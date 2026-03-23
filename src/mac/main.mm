#import <AppKit/AppKit.h>

#include <CoreGraphics/CoreGraphics.h>
#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <dispatch/dispatch.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "core/document.h"
#include "core/page_cache.h"
#include "core/viewport.h"

struct PageRenderCacheEntry {
  NSImage* image;
  long long requestId;

  PageRenderCacheEntry() : image(nil), requestId(0) {}
};

@interface FlippedDocumentView : NSView
@end

@implementation FlippedDocumentView

- (BOOL)isFlipped {
  return YES;
}

@end

@interface PDFTabContext : NSObject {
 @public
  pdfview::core::DocumentPtr document_;
  std::string documentPath_;
  NSView* containerView_;
  NSScrollView* scrollView_;
  FlippedDocumentView* documentView_;
  std::vector<pdfview::core::PageSize> pageSizes_;
  std::vector<NSImageView*> pageImageViews_;
  std::vector<pdfview::core::PageCacheSlotState> pageCacheStates_;
  std::vector<PageRenderCacheEntry> pageCache_;
  std::vector<pdfview::core::ViewRect> pageFrames_;
  int currentPage_;
  float manualScale_;
  float lastRenderScale_;
  BOOL useFitScale_;
}

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame;
- (NSString*)tabTitle;
- (float)fitScaleForViewportWidth:(CGFloat)viewportWidth;
- (float)currentScaleForViewportWidth:(CGFloat)viewportWidth;
- (void)invalidateRenderedPages;
- (pdfview::core::PageLayoutResult)layoutPagesForViewportSize:(NSSize)viewportSize;
- (pdfview::core::PageCachePlan)pageCachePlanForVisibleRect:(const pdfview::core::ViewRect&)visibleRect;
- (pdfview::core::PageRenderPlan)renderPlanForVisibleRect:(const pdfview::core::ViewRect&)visibleRect
                                            deviceScale:(CGFloat)deviceScale;
- (BOOL)isRenderRequestCurrent:(int)pageIndex
                   renderScale:(float)renderScale
                     requestId:(long long)requestId;
- (void)markPageDiscarded:(int)pageIndex;
- (void)markPageRendered:(int)pageIndex renderScale:(float)renderScale;
- (void)markPageRequested:(int)pageIndex renderScale:(float)renderScale requestId:(long long)requestId;
- (void)setManualScale:(float)scale;
- (void)setUseFitScale:(BOOL)useFitScale;

@end

namespace {

NSRect NSRectFromViewRect(const pdfview::core::ViewRect& rect) {
  return NSMakeRect(rect.x, rect.y, rect.width, rect.height);
}

pdfview::core::ViewRect ViewRectFromNSRect(const NSRect& rect) {
  pdfview::core::ViewRect result;
  result.x = rect.origin.x;
  result.y = rect.origin.y;
  result.width = rect.size.width;
  result.height = rect.size.height;
  return result;
}

}  // namespace

namespace {

bool RenderProfilingEnabled() {
  static const bool enabled = []() -> bool {
    const char* value = std::getenv("PDFVIEW_PROFILE_RENDER");
    return value != NULL && value[0] != '\0' && value[0] != '0';
  }();
  return enabled;
}

double MillisecondsSince(const std::chrono::steady_clock::time_point& start) {
  return std::chrono::duration_cast<std::chrono::duration<double, std::milli> >(
             std::chrono::steady_clock::now() - start)
      .count();
}

}  // namespace

