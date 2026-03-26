#import "mac/app_delegate.h"

#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <chrono>

#include "core/profiling.h"
#include "core/document.h"
#include "mac/document_workspace_controller.h"
#include "mac/page_indicator_view.h"
#include "mac/recent_documents_controller.h"
#include "mac/render_coordinator.h"
#include "mac/startup_view.h"
#include "mac/tab_strip_view.h"
#include "mac/tab_context.h"
#include "mac/toolbar_view.h"

namespace {

constexpr float kMinimumManualScale = 0.1f;
constexpr float kMaximumManualScale = 5.0f;

double MillisecondsSince(const std::chrono::steady_clock::time_point& start) {
  return std::chrono::duration_cast<std::chrono::duration<double, std::milli> >(
             std::chrono::steady_clock::now() - start)
      .count();
}

}  // namespace

@interface AppDelegate () <NSWindowDelegate, PDFRenderCoordinatorDelegate, NSMenuItemValidation, PDFStartupViewDelegate, PDFTabStripViewDelegate, PDFToolbarViewDelegate, PDFRecentDocumentsControllerDelegate, PDFDocumentWorkspaceControllerDelegate>
- (void)installMainMenu;
- (void)installApplicationIcon;
- (void)installTabStripInView:(NSView*)contentView;
- (void)installToolbarStripInView:(NSView*)contentView;
- (void)layoutChrome;
- (void)updateToolbarForActiveTab;
- (BOOL)applyZoomString:(NSString*)rawValue;
- (void)presentError:(NSString*)message;
- (CGFloat)deviceScaleFactor;
- (void)loadInitialDocuments;
- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive;
- (void)renderTabContext:(PDFTabContext*)context;
- (void)updateScrollerVisibilityForContext:(PDFTabContext*)context;
- (void)updateVisiblePagesForContext:(PDFTabContext*)context;
- (BOOL)isContextActive:(PDFTabContext*)context;
- (CGFloat)effectiveDeviceScaleForContext:(PDFTabContext*)context;
- (BOOL)shouldReduceInteractiveScaleForContext:(PDFTabContext*)context
                                   deviceScale:(CGFloat)deviceScale;
- (void)beginInteractiveRenderingForContext:(PDFTabContext*)context;
- (void)endInteractiveRendering:(NSTimer*)timer;
- (void)cancelInteractiveRendering;
- (void)applyScaleChangeForContext:(PDFTabContext*)context
                        invalidate:(BOOL)invalidateRenderedPages
                        updateMode:(void (^)(PDFTabContext* context))updateMode;
- (float)currentScaleForContext:(PDFTabContext*)context;
- (void)zoomIn;
- (void)zoomOut;
- (void)zoomToActualSize;
- (void)resetZoomToFitWidth;
- (void)fitZoomToPage;
- (void)goToNextPage;
- (void)goToPreviousPage;
- (void)pageDown;
- (void)pageUp;
- (void)scrollToCurrentPageInContext:(PDFTabContext*)context;
- (void)scrollActiveContextByViewportDelta:(CGFloat)deltaY;
- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context;
- (void)showPageIndicatorForContext:(PDFTabContext*)context;
- (void)hidePageIndicator:(NSTimer*)timer;
- (void)ensurePageIndicatorAttachedToContext:(PDFTabContext*)context;
- (void)installKeyMonitor;
- (IBAction)openDocument:(id)sender;
- (IBAction)clearRecentDocuments:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)showHelp:(id)sender;
- (void)installStartupViewInHost:(NSView*)hostView;
@end

