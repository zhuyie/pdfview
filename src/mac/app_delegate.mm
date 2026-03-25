#import "mac/app_delegate.h"

#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <chrono>

#include "core/profiling.h"
#include "core/document.h"
#include "mac/render_coordinator.h"
#include "mac/tab_context.h"

namespace {

NSRect NSRectFromViewRect(const pdfview::core::ViewRect& rect) {
  return NSMakeRect(rect.x, rect.y, rect.width, rect.height);
}

double MillisecondsSince(const std::chrono::steady_clock::time_point& start) {
  return std::chrono::duration_cast<std::chrono::duration<double, std::milli> >(
             std::chrono::steady_clock::now() - start)
      .count();
}

}  // namespace

@interface AppDelegate () <NSWindowDelegate, NSTabViewDelegate, NSComboBoxDelegate, NSTextFieldDelegate, PDFRenderCoordinatorDelegate>
- (void)installMainMenu;
- (void)installToolbarStripInView:(NSView*)contentView;
- (void)layoutChrome;
- (void)updateToolbarForActiveTab;
- (BOOL)applyZoomString:(NSString*)rawValue;
- (IBAction)zoomComboBoxChanged:(id)sender;
- (void)presentError:(NSString*)message;
- (CGFloat)deviceScaleFactor;
- (void)loadInitialDocuments;
- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive;
- (void)renderTabContext:(PDFTabContext*)context;
- (void)updateVisiblePagesForContext:(PDFTabContext*)context;
- (BOOL)isContextActive:(PDFTabContext*)context;
- (CGFloat)effectiveDeviceScaleForContext:(PDFTabContext*)context;
- (BOOL)shouldReduceInteractiveScaleForContext:(PDFTabContext*)context
                                   deviceScale:(CGFloat)deviceScale;
- (void)beginInteractiveRenderingForContext:(PDFTabContext*)context;
- (void)endInteractiveRendering:(NSTimer*)timer;
- (void)cancelInteractiveRendering;
- (float)currentScaleForContext:(PDFTabContext*)context;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoomToFitWidth;
- (void)fitZoomToPage;
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
  NSButton* fitWidthButton_;
  NSButton* fitPageButton_;
  BOOL zoomComboBoxEditing_;
  NSMutableArray* tabContexts_;
  PDFRenderCoordinator* renderCoordinator_;
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
    renderCoordinator_ = [[PDFRenderCoordinator alloc] initWithDelegate:self];
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
  [window_ orderFrontRegardless];
  [NSApp activateIgnoringOtherApps:YES];
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

  fitWidthButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(176, 4, 62, 22)];
  [fitWidthButton_ setTitle:@"Width"];
  [fitWidthButton_ setBezelStyle:NSBezelStyleTexturedRounded];
  [fitWidthButton_ setTarget:self];
  [fitWidthButton_ setAction:@selector(resetZoomToFitWidth)];
  [toolbarStrip_ addSubview:fitWidthButton_];

  fitPageButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(244, 4, 56, 22)];
  [fitPageButton_ setTitle:@"Page"];
  [fitPageButton_ setBezelStyle:NSBezelStyleTexturedRounded];
  [fitPageButton_ setTarget:self];
  [fitPageButton_ setAction:@selector(fitZoomToPage)];
  [toolbarStrip_ addSubview:fitPageButton_];
}

- (void)layoutChrome {
  if (tabView_ == nil || toolbarStrip_ == nil) {
    return;
  }

  const CGFloat toolbarHeight = 32.0f;
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    [toolbarStrip_ setHidden:YES];
    return;
  }

  [toolbarStrip_ setHidden:NO];
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
    [fitWidthButton_ setEnabled:NO];
    [fitPageButton_ setEnabled:NO];
    return;
  }

  if (zoomComboBoxEditing_) {
    return;
  }

  [zoomComboBox_ setEnabled:YES];
  [fitWidthButton_ setEnabled:YES];
  [fitPageButton_ setEnabled:YES];
  [fitWidthButton_ setState:context->viewModel_.view_state().scale_mode == pdfview::core::ScaleMode::FitWidth
                                ? NSControlStateValueOn
                                : NSControlStateValueOff];
  [fitPageButton_ setState:context->viewModel_.view_state().scale_mode == pdfview::core::ScaleMode::FitPage
                               ? NSControlStateValueOn
                               : NSControlStateValueOff];
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

  [context setManualScale:std::max(static_cast<float>(zoomPercent / 100.0), 0.1f)];
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
  if ([self shouldReduceInteractiveScaleForContext:context deviceScale:deviceScale]) {
    deviceScale = std::max(1.0, deviceScale * 0.5);
  }
  return deviceScale;
}