@implementation PDFTabContext

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame {
  self = [super init];
  if (self != nil) {
    document_ = document;
    documentPath_ = path;
    currentPage_ = 0;
    manualScale_ = 1.0f;
    lastRenderScale_ = 0.0f;
    useFitScale_ = NO;

    const int pageCount = document_ ? document_->page_count() : 0;
    pageSizes_.resize(pageCount);
    pageImageViews_.resize(pageCount, nil);
    pageCacheStates_ = pdfview::core::make_page_cache_states(pageCount);
    pageCache_.resize(pageCount);
    pageFrames_.resize(pageCount);
    for (int pageIndex = 0; pageIndex < pageCount; ++pageIndex) {
      pageSizes_[pageIndex] = document_->page_size(pageIndex);
    }

    containerView_ = [[NSView alloc] initWithFrame:frame];
    [containerView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    scrollView_ = [[NSScrollView alloc] initWithFrame:frame];
    [scrollView_ setHasVerticalScroller:YES];
    [scrollView_ setHasHorizontalScroller:YES];
    [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scrollView_ setBorderType:NSNoBorder];
    [scrollView_ setBackgroundColor:[NSColor colorWithCalibratedWhite:0.92 alpha:1.0]];
    [[scrollView_ contentView] setPostsBoundsChangedNotifications:YES];

    documentView_ = [[FlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [documentView_ setWantsLayer:YES];
    [[documentView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
    [scrollView_ setDocumentView:documentView_];
    [containerView_ addSubview:scrollView_];
  }
  return self;
}

- (NSString*)tabTitle {
  NSString* path = [NSString stringWithUTF8String:documentPath_.c_str()];
  return [path lastPathComponent];
}

- (float)fitScaleForViewportWidth:(CGFloat)viewportWidth {
  if (!document_ || pageSizes_.empty()) {
    return 1.0f;
  }

  return pdfview::core::compute_fit_scale(pageSizes_, viewportWidth, 48.0f, 0.25f);
}

- (float)currentScaleForViewportWidth:(CGFloat)viewportWidth {
  if (useFitScale_) {
    return [self fitScaleForViewportWidth:viewportWidth];
  }
  return std::max(0.1f, manualScale_);
}

- (void)invalidateRenderedPages {
  pdfview::core::invalidate_page_cache(&pageCacheStates_);
  for (size_t pageIndex = 0; pageIndex < pageCache_.size(); ++pageIndex) {
    pageCache_[pageIndex].image = nil;
    pageCache_[pageIndex].requestId = 0;
    if (pageImageViews_[pageIndex] != nil) {
      [pageImageViews_[pageIndex] setImage:nil];
    }
  }
  lastRenderScale_ = 0.0f;
}

- (pdfview::core::PageLayoutResult)layoutPagesForViewportSize:(NSSize)viewportSize {
  pdfview::core::PageLayoutConfig layoutConfig;
  layoutConfig.viewport_width = viewportSize.width;
  layoutConfig.viewport_height = viewportSize.height;
  layoutConfig.zoom = [self currentScaleForViewportWidth:viewportSize.width];
  layoutConfig.top_margin = 20.0f;
  layoutConfig.side_margin = 16.0f;
  layoutConfig.page_gap = 24.0f;

  const pdfview::core::PageLayoutResult layoutResult =
      pdfview::core::compute_continuous_page_layout(pageSizes_, layoutConfig);
  pageFrames_ = layoutResult.page_frames;
  return layoutResult;
}

- (pdfview::core::PageCachePlan)pageCachePlanForVisibleRect:(const pdfview::core::ViewRect&)visibleRect {
  return pdfview::core::compute_page_cache_plan(pageFrames_, visibleRect, visibleRect.height * 0.5f);
}

- (pdfview::core::PageRenderPlan)renderPlanForVisibleRect:(const pdfview::core::ViewRect&)visibleRect
                                            deviceScale:(CGFloat)deviceScale {
  const float renderScale =
      [self currentScaleForViewportWidth:visibleRect.width] * static_cast<float>(deviceScale);
  const pdfview::core::PageCachePlan cachePlan = [self pageCachePlanForVisibleRect:visibleRect];
  return pdfview::core::plan_page_rendering(cachePlan.preload_range,
                                            pageCacheStates_,
                                            pageFrames_,
                                            visibleRect,
                                            renderScale);
}

- (BOOL)isRenderRequestCurrent:(int)pageIndex
                   renderScale:(float)renderScale
                     requestId:(long long)requestId {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return NO;
  }

  const PageRenderCacheEntry& cacheEntry = pageCache_[pageIndex];
  const pdfview::core::PageCacheSlotState& state = pageCacheStates_[pageIndex];
  return cacheEntry.requestId == requestId && state.pending && state.render_scale == renderScale;
}

- (void)markPageDiscarded:(int)pageIndex {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return;
  }

  pageCache_[pageIndex].image = nil;
  pageCache_[pageIndex].requestId = 0;
  pdfview::core::mark_page_cache_discarded(&pageCacheStates_, pageIndex);
}

- (void)markPageRendered:(int)pageIndex renderScale:(float)renderScale {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return;
  }

  pageCache_[pageIndex].requestId = 0;
  pdfview::core::mark_page_cache_rendered(&pageCacheStates_, pageIndex, renderScale);
  lastRenderScale_ = renderScale;
}

- (void)markPageRequested:(int)pageIndex renderScale:(float)renderScale requestId:(long long)requestId {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return;
  }

  pageCache_[pageIndex].requestId = requestId;
  pdfview::core::mark_page_cache_requested(&pageCacheStates_, pageIndex, renderScale);
}

- (void)setManualScale:(float)scale {
  manualScale_ = scale;
}

- (void)setUseFitScale:(BOOL)useFitScale {
  useFitScale_ = useFitScale;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTabViewDelegate, NSComboBoxDelegate, NSTextFieldDelegate>
- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv;
- (void)installMainMenu;
- (void)installToolbarStripInView:(NSView*)contentView;
- (void)layoutChrome;
- (void)updateToolbarForActiveTab;
- (BOOL)applyZoomString:(NSString*)rawValue;
- (IBAction)zoomComboBoxChanged:(id)sender;
- (void)presentError:(NSString*)message;
- (CGFloat)deviceScaleFactor;
- (NSImage*)imageFromBitmap:(const pdfview::core::Bitmap&)bitmap
                displaySize:(NSSize)displaySize;
- (void)loadInitialDocuments;
- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive;
- (void)renderTabContext:(PDFTabContext*)context;
- (void)updateVisiblePagesForContext:(PDFTabContext*)context;
- (void)applyRenderedPage:(const pdfview::core::RenderPageResult&)renderResult
               forRequest:(const pdfview::core::PageRenderRequest&)request
                requestId:(long long)requestId
                  context:(PDFTabContext*)context
                   pdfMs:(double)pdfMilliseconds;
- (BOOL)isContextActive:(PDFTabContext*)context;
- (CGFloat)effectiveDeviceScaleForContext:(PDFTabContext*)context;
- (void)beginInteractiveRenderingForContext:(PDFTabContext*)context;
- (void)endInteractiveRendering:(NSTimer*)timer;
- (void)cancelInteractiveRendering;
- (float)fitScaleForContext:(PDFTabContext*)context;
- (float)currentScaleForContext:(PDFTabContext*)context;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoomToFit;
- (void)goToNextPage;
- (void)goToPreviousPage;
- (void)scrollToCurrentPageInContext:(PDFTabContext*)context;
- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context;
- (void)installKeyMonitor;
- (PDFTabContext*)activeTabContext;
- (PDFTabContext*)contextForClipView:(NSClipView*)clipView;
- (IBAction)openDocument:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)showHelp:(id)sender;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSTabView* tabView_;
  NSView* toolbarStrip_;
  NSComboBox* zoomComboBox_;
  NSButton* zoomOutButton_;
  NSButton* zoomInButton_;
  BOOL zoomComboBoxEditing_;
  NSMutableArray* tabContexts_;
  dispatch_queue_t renderQueue_;
  long long nextRenderRequestId_;
  NSTimer* interactiveRenderTimer_;
  PDFTabContext* interactiveRenderContext_;
  id keyMonitor_;
  int argc_;
  const char** argv_;
}

- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv {
  self = [super init];
  if (self != nil) {
    argc_ = argc;
    argv_ = argv;
    keyMonitor_ = nil;
    zoomComboBoxEditing_ = NO;
    renderQueue_ = dispatch_queue_create("com.pdfview.render", DISPATCH_QUEUE_SERIAL);
    nextRenderRequestId_ = 1;
    interactiveRenderTimer_ = nil;
    interactiveRenderContext_ = nil;
    tabContexts_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  NSRect frame = NSMakeRect(0, 0, 1080, 800);
  window_ = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSWindowStyleMaskTitled |
                                                  NSWindowStyleMaskClosable |
                                                  NSWindowStyleMaskMiniaturizable |
                                                  NSWindowStyleMaskResizable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

  [window_ center];
  [window_ setTitle:@"pdfview"];
  [window_ setDelegate:self];

  [self installMainMenu];

  NSView* contentView = [window_ contentView];
  tabView_ = [[NSTabView alloc] initWithFrame:[contentView bounds]];
  [tabView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [tabView_ setTabViewType:NSTopTabsBezelBorder];
  [tabView_ setDelegate:self];
  [contentView addSubview:tabView_];
  [self installToolbarStripInView:contentView];
  [self layoutChrome];

  [self installKeyMonitor];
  [self loadInitialDocuments];
  [window_ makeKeyAndOrderFront:nil];
}

- (void)installMainMenu {
  NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

  NSMenuItem* appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:appMenuItem];
  NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"pdfview"];
  NSMenuItem* quitItem =
      [[NSMenuItem alloc] initWithTitle:@"Quit pdfview"
                                 action:@selector(terminate:)
                          keyEquivalent:@"q"];
  [appMenu addItem:quitItem];
  [appMenuItem setSubmenu:appMenu];

  NSMenuItem* fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:fileMenuItem];
  NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  NSMenuItem* openItem = [[NSMenuItem alloc] initWithTitle:@"Open..."
                                                    action:@selector(openDocument:)
                                             keyEquivalent:@"o"];
  [openItem setTarget:self];
  [fileMenu addItem:openItem];

  NSMenuItem* closeTabItem = [[NSMenuItem alloc] initWithTitle:@"Close Tab"
                                                        action:@selector(closeCurrentTab:)
                                                 keyEquivalent:@"w"];
  [closeTabItem setTarget:self];
  [fileMenu addItem:closeTabItem];
  [fileMenuItem setSubmenu:fileMenu];

  NSMenuItem* windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:windowMenuItem];
  NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
  NSMenuItem* minimizeItem = [[NSMenuItem alloc] initWithTitle:@"Minimize"
                                                        action:@selector(performMiniaturize:)
                                                 keyEquivalent:@"m"];
  [windowMenu addItem:minimizeItem];
  NSMenuItem* zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom"
                                                    action:@selector(performZoom:)
                                             keyEquivalent:@""];
  [windowMenu addItem:zoomItem];
  [windowMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem* bringAllToFrontItem =
      [[NSMenuItem alloc] initWithTitle:@"Bring All to Front"
                                 action:@selector(arrangeInFront:)
                          keyEquivalent:@""];
  [windowMenu addItem:bringAllToFrontItem];
  [windowMenuItem setSubmenu:windowMenu];
  [NSApp setWindowsMenu:windowMenu];

  NSMenuItem* helpMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:helpMenuItem];
  NSMenu* helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
  NSMenuItem* helpItem = [[NSMenuItem alloc] initWithTitle:@"pdfview Help"
                                                    action:@selector(showHelp:)
                                             keyEquivalent:@"?"];
  [helpItem setTarget:self];
  [helpMenu addItem:helpItem];
  [helpMenuItem setSubmenu:helpMenu];
  [NSApp setHelpMenu:helpMenu];

  [NSApp setMainMenu:mainMenu];
}