@implementation AppDelegate {
  NSWindow* window_;
  PDFTabStripView* tabBarView_;
  NSView* contentHostView_;
  PDFStartupView* startupView_;
  PDFToolbarView* toolbarStrip_;
  PDFPageIndicatorView* pageIndicatorView_;
  PDFRecentDocumentsController* recentDocumentsController_;
  PDFDocumentWorkspaceController* workspaceController_;
  PDFRenderCoordinator* renderCoordinator_;
  NSTimer* interactiveRenderTimer_;
  NSTimer* pageIndicatorTimer_;
  PDFTabContext* interactiveRenderContext_;
  BOOL suppressScrollTracking_;
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
    recentDocumentsController_ = [[PDFRecentDocumentsController alloc] initWithDelegate:self];
    workspaceController_ = nil;
    renderCoordinator_ = [[PDFRenderCoordinator alloc] initWithDelegate:self];
    interactiveRenderTimer_ = nil;
    pageIndicatorTimer_ = nil;
    interactiveRenderContext_ = nil;
    suppressScrollTracking_ = NO;
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  if ([NSWindow respondsToSelector:@selector(setAllowsAutomaticWindowTabbing:)]) {
    [NSWindow setAllowsAutomaticWindowTabbing:NO];
  }

  NSRect frame = NSMakeRect(0, 0, 1080, 800);
  window_ = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSWindowStyleMaskTitled |
                                                  NSWindowStyleMaskClosable |
                                                  NSWindowStyleMaskMiniaturizable |
                                                  NSWindowStyleMaskResizable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

  [window_ center];
  [window_ setTitle:@"PDFView"];
  [window_ setDelegate:self];

  [self installMainMenu];
  [self installApplicationIcon];

  NSView* contentView = [window_ contentView];
  [self installTabStripInView:contentView];
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
  NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"PDFView"];
  NSMenuItem* quitItem =
      [[NSMenuItem alloc] initWithTitle:@"Quit PDFView"
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

  NSMenuItem* openRecentItem =
      [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
  [openRecentItem setSubmenu:[recentDocumentsController_ menu]];
  [fileMenu addItem:openRecentItem];

  NSMenuItem* closeTabItem = [[NSMenuItem alloc] initWithTitle:@"Close Tab"
                                                        action:@selector(closeCurrentTab:)
                                                 keyEquivalent:@"w"];
  [closeTabItem setTarget:self];
  [fileMenu addItem:closeTabItem];
  [fileMenuItem setSubmenu:fileMenu];

  NSMenuItem* viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:viewMenuItem];
  NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
  NSMenuItem* zoomMenuItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:nil keyEquivalent:@""];
  NSMenu* zoomMenu = [[NSMenu alloc] initWithTitle:@"Zoom"];

  NSMenuItem* zoomInItem = [[NSMenuItem alloc] initWithTitle:@"Zoom In"
                                                      action:@selector(zoomIn)
                                               keyEquivalent:@"+"];
  [zoomInItem setTarget:self];
  [zoomMenu addItem:zoomInItem];

  NSMenuItem* zoomOutItem = [[NSMenuItem alloc] initWithTitle:@"Zoom Out"
                                                       action:@selector(zoomOut)
                                                keyEquivalent:@"-"];
  [zoomOutItem setTarget:self];
  [zoomMenu addItem:zoomOutItem];

  [zoomMenu addItem:[NSMenuItem separatorItem]];

  NSMenuItem* actualSizeItem = [[NSMenuItem alloc] initWithTitle:@"Zoom to 100%"
                                                          action:@selector(zoomToActualSize)
                                                   keyEquivalent:@"1"];
  [actualSizeItem setTarget:self];
  [zoomMenu addItem:actualSizeItem];

  NSMenuItem* fitPageItem = [[NSMenuItem alloc] initWithTitle:@"Zoom to Fit Page"
                                                       action:@selector(fitZoomToPage)
                                                keyEquivalent:@""];
  [fitPageItem setTarget:self];
  [zoomMenu addItem:fitPageItem];

  NSMenuItem* fitWidthItem = [[NSMenuItem alloc] initWithTitle:@"Zoom to Fit Width"
                                                        action:@selector(resetZoomToFitWidth)
                                                 keyEquivalent:@""];
  [fitWidthItem setTarget:self];
  [zoomMenu addItem:fitWidthItem];

  [zoomMenuItem setSubmenu:zoomMenu];
  [viewMenu addItem:zoomMenuItem];
  [viewMenuItem setSubmenu:viewMenu];

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
  NSMenuItem* helpItem = [[NSMenuItem alloc] initWithTitle:@"PDFView Help"
                                                    action:@selector(showHelp:)
                                             keyEquivalent:@"?"];
  [helpItem setTarget:self];
  [helpMenu addItem:helpItem];
  [helpMenuItem setSubmenu:helpMenu];
  [NSApp setHelpMenu:helpMenu];

  [NSApp setMainMenu:mainMenu];
}