- (BOOL)shouldReduceInteractiveScaleForContext:(PDFTabContext*)context
                                   deviceScale:(CGFloat)deviceScale {
  if (context == nil || context != interactiveRenderContext_ || deviceScale <= 1.0) {
    return NO;
  }

  const std::vector<pdfview::core::ViewRect>& pageFrames = context->viewModel_.page_frames();
  if (pageFrames.empty()) {
    return NO;
  }

  const pdfview::core::ViewRect visibleRect = context->viewModel_.visible_rect();
  const pdfview::core::PageCachePlan cachePlan =
      context->viewModel_.page_cache_plan(visibleRect.height * 0.5f);
  if (cachePlan.preload_range.empty()) {
    return NO;
  }

  double totalVisiblePixels = 0.0;
  double maxPagePixels = 0.0;
  for (int pageIndex = cachePlan.preload_range.start;
       pageIndex < cachePlan.preload_range.end;
       ++pageIndex) {
    if (pageIndex < 0 || pageIndex >= static_cast<int>(pageFrames.size())) {
      continue;
    }

    const pdfview::core::ViewRect& frame = pageFrames[pageIndex];
    const double pagePixels =
        static_cast<double>(frame.width) * static_cast<double>(frame.height) *
        static_cast<double>(deviceScale) * static_cast<double>(deviceScale);
    totalVisiblePixels += pagePixels;
    maxPagePixels = std::max(maxPagePixels, pagePixels);
  }

  return maxPagePixels >= 2500000.0 || totalVisiblePixels >= 5000000.0;
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
  if (context == nil || !context->viewModel_.document()) {
    return;
  }

  const std::chrono::steady_clock::time_point passStart = std::chrono::steady_clock::now();
  const CGFloat deviceScale = [self effectiveDeviceScaleForContext:context];
  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;
  [context setScrollOrigin:[[context->scrollView_ contentView] bounds].origin];
  context->viewModel_.set_viewport_size(clipSize.width, clipSize.height);
  context->viewModel_.set_device_scale(static_cast<float>(deviceScale));

  context->viewModel_.relayout();
  const pdfview::core::PageLayoutResult& layoutResult = context->viewModel_.layout_result();
  const double layoutMilliseconds = MillisecondsSince(passStart);
  [context syncPageFrames];

  [context->documentView_
      setFrame:NSMakeRect(0,
                          0,
                          layoutResult.document_width,
                          layoutResult.document_height)];
  if ([self isContextActive:context]) {
    [self updateVisiblePagesForContext:context];
  }

  if (pdfview::core::render_profiling_enabled()) {
    const pdfview::core::ViewRect visibleRect = context->viewModel_.visible_rect();
    const int currentPage = context->viewModel_.view_state().current_page;
    const double totalMilliseconds = MillisecondsSince(passStart);
    pdfview::core::record_render_tab_sample(totalMilliseconds, layoutMilliseconds);
    pdfview::core::render_log("[pdfview] render_tab total_ms=%.2f layout_ms=%.2f viewport=%.0fx%.0f "
                              "doc=%.0fx%.0f logical_scale=%.3f render_scale=%.3f current_page=%d scroll_y=%.0f",
                              totalMilliseconds,
                              layoutMilliseconds,
                              clipSize.width,
                              clipSize.height,
                              layoutResult.document_width,
                              layoutResult.document_height,
                              context->viewModel_.current_logical_scale(),
                              context->viewModel_.current_render_scale(),
                              currentPage,
                              visibleRect.y);
  }
}

- (void)updateVisiblePagesForContext:(PDFTabContext*)context {
  const CGFloat deviceScale = [self effectiveDeviceScaleForContext:context];
  [renderCoordinator_ updateVisiblePagesForContext:context
                                          isActive:[self isContextActive:context]
                                       deviceScale:deviceScale];
}

- (float)currentScaleForContext:(PDFTabContext*)context {
  return [context currentScale];
}

- (void)zoomIn {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [context setManualScale:std::min([self currentScaleForContext:context] * 1.25f, 5.0f)];
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
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)resetZoomToFitWidth {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [context setScaleMode:pdfview::core::ScaleMode::FitWidth];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)fitZoomToPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [context setScaleMode:pdfview::core::ScaleMode::FitPage];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)goToNextPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil ||
      context->viewModel_.view_state().current_page + 1 >= context->viewModel_.page_count()) {
    return;
  }

  context->viewModel_.mutable_view_state()->current_page += 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)goToPreviousPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil || context->viewModel_.view_state().current_page <= 0) {
    return;
  }

  context->viewModel_.mutable_view_state()->current_page -= 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)scrollToCurrentPageInContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  const pdfview::core::ViewRect pageRect = [context currentPageRect];
  if (pageRect.width <= 0.0f || pageRect.height <= 0.0f) {
    return;
  }

  const NSRect pageFrame = NSRectFromViewRect(pageRect);
  [[context->scrollView_ documentView] scrollRectToVisible:pageFrame];
  [context setScrollOrigin:[[context->scrollView_ contentView] bounds].origin];
  [self updateVisiblePagesForContext:context];
}

- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context {
  if (context == nil || context->viewModel_.page_frames().empty()) {
    return;
  }

  [context setScrollOrigin:[[context->scrollView_ contentView] bounds].origin];
  [context updateCurrentPageFromScroll];
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
    if (context->viewModel_.view_state().scale_mode != pdfview::core::ScaleMode::Manual) {
      [self scrollToCurrentPageInContext:context];
    }
  }
  [self updateToolbarForActiveTab];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  (void)notification;
  pdfview::core::flush_render_profile_summary();
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