- (void)installToolbarStripInView:(NSView*)contentView {
  toolbarStrip_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 32)];
  [toolbarStrip_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [toolbarStrip_ setWantsLayer:YES];
  [[toolbarStrip_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.965 alpha:1.0] CGColor]];
  [contentView addSubview:toolbarStrip_];

  NSBox* divider = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
  [divider setBoxType:NSBoxSeparator];
  [divider setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [toolbarStrip_ addSubview:divider];

  zoomOutButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(12, 4, 26, 22)];
  [zoomOutButton_ setTitle:@"-"];
  [zoomOutButton_ setBezelStyle:NSBezelStyleTexturedRounded];
  [zoomOutButton_ setTarget:self];
  [zoomOutButton_ setAction:@selector(zoomOut)];
  [toolbarStrip_ addSubview:zoomOutButton_];

  zoomComboBox_ = [[NSComboBox alloc] initWithFrame:NSMakeRect(44, 3, 92, 24)];
  [zoomComboBox_ setUsesDataSource:NO];
  [zoomComboBox_ setCompletes:NO];
  [zoomComboBox_ setEditable:YES];
  [zoomComboBox_ setDelegate:self];
  [[zoomComboBox_ cell] setWraps:NO];
  [zoomComboBox_ addItemsWithObjectValues:[NSArray arrayWithObjects:@"50%", @"75%", @"100%", @"125%", @"150%", @"200%", @"300%", nil]];
  [toolbarStrip_ addSubview:zoomComboBox_];

  zoomInButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(142, 4, 26, 22)];
  [zoomInButton_ setTitle:@"+"];
  [zoomInButton_ setBezelStyle:NSBezelStyleTexturedRounded];
  [zoomInButton_ setTarget:self];
  [zoomInButton_ setAction:@selector(zoomIn)];
  [toolbarStrip_ addSubview:zoomInButton_];
}

- (void)layoutChrome {
  PDFTabContext* context = [self activeTabContext];
  if (tabView_ == nil || toolbarStrip_ == nil || context == nil) {
    return;
  }

  const CGFloat toolbarHeight = 32.0f;
  const NSRect contentRect = [tabView_ contentRect];
  [context->containerView_ setFrame:contentRect];
  [toolbarStrip_ removeFromSuperview];
  [context->containerView_ addSubview:toolbarStrip_];
  [toolbarStrip_ setFrame:NSMakeRect(0,
                                     contentRect.size.height - toolbarHeight,
                                     contentRect.size.width,
                                     toolbarHeight)];

  const NSRect documentFrame = NSMakeRect(0,
                                          0,
                                          contentRect.size.width,
                                          std::max(contentRect.size.height - toolbarHeight, 0.0));
  [context->scrollView_ setFrame:documentFrame];
}

- (void)updateToolbarForActiveTab {
  if (zoomComboBox_ == nil) {
    return;
  }

  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    [zoomComboBox_ setStringValue:@""];
    [zoomComboBox_ setEnabled:NO];
    return;
  }

  if (zoomComboBoxEditing_) {
    return;
  }

  [zoomComboBox_ setEnabled:YES];
  [zoomComboBox_ setStringValue:[NSString stringWithFormat:@"%.0f%%",
                                                           [self currentScaleForContext:context] * 100.0f]];
}

- (BOOL)applyZoomString:(NSString*)rawValue {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil || zoomComboBox_ == nil) {
    return NO;
  }

  NSString* normalizedValue =
      [[rawValue stringByReplacingOccurrencesOfString:@"%" withString:@""]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  const CGFloat zoomPercent = [normalizedValue doubleValue];
  if (zoomPercent <= 0.0) {
    [self updateToolbarForActiveTab];
    return NO;
  }

  context->manualScale_ = std::max(static_cast<float>(zoomPercent / 100.0), 0.1f);
  context->useFitScale_ = NO;
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
  return YES;
}

- (IBAction)zoomComboBoxChanged:(id)sender {
  (void)sender;
}

- (void)comboBoxSelectionDidChange:(NSNotification*)notification {
  if ([notification object] != zoomComboBox_) {
    return;
  }

  zoomComboBoxEditing_ = NO;
  const NSInteger selectedIndex = [zoomComboBox_ indexOfSelectedItem];
  if (selectedIndex >= 0) {
    id value = [zoomComboBox_ objectValueOfSelectedItem];
    if ([value isKindOfClass:[NSString class]]) {
      [self applyZoomString:(NSString*)value];
      return;
    }
  }
  [self updateToolbarForActiveTab];
}

- (void)controlTextDidBeginEditing:(NSNotification*)notification {
  if ([notification object] == zoomComboBox_) {
    zoomComboBoxEditing_ = YES;
  }
}

- (void)controlTextDidEndEditing:(NSNotification*)notification {
  if ([notification object] == zoomComboBox_) {
    zoomComboBoxEditing_ = NO;
    [self updateToolbarForActiveTab];
  }
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
  (void)textView;
  if (control != zoomComboBox_) {
    return NO;
  }

  if (commandSelector == @selector(insertNewline:)) {
    zoomComboBoxEditing_ = NO;
    const BOOL applied = [self applyZoomString:[zoomComboBox_ stringValue]];
    if (applied) {
      [[window_ firstResponder] resignFirstResponder];
    }
    return YES;
  }

  if (commandSelector == @selector(cancelOperation:)) {
    zoomComboBoxEditing_ = NO;
    [self updateToolbarForActiveTab];
    [[window_ firstResponder] resignFirstResponder];
    return YES;
  }

  return NO;
}