- (void)installApplicationIcon {
  NSBundle* bundle = [NSBundle mainBundle];
  NSString* iconPath = [bundle pathForResource:@"pdfview" ofType:@"icns"];
  if (iconPath == nil) {
    return;
  }

  NSImage* iconImage = [[NSImage alloc] initWithContentsOfFile:iconPath];
  if (iconImage != nil) {
    [NSApp setApplicationIconImage:iconImage];
  }
}

- (void)installTabStripInView:(NSView*)contentView {
  tabBarView_ = [[PDFTabStripView alloc] initWithFrame:NSMakeRect(0, 0, 100, 34) delegate:self];
  [contentView addSubview:tabBarView_];

  contentHostView_ = [[NSView alloc] initWithFrame:[contentView bounds]];
  [contentHostView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [contentHostView_ setWantsLayer:YES];
  [[contentHostView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
  [contentView addSubview:contentHostView_ positioned:NSWindowBelow relativeTo:tabBarView_];
  workspaceController_ = [[PDFDocumentWorkspaceController alloc] initWithHostView:contentHostView_
                                                                          delegate:self];
  [self installStartupViewInHost:contentHostView_];
}

- (void)installToolbarStripInView:(NSView*)contentView {
  toolbarStrip_ = [[PDFToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 100, 32)
                                               delegate:self];
  [contentView addSubview:toolbarStrip_];
}

- (void)installStartupViewInHost:(NSView*)hostView {
  startupView_ = [[PDFStartupView alloc] initWithFrame:[hostView bounds] delegate:self];
  [startupView_ setRecentDocumentPaths:[recentDocumentsController_ recentDocumentPaths]];
  [hostView addSubview:startupView_];
}

- (void)layoutChrome {
  if (contentHostView_ == nil || toolbarStrip_ == nil || tabBarView_ == nil) {
    return;
  }

  NSView* contentView = [window_ contentView];
  const NSRect contentBounds = [contentView bounds];
  const CGFloat tabBarHeight = [workspaceController_ tabCount] > 0 ? 34.0f : 0.0f;
  const CGFloat toolbarHeight = 32.0f;
  PDFTabContext* context = [workspaceController_ activeContext];
  NSArray<PDFTabContext*>* tabContexts = [workspaceController_ tabContexts];
  NSMutableArray<NSString*>* tabTitles = [[NSMutableArray alloc] initWithCapacity:[tabContexts count]];
  NSInteger selectedIndex = NSNotFound;
  for (NSUInteger index = 0; index < [tabContexts count]; ++index) {
    PDFTabContext* tabContext = [tabContexts objectAtIndex:index];
    [tabTitles addObject:[tabContext tabTitle]];
    if (tabContext == context) {
      selectedIndex = static_cast<NSInteger>(index);
    }
  }
  [tabBarView_ setHidden:[workspaceController_ tabCount] == 0];
  [tabBarView_ setFrame:NSMakeRect(0,
                                   contentBounds.size.height - tabBarHeight,
                                   contentBounds.size.width,
                                   tabBarHeight)];
  [tabBarView_ setTabTitles:tabTitles selectedIndex:selectedIndex];

  if (context == nil) {
    [toolbarStrip_ setHidden:YES];
    [contentHostView_ setFrame:NSMakeRect(0, 0, contentBounds.size.width, contentBounds.size.height)];
    [startupView_ setHidden:NO];
    [startupView_ setFrame:[contentHostView_ bounds]];
    [startupView_ setRecentDocumentPaths:[recentDocumentsController_ recentDocumentPaths]];
    return;
  }

  [toolbarStrip_ setHidden:NO];
  [startupView_ setHidden:YES];
  const NSRect contentRect = NSMakeRect(0,
                                        0,
                                        contentBounds.size.width,
                                        std::max(contentBounds.size.height - tabBarHeight, 0.0));
  [contentHostView_ setFrame:contentRect];
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
  if (toolbarStrip_ == nil) {
    return;
  }

  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    [toolbarStrip_ showEmptyState];
    return;
  }

  const float currentScale = [self currentScaleForContext:context];
  [toolbarStrip_ updateWithCurrentScale:currentScale
                           minimumScale:kMinimumManualScale
                           maximumScale:kMaximumManualScale
                         fitWidthActive:context->viewModel_.view_state().scale_mode ==
                                        pdfview::core::ScaleMode::FitWidth
                          fitPageActive:context->viewModel_.view_state().scale_mode ==
                                         pdfview::core::ScaleMode::FitPage];
}

- (BOOL)applyZoomString:(NSString*)rawValue {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil || toolbarStrip_ == nil) {
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

  [context setManualScale:std::min(std::max(static_cast<float>(zoomPercent / 100.0f),
                                            kMinimumManualScale),
                                   kMaximumManualScale)];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
  return YES;
}

- (void)presentError:(NSString*)message {
  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleCritical];
  [alert setMessageText:@"PDFView"];
  [alert setInformativeText:message];
  [alert runModal];
}

- (void)loadInitialDocuments {
  for (int index = 1; index < argc_; ++index) {
    [self openDocumentAtPath:argv_[index] makeActive:index == argc_ - 1];
  }
}

- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive {
  PDFTabContext* existingContext = [workspaceController_ contextForDocumentPath:path];
  if (existingContext != nil) {
    [workspaceController_ selectContext:existingContext];
    return;
  }

  const pdfview::core::OpenDocumentResult result = pdfview::core::open_document(path);
  if (!result.ok()) {
    [self presentError:[NSString stringWithFormat:@"Failed to open PDF: %s", result.error.c_str()]];
    return;
  }

  PDFTabContext* context =
      [[PDFTabContext alloc] initWithDocument:result.document
                                         path:path
                                        frame:NSMakeRect(0, 0, 100, 100)];
  [recentDocumentsController_ noteOpenedDocumentPath:path];
  [startupView_ setRecentDocumentPaths:[recentDocumentsController_ recentDocumentPaths]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(tabClipViewDidScroll:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:[context->scrollView_ contentView]];
  [workspaceController_ addContext:context makeActive:makeActive];

  if (!makeActive && [workspaceController_ activeContext] != context) {
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

- (void)startupViewDidRequestOpenDocument {
  [self openDocument:nil];
}

- (void)startupViewDidRequestOpenRecentDocumentAtIndex:(NSInteger)index {
  const std::vector<std::string>& recentDocumentPaths = [recentDocumentsController_ recentDocumentPaths];
  if (index < 0 || index >= static_cast<NSInteger>(recentDocumentPaths.size())) {
    return;
  }

  [self openDocumentAtPath:recentDocumentPaths[index] makeActive:YES];
}

- (void)startupViewDidRequestClearRecents {
  [self clearRecentDocuments:nil];
}

- (void)tabStripViewDidSelectTabAtIndex:(NSInteger)index {
  [self cancelInteractiveRendering];
  [workspaceController_ selectContextAtIndex:index];
}

- (void)tabStripViewDidCloseTabAtIndex:(NSInteger)index {
  NSArray<PDFTabContext*>* tabContexts = [workspaceController_ tabContexts];
  if (index < 0 || index >= [tabContexts count]) {
    return;
  }
  [workspaceController_ closeContext:[tabContexts objectAtIndex:index]];
}

- (void)toolbarViewDidRequestZoomOut {
  [self zoomOut];
}

- (void)toolbarViewDidRequestZoomIn {
  [self zoomIn];
}

- (void)toolbarViewDidRequestZoomActual {
  [self zoomToActualSize];
}

- (void)toolbarViewDidRequestFitWidth {
  [self resetZoomToFitWidth];
}

- (void)toolbarViewDidRequestFitPage {
  [self fitZoomToPage];
}

- (void)toolbarViewDidSubmitZoomString:(NSString*)zoomString {
  [self applyZoomString:zoomString];
}

- (void)recentDocumentsControllerDidRequestOpenDocumentAtPath:(NSString*)path {
  if (path == nil || [path length] == 0) {
    return;
  }

  [self openDocumentAtPath:[path UTF8String] makeActive:YES];
}

- (void)workspaceControllerDidAddContext:(PDFTabContext*)context {
  (void)context;
  [tabBarView_ ensureSelectedTabVisibleOnNextLayout];
}

- (void)workspaceControllerWillRemoveContext:(PDFTabContext*)context {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:[context->scrollView_ contentView]];
}

- (void)workspaceControllerSelectionDidChange:(PDFTabContext*)context {
  [self hidePageIndicator:nil];
  if (context == nil) {
    [window_ setTitle:@"PDFView"];
    [self layoutChrome];
    [self updateToolbarForActiveTab];
    return;
  }

  [tabBarView_ ensureSelectedTabVisibleOnNextLayout];
  [window_ setTitle:[NSString stringWithFormat:@"PDFView - %@", [context tabTitle]]];
  [self layoutChrome];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (IBAction)clearRecentDocuments:(id)sender {
  (void)sender;
  [recentDocumentsController_ clearRecentDocuments];
  [startupView_ setRecentDocumentPaths:[recentDocumentsController_ recentDocumentPaths]];
}

- (IBAction)closeCurrentTab:(id)sender {
  (void)sender;
  [workspaceController_ closeContext:[workspaceController_ activeContext]];
}

- (IBAction)showHelp:(id)sender {
  (void)sender;
  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleInformational];
  [alert setMessageText:@"PDFView Help"];
  [alert setInformativeText:@"Use File > Open... to open PDFs, tabs to switch documents, Cmd+W to close the current tab, and Cmd+Q to quit."];
  [alert runModal];
}

- (BOOL)isContextActive:(PDFTabContext*)context {
  return context != nil && context == [workspaceController_ activeContext];
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
  if (context == nil || context != interactiveRenderContext_) {
    return NO;
  }
  return context->viewModel_.should_reduce_interactive_scale(static_cast<float>(deviceScale));
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

- (void)applyScaleChangeForContext:(PDFTabContext*)context
                        invalidate:(BOOL)invalidateRenderedPages
                        updateMode:(void (^)(PDFTabContext* context))updateMode {
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [self updateCurrentPageFromScrollForContext:context];

  const NSRect visibleBounds = [[context->scrollView_ contentView] bounds];
  const pdfview::core::ScaleChangeState scaleChangeState =
      context->viewModel_.capture_scale_change_state();

  updateMode(context);
  if (invalidateRenderedPages) {
    [context invalidateRenderedPages];
  }

  suppressScrollTracking_ = YES;
  [self renderTabContext:context];

  const pdfview::core::ViewRect newPageRect = context->viewModel_.current_page_rect();
  if (newPageRect.height > 0.0f) {
    NSClipView* clipView = [context->scrollView_ contentView];
    const CGFloat targetOriginY =
        context->viewModel_.restored_scroll_y_for_scale_change(scaleChangeState);
    [clipView scrollToPoint:NSMakePoint(visibleBounds.origin.x, targetOriginY)];
    [context->scrollView_ reflectScrolledClipView:clipView];
    context->viewModel_.set_scroll_origin([clipView bounds].origin.x, [clipView bounds].origin.y);
    context->viewModel_.update_current_page_from_scroll();
    [self updateVisiblePagesForContext:context];
  }
  suppressScrollTracking_ = NO;
}

- (void)renderTabContext:(PDFTabContext*)context {
  if (context == nil || !context->viewModel_.document()) {
    return;
  }

  const std::chrono::steady_clock::time_point passStart = std::chrono::steady_clock::now();
  const CGFloat deviceScale = [self effectiveDeviceScaleForContext:context];
  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;
  context->viewModel_.set_scroll_origin([[context->scrollView_ contentView] bounds].origin.x,
                                        [[context->scrollView_ contentView] bounds].origin.y);
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
  [self updateScrollerVisibilityForContext:context];
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

- (void)updateScrollerVisibilityForContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;
  const pdfview::core::PageLayoutResult& layoutResult = context->viewModel_.layout_result();
  const BOOL needsHorizontalScroller = layoutResult.document_width > clipSize.width + 0.5f;
  [context->scrollView_ setHasHorizontalScroller:needsHorizontalScroller];
  [context->scrollView_ setHasVerticalScroller:YES];
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
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    return;
  }

  [self applyScaleChangeForContext:context
                        invalidate:NO
                        updateMode:^(PDFTabContext* scaleContext) {
                          [scaleContext setManualScale:std::min([self currentScaleForContext:scaleContext] * 1.25f,
                                                                kMaximumManualScale)];
                        }];
  [self updateToolbarForActiveTab];
}

- (void)zoomOut {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    return;
  }

  [self applyScaleChangeForContext:context
                        invalidate:NO
                        updateMode:^(PDFTabContext* scaleContext) {
                          [scaleContext setManualScale:std::max([self currentScaleForContext:scaleContext] / 1.25f,
                                                                kMinimumManualScale)];
                        }];
  [self updateToolbarForActiveTab];
}

- (void)zoomToActualSize {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    return;
  }

  [self applyScaleChangeForContext:context
                        invalidate:NO
                        updateMode:^(PDFTabContext* scaleContext) {
                          [scaleContext setManualScale:1.0f];
                        }];
  [self updateToolbarForActiveTab];
}

- (void)resetZoomToFitWidth {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    return;
  }

  [self applyScaleChangeForContext:context
                        invalidate:YES
                        updateMode:^(PDFTabContext* scaleContext) {
                          [scaleContext setScaleMode:pdfview::core::ScaleMode::FitWidth];
                        }];
  [self updateToolbarForActiveTab];
}