- (void)presentError:(NSString*)message {
  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleCritical];
  [alert setMessageText:@"pdfview"];
  [alert setInformativeText:message];
  [alert runModal];
}

- (void)loadInitialDocuments {
  for (int index = 1; index < argc_; ++index) {
    [self openDocumentAtPath:argv_[index] makeActive:index == argc_ - 1];
  }
}

- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive {
  const pdfview::core::OpenDocumentResult result = pdfview::core::open_document(path);
  if (!result.ok()) {
    [self presentError:[NSString stringWithFormat:@"Failed to open PDF: %s", result.error.c_str()]];
    return;
  }

  PDFTabContext* context =
      [[PDFTabContext alloc] initWithDocument:result.document
                                         path:path
                                        frame:NSMakeRect(0, 0, 100, 100)];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(tabClipViewDidScroll:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:[context->scrollView_ contentView]];

  NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:context];
  [item setLabel:[context tabTitle]];
  [item setView:context->containerView_];
  [tabContexts_ addObject:context];
  [tabView_ addTabViewItem:item];

  if (makeActive || [tabView_ numberOfTabViewItems] == 1) {
    [tabView_ selectTabViewItem:item];
    [self layoutChrome];
    [self renderTabContext:context];
    [self scrollToCurrentPageInContext:context];
  } else {
    [self layoutChrome];
    [self renderTabContext:context];
  }

  [self updateToolbarForActiveTab];
}

- (IBAction)openDocument:(id)sender {
  (void)sender;
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:YES];
  [panel setAllowedContentTypes:[NSArray arrayWithObject:UTTypePDF]];

  if ([panel runModal] != NSModalResponseOK) {
    return;
  }

  for (NSURL* url in [panel URLs]) {
    [self openDocumentAtPath:[[url path] UTF8String] makeActive:YES];
  }
}

- (IBAction)closeCurrentTab:(id)sender {
  (void)sender;
  NSTabViewItem* selectedItem = [tabView_ selectedTabViewItem];
  if (selectedItem == nil) {
    return;
  }

  PDFTabContext* context = (PDFTabContext*)[selectedItem identifier];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:[context->scrollView_ contentView]];
  [tabContexts_ removeObject:context];
  [tabView_ removeTabViewItem:selectedItem];

  if ([tabView_ numberOfTabViewItems] == 0) {
    [window_ setTitle:@"pdfview"];
  }
  [self layoutChrome];
  [self updateToolbarForActiveTab];
}

- (IBAction)showHelp:(id)sender {
  (void)sender;
  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleInformational];
  [alert setMessageText:@"pdfview Help"];
  [alert setInformativeText:@"Use File > Open... to open PDFs, tabs to switch documents, Cmd+W to close the current tab, and Cmd+Q to quit."];
  [alert runModal];
}

- (PDFTabContext*)activeTabContext {
  NSTabViewItem* item = [tabView_ selectedTabViewItem];
  if (item == nil) {
    return nil;
  }
  return (PDFTabContext*)[item identifier];
}

- (PDFTabContext*)contextForClipView:(NSClipView*)clipView {
  for (PDFTabContext* context in tabContexts_) {
    if ([context->scrollView_ contentView] == clipView) {
      return context;
    }
  }
  return nil;
}

- (BOOL)isContextActive:(PDFTabContext*)context {
  return context != nil && context == [self activeTabContext];
}

- (CGFloat)effectiveDeviceScaleForContext:(PDFTabContext*)context {
  CGFloat deviceScale = [self deviceScaleFactor];
  if (context != nil && context == interactiveRenderContext_) {
    deviceScale = std::max(1.0, deviceScale * 0.5);
  }
  return deviceScale;
}

- (void)beginInteractiveRenderingForContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  interactiveRenderContext_ = context;
  if (interactiveRenderTimer_ != nil) {
    [interactiveRenderTimer_ invalidate];
    interactiveRenderTimer_ = nil;
  }
  interactiveRenderTimer_ =
      [NSTimer scheduledTimerWithTimeInterval:0.12
                                       target:self
                                     selector:@selector(endInteractiveRendering:)
                                     userInfo:nil
                                      repeats:NO];
  [[NSRunLoop mainRunLoop] addTimer:interactiveRenderTimer_ forMode:NSRunLoopCommonModes];
}

- (void)endInteractiveRendering:(NSTimer*)timer {
  if (timer != interactiveRenderTimer_) {
    return;
  }

  interactiveRenderTimer_ = nil;
  PDFTabContext* context = interactiveRenderContext_;
  interactiveRenderContext_ = nil;
  if ([self isContextActive:context]) {
    [self updateVisiblePagesForContext:context];
  }
}

- (void)cancelInteractiveRendering {
  if (interactiveRenderTimer_ != nil) {
    [interactiveRenderTimer_ invalidate];
    interactiveRenderTimer_ = nil;
  }
  interactiveRenderContext_ = nil;
}