- (void)fitZoomToPage {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    return;
  }

  [self applyScaleChangeForContext:context
                        invalidate:YES
                        updateMode:^(PDFTabContext* scaleContext) {
                          [scaleContext setScaleMode:pdfview::core::ScaleMode::FitPage];
                        }];
  [self updateToolbarForActiveTab];
}

- (void)goToNextPage {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil ||
      context->viewModel_.view_state().current_page + 1 >= context->viewModel_.page_count()) {
    return;
  }

  context->viewModel_.mutable_view_state()->current_page += 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)goToPreviousPage {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil || context->viewModel_.view_state().current_page <= 0) {
    return;
  }

  context->viewModel_.mutable_view_state()->current_page -= 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)pageDown {
  [self scrollActiveContextByViewportDelta:1.0f];
}

- (void)pageUp {
  [self scrollActiveContextByViewportDelta:-1.0f];
}

- (void)scrollActiveContextByViewportDelta:(CGFloat)deltaY {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil) {
    return;
  }

  NSClipView* clipView = [context->scrollView_ contentView];
  const NSRect visibleBounds = [clipView bounds];
  const CGFloat targetOriginY = context->viewModel_.scroll_y_after_viewport_step(deltaY);
  if (std::abs(targetOriginY - visibleBounds.origin.y) < 0.5f) {
    return;
  }

  [self cancelInteractiveRendering];
  [clipView scrollToPoint:NSMakePoint(visibleBounds.origin.x, targetOriginY)];
  [context->scrollView_ reflectScrolledClipView:clipView];
  [self updateCurrentPageFromScrollForContext:context];
  [self showPageIndicatorForContext:context];
  [self beginInteractiveRenderingForContext:context];
  [self updateVisiblePagesForContext:context];
}

- (void)scrollToCurrentPageInContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  const pdfview::core::ViewRect pageRect = context->viewModel_.current_page_rect();
  if (pageRect.width <= 0.0f || pageRect.height <= 0.0f) {
    return;
  }

  NSClipView* clipView = [context->scrollView_ contentView];
  suppressScrollTracking_ = YES;
  [clipView scrollToPoint:NSMakePoint([clipView bounds].origin.x,
                                      context->viewModel_.scroll_y_for_current_page())];
  [context->scrollView_ reflectScrolledClipView:clipView];
  context->viewModel_.set_scroll_origin([[context->scrollView_ contentView] bounds].origin.x,
                                        [[context->scrollView_ contentView] bounds].origin.y);
  context->viewModel_.update_current_page_from_scroll();
  [self showPageIndicatorForContext:context];
  [self updateVisiblePagesForContext:context];
  suppressScrollTracking_ = NO;
}

- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context {
  if (context == nil || context->viewModel_.page_frames().empty()) {
    return;
  }

  context->viewModel_.set_scroll_origin([[context->scrollView_ contentView] bounds].origin.x,
                                        [[context->scrollView_ contentView] bounds].origin.y);
  context->viewModel_.update_current_page_from_scroll();
}

- (void)ensurePageIndicatorAttachedToContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  if (pageIndicatorView_ == nil) {
    pageIndicatorView_ = [[PDFPageIndicatorView alloc] initWithFrame:NSMakeRect(0, 0, 88, 30)];
  }

  if ([pageIndicatorView_ superview] != context->containerView_) {
    [pageIndicatorView_ removeFromSuperview];
    [context->containerView_ addSubview:pageIndicatorView_ positioned:NSWindowAbove relativeTo:context->scrollView_];
  }
}