- (void)renderTabContext:(PDFTabContext*)context {
  if (context == nil || !context->document_) {
    return;
  }

  const std::chrono::steady_clock::time_point passStart = std::chrono::steady_clock::now();
  const CGFloat deviceScale = [self effectiveDeviceScaleForContext:context];
  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;
  const float logicalScale = [context currentScaleForViewportWidth:clipSize.width];
  const float renderScale = logicalScale * static_cast<float>(deviceScale);

  if (std::abs(context->lastRenderScale_ - renderScale) > 0.001f) {
    [context invalidateRenderedPages];
  }

  const pdfview::core::PageLayoutResult layoutResult =
      [context layoutPagesForViewportSize:clipSize];
  const double layoutMilliseconds = MillisecondsSince(passStart);

  const int pageCount = static_cast<int>(context->pageFrames_.size());
  for (int pageIndex = 0; pageIndex < pageCount; ++pageIndex) {
    NSImageView* imageView = context->pageImageViews_[pageIndex];
    if (imageView == nil) {
      imageView = [[NSImageView alloc]
          initWithFrame:NSRectFromViewRect(context->pageFrames_[pageIndex])];
      [imageView setImageAlignment:NSImageAlignCenter];
      [imageView setImageScaling:NSImageScaleNone];
      [imageView setWantsLayer:YES];
      [[imageView layer] setBackgroundColor:[[NSColor whiteColor] CGColor]];
      context->pageImageViews_[pageIndex] = imageView;
      [context->documentView_ addSubview:imageView];
    }

    [imageView setFrame:NSRectFromViewRect(context->pageFrames_[pageIndex])];
  }

  [context->documentView_
      setFrame:NSMakeRect(0,
                          0,
                          layoutResult.document_width,
                          layoutResult.document_height)];
  if ([self isContextActive:context]) {
    [self updateVisiblePagesForContext:context];
  }

  if (RenderProfilingEnabled()) {
    const double totalMilliseconds = MillisecondsSince(passStart);
    std::fprintf(stderr,
                 "[pdfview] render_tab layout_ms=%.2f total_ms=%.2f pages=%d scale=%.3f\n",
                 layoutMilliseconds,
                 totalMilliseconds,
                 pageCount,
                 renderScale);
  }
}

- (void)updateVisiblePagesForContext:(PDFTabContext*)context {
  if (context == nil || context->pageFrames_.empty()) {
    return;
  }

  if (![self isContextActive:context]) {
    return;
  }

  const std::chrono::steady_clock::time_point passStart = std::chrono::steady_clock::now();
  double pdfRenderMilliseconds = 0.0;
  double imageDecodeMilliseconds = 0.0;
  double imageApplyMilliseconds = 0.0;
  int renderedPageCount = 0;
  int discardedPageCount = 0;
  int keptPageCount = 0;
  long long renderedPixelCount = 0;
  const pdfview::core::ViewRect visibleRect =
      ViewRectFromNSRect([[context->scrollView_ contentView] bounds]);
  const CGFloat deviceScale = [self effectiveDeviceScaleForContext:context];
  const pdfview::core::PageRenderPlan renderPlan =
      [context renderPlanForVisibleRect:visibleRect deviceScale:deviceScale];

  for (size_t discardIndex = 0; discardIndex < renderPlan.pages_to_discard.size(); ++discardIndex) {
    const int pageIndex = renderPlan.pages_to_discard[discardIndex];
    const std::chrono::steady_clock::time_point applyStart = std::chrono::steady_clock::now();
    [context markPageDiscarded:pageIndex];
    NSImageView* imageView = context->pageImageViews_[pageIndex];
    if (imageView != nil) {
      [imageView setImage:nil];
    }
    imageApplyMilliseconds += MillisecondsSince(applyStart);
    discardedPageCount += 1;
  }

  for (size_t renderIndex = 0; renderIndex < renderPlan.render_requests.size(); ++renderIndex) {
    const pdfview::core::PageRenderRequest& request = renderPlan.render_requests[renderIndex];
    const int pageIndex = request.page_index;
    NSImageView* imageView = context->pageImageViews_[pageIndex];
    if (imageView == nil) {
      continue;
    }

    const long long requestId = nextRenderRequestId_++;
    [context markPageRequested:pageIndex renderScale:request.render_scale requestId:requestId];
    const pdfview::core::DocumentPtr document = context->document_;
    PDFTabContext* retainedContext = context;
    const pdfview::core::PageRenderRequest requestCopy = request;
    dispatch_async(renderQueue_, ^{
      __block BOOL shouldRender = NO;
      dispatch_sync(dispatch_get_main_queue(), ^{
        shouldRender = [retainedContext isRenderRequestCurrent:requestCopy.page_index
                                                   renderScale:requestCopy.render_scale
                                                     requestId:requestId];
      });
      if (!shouldRender) {
        if (RenderProfilingEnabled()) {
          std::fprintf(stderr,
                       "[pdfview] page_skip page=%d scale=%.3f request=%lld reason=stale_before_render\n",
                       requestCopy.page_index,
                       requestCopy.render_scale,
                       requestId);
        }
        return;
      }

      const std::chrono::steady_clock::time_point pdfRenderStart = std::chrono::steady_clock::now();
      const pdfview::core::RenderPageResult renderResult =
          document->render_page(requestCopy.page_index, requestCopy.render_scale);
      const double pdfMilliseconds = MillisecondsSince(pdfRenderStart);
      dispatch_async(dispatch_get_main_queue(), ^{
        [self applyRenderedPage:renderResult
                     forRequest:requestCopy
                      requestId:requestId
                        context:retainedContext
                         pdfMs:pdfMilliseconds];
      });
    });

    pdfRenderMilliseconds += 0.0;
    renderedPageCount += 1;
  }

  for (int pageIndex = renderPlan.keep_range.start; pageIndex < renderPlan.keep_range.end; ++pageIndex) {
    NSImageView* imageView = context->pageImageViews_[pageIndex];
    if (imageView != nil && context->pageCache_[pageIndex].image != nil) {
      const std::chrono::steady_clock::time_point applyStart = std::chrono::steady_clock::now();
      [imageView setImage:context->pageCache_[pageIndex].image];
      imageApplyMilliseconds += MillisecondsSince(applyStart);
      keptPageCount += 1;
    }
  }

  if (RenderProfilingEnabled()) {
    const double totalMilliseconds = MillisecondsSince(passStart);
    std::fprintf(stderr,
                 "[pdfview] visible_update total_ms=%.2f pdf_ms=%.2f image_decode_ms=%.2f "
                 "image_apply_ms=%.2f rendered=%d discarded=%d kept=%d pixels=%lld keep_range=%d..%d\n",
                 totalMilliseconds,
                 pdfRenderMilliseconds,
                 imageDecodeMilliseconds,
                 imageApplyMilliseconds,
                 renderedPageCount,
                 discardedPageCount,
                 keptPageCount,
                 renderedPixelCount,
                 renderPlan.keep_range.start,
                 renderPlan.keep_range.end);
  }
}