- (void)showPageIndicatorForContext:(PDFTabContext*)context {
  if (context == nil || ![self isContextActive:context] || context->viewModel_.page_count() <= 0) {
    return;
  }

  [self ensurePageIndicatorAttachedToContext:context];

  NSString* text =
      [NSString stringWithUTF8String:context->viewModel_.page_indicator_text().c_str()];
  [pageIndicatorView_ updateWithText:text
                      containerBounds:[context->containerView_ bounds]
                 hasHorizontalScroller:[context->scrollView_ hasHorizontalScroller]];
  [pageIndicatorView_ setHidden:NO];

  if (pageIndicatorTimer_ != nil) {
    [pageIndicatorTimer_ invalidate];
    pageIndicatorTimer_ = nil;
  }
  pageIndicatorTimer_ =
      [NSTimer scheduledTimerWithTimeInterval:1.8
                                       target:self
                                     selector:@selector(hidePageIndicator:)
                                     userInfo:nil
                                      repeats:NO];
  [[NSRunLoop mainRunLoop] addTimer:pageIndicatorTimer_ forMode:NSRunLoopCommonModes];
}

- (void)hidePageIndicator:(NSTimer*)timer {
  if (timer != nil && timer != pageIndicatorTimer_) {
    return;
  }
  if (pageIndicatorTimer_ != nil) {
    [pageIndicatorTimer_ invalidate];
    pageIndicatorTimer_ = nil;
  }
  [pageIndicatorView_ setHidden:YES];
}

- (void)tabClipViewDidScroll:(NSNotification*)notification {
  if (suppressScrollTracking_) {
    return;
  }
  PDFTabContext* context = [workspaceController_ contextForClipView:(NSClipView*)[notification object]];
  [self updateCurrentPageFromScrollForContext:context];
  [self showPageIndicatorForContext:context];
  [self beginInteractiveRenderingForContext:context];
  [self updateVisiblePagesForContext:context];
}

- (void)installKeyMonitor {
  keyMonitor_ = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                      handler:^NSEvent*(NSEvent* event) {
    if ([toolbarStrip_ isEditingZoomField]) {
      return event;
    }

    id firstResponder = [window_ firstResponder];
    if ([toolbarStrip_ ownsFirstResponder:firstResponder]) {
      return event;
    }

    PDFTabContext* context = [workspaceController_ activeContext];
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
    if (key == NSPageDownFunctionKey) {
      [self pageDown];
      return nil;
    }
    if (key == NSPageUpFunctionKey) {
      [self pageUp];
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

- (void)windowDidResize:(NSNotification*)notification {
  (void)notification;
  [self layoutChrome];
  NSArray<PDFTabContext*>* tabContexts = [workspaceController_ tabContexts];
  for (PDFTabContext* context in tabContexts) {
    if (context != [workspaceController_ activeContext]) {
      NSView* contentView = [window_ contentView];
      const NSRect contentBounds = [contentView bounds];
      const CGFloat tabBarHeight = [workspaceController_ tabCount] > 0 ? 34.0f : 0.0f;
      const CGFloat toolbarHeight = 32.0f;
      const NSRect contentRect = NSMakeRect(0,
                                            0,
                                            contentBounds.size.width,
                                            std::max(contentBounds.size.height - tabBarHeight, 0.0));
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
  [self hidePageIndicator:nil];
  if (keyMonitor_ != nil) {
    [NSEvent removeMonitor:keyMonitor_];
    keyMonitor_ = nil;
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
  SEL action = [menuItem action];
  const BOOL hasActiveDocument = [workspaceController_ activeContext] != nil;

  if (action == @selector(zoomIn) ||
      action == @selector(zoomOut) ||
      action == @selector(zoomToActualSize) ||
      action == @selector(resetZoomToFitWidth) ||
      action == @selector(fitZoomToPage) ||
      action == @selector(goToNextPage) ||
      action == @selector(goToPreviousPage) ||
      action == @selector(closeCurrentTab:)) {
    return hasActiveDocument;
  }

  if (action == @selector(clearRecentDocuments:)) {
    return ![recentDocumentsController_ recentDocumentPaths].empty();
  }

  return YES;
}

@end