- (void)applyRenderedPage:(const pdfview::core::RenderPageResult&)renderResult
               forRequest:(const pdfview::core::PageRenderRequest&)request
                requestId:(long long)requestId
                  context:(PDFTabContext*)context
                   pdfMs:(double)pdfMilliseconds {
  if (context == nil ||
      request.page_index < 0 ||
      request.page_index >= static_cast<int>(context->pageCache_.size())) {
    return;
  }

  PageRenderCacheEntry& cacheEntry = context->pageCache_[request.page_index];
  if (cacheEntry.requestId != requestId) {
    return;
  }

  if (!renderResult.ok()) {
    [context markPageDiscarded:request.page_index];
    [self presentError:[NSString stringWithFormat:@"Failed to render page %d: %s",
                                                  request.page_index + 1,
                                                  renderResult.error.c_str()]];
    return;
  }

  const std::chrono::steady_clock::time_point imageDecodeStart = std::chrono::steady_clock::now();
  cacheEntry.image =
      [self imageFromBitmap:renderResult.bitmap
                displaySize:NSMakeSize(request.display_width, request.display_height)];
  const double imageDecodeMilliseconds = MillisecondsSince(imageDecodeStart);

  double imageApplyMilliseconds = 0.0;
  NSImageView* imageView = context->pageImageViews_[request.page_index];
  if (imageView != nil) {
    const std::chrono::steady_clock::time_point imageApplyStart = std::chrono::steady_clock::now();
    [imageView setImage:cacheEntry.image];
    imageApplyMilliseconds = MillisecondsSince(imageApplyStart);
  }

  [context markPageRendered:request.page_index renderScale:request.render_scale];

  if (RenderProfilingEnabled()) {
    std::fprintf(stderr,
                 "[pdfview] page_render page=%d scale=%.3f pdf_ms=%.2f decode_ms=%.2f apply_ms=%.2f pixels=%d\n",
                 request.page_index,
                 request.render_scale,
                 pdfMilliseconds,
                 imageDecodeMilliseconds,
                 imageApplyMilliseconds,
                 renderResult.bitmap.width * renderResult.bitmap.height);
  }
}

- (float)fitScaleForContext:(PDFTabContext*)context {
  if (context == nil || !context->document_ || context->document_->page_count() <= 0) {
    return 1.0f;
  }

  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;
  return [context fitScaleForViewportWidth:clipSize.width];
}

- (float)currentScaleForContext:(PDFTabContext*)context {
  if (context->useFitScale_) {
    return [self fitScaleForContext:context];
  }
  return std::max(0.1f, context->manualScale_);
}

- (void)zoomIn {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [context setManualScale:std::min([self currentScaleForContext:context] * 1.25f, 5.0f)];
  [context setUseFitScale:NO];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)zoomOut {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [context setManualScale:std::max([self currentScaleForContext:context] / 1.25f, 0.1f)];
  [context setUseFitScale:NO];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)resetZoomToFit {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [context setUseFitScale:YES];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)goToNextPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil || context->currentPage_ + 1 >= context->document_->page_count()) {
    return;
  }

  context->currentPage_ += 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)goToPreviousPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil || context->currentPage_ <= 0) {
    return;
  }

  context->currentPage_ -= 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)scrollToCurrentPageInContext:(PDFTabContext*)context {
  if (context == nil ||
      context->currentPage_ < 0 ||
      context->currentPage_ >= static_cast<int>(context->pageFrames_.size())) {
    return;
  }

  [self cancelInteractiveRendering];
  const NSRect pageFrame = NSRectFromViewRect(context->pageFrames_[context->currentPage_]);
  [[context->scrollView_ documentView] scrollRectToVisible:pageFrame];
  [self updateVisiblePagesForContext:context];
}

- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context {
  if (context == nil || context->pageFrames_.empty()) {
    return;
  }

  const NSRect visibleRect = [[context->scrollView_ contentView] bounds];
  context->currentPage_ = pdfview::core::find_nearest_page_to_viewport_center(
      context->pageFrames_, visibleRect.origin.y, visibleRect.size.height);
}

- (void)tabClipViewDidScroll:(NSNotification*)notification {
  PDFTabContext* context = [self contextForClipView:(NSClipView*)[notification object]];
  [self updateCurrentPageFromScrollForContext:context];
  [self beginInteractiveRenderingForContext:context];
  [self updateVisiblePagesForContext:context];
}

- (void)installKeyMonitor {
  keyMonitor_ = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                      handler:^NSEvent*(NSEvent* event) {
    if (zoomComboBoxEditing_) {
      return event;
    }

    id firstResponder = [window_ firstResponder];
    if ([firstResponder isKindOfClass:[NSTextView class]]) {
      NSTextView* textView = (NSTextView*)firstResponder;
      if ([textView delegate] == (id)zoomComboBox_) {
        return event;
      }
    }

    PDFTabContext* context = [self activeTabContext];
    if (context == nil) {
      return event;
    }

    NSString* characters = [event charactersIgnoringModifiers];
    if ([characters length] == 0) {
      return event;
    }

    const unichar key = [characters characterAtIndex:0];
    if (key == '+' || key == '=') {
      [self zoomIn];
      return nil;
    }
    if (key == '-') {
      [self zoomOut];
      return nil;
    }
    if (key == '0') {
      [self resetZoomToFit];
      return nil;
    }
    if (key == NSRightArrowFunctionKey || key == NSDownArrowFunctionKey ||
        key == 'j' || key == 'n') {
      [self goToNextPage];
      return nil;
    }
    if (key == NSLeftArrowFunctionKey || key == NSUpArrowFunctionKey ||
        key == 'k' || key == 'p') {
      [self goToPreviousPage];
      return nil;
    }

  return event;
  }];
}

- (CGFloat)deviceScaleFactor {
  NSScreen* screen = [window_ screen];
  if (screen != nil) {
    return std::max([screen backingScaleFactor], 1.0);
  }
  return 1.0;
}

- (NSImage*)imageFromBitmap:(const pdfview::core::Bitmap&)bitmap
                displaySize:(NSSize)displaySize {
  NSData* bitmapData =
      [NSData dataWithBytes:bitmap.pixels.data() length:bitmap.pixels.size()];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)bitmapData);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGImageRef cgImage = CGImageCreate(bitmap.width,
                                     bitmap.height,
                                     8,
                                     32,
                                     bitmap.stride,
                                     colorSpace,
                                     kCGBitmapByteOrder32Little |
                                         kCGImageAlphaPremultipliedFirst,
                                     provider,
                                     NULL,
                                     false,
                                     kCGRenderingIntentDefault);
  NSImage* image = [[NSImage alloc] initWithCGImage:cgImage
                                               size:displaySize];
  CGImageRelease(cgImage);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}

- (void)tabView:(NSTabView*)tabView didSelectTabViewItem:(NSTabViewItem*)tabViewItem {
  (void)tabView;
  [self cancelInteractiveRendering];
  PDFTabContext* context = (PDFTabContext*)[tabViewItem identifier];
  if (context != nil) {
    [window_ setTitle:[NSString stringWithFormat:@"pdfview - %@", [context tabTitle]]];
    [self layoutChrome];
    [self renderTabContext:context];
  }
  [self updateToolbarForActiveTab];
}

- (void)windowDidResize:(NSNotification*)notification {
  (void)notification;
  [self layoutChrome];
  for (PDFTabContext* context in tabContexts_) {
    if (context != [self activeTabContext]) {
      const CGFloat toolbarHeight = 32.0f;
      const NSRect contentRect = [tabView_ contentRect];
      [context->containerView_ setFrame:contentRect];
      [context->scrollView_ setFrame:NSMakeRect(0,
                                                0,
                                                contentRect.size.width,
                                                std::max(contentRect.size.height - toolbarHeight, 0.0))];
    }
    [self renderTabContext:context];
    if (context->useFitScale_) {
      [self scrollToCurrentPageInContext:context];
    }
  }
  [self updateToolbarForActiveTab];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  (void)notification;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self cancelInteractiveRendering];
  if (keyMonitor_ != nil) {
    [NSEvent removeMonitor:keyMonitor_];
    keyMonitor_ = nil;
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    NSApplication* app = [NSApplication sharedApplication];
    AppDelegate* delegate = [[AppDelegate alloc] initWithArgc:argc argv:argv];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app setDelegate:delegate];
    [app activateIgnoringOtherApps:YES];
    [app run];
  }
  return 0;
}
