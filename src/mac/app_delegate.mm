#import "mac/app_delegate.h"

#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <chrono>

#include "core/profiling.h"
#include "core/document.h"
#include "core/text_selection.h"
#include "mac/chrome_metrics.h"
#include "mac/document_drop_view.h"
#include "mac/document_interaction_controller.h"
#include "mac/document_workspace_controller.h"
#include "mac/recent_documents_controller.h"
#include "mac/render_coordinator.h"
#include "mac/startup_view.h"
#include "mac/tab_strip_view.h"
#include "mac/tab_context.h"
#include "mac/toolbar_view.h"

namespace {

constexpr float kMinimumManualScale = 0.1f;
constexpr float kMaximumManualScale = 5.0f;
constexpr CGFloat kSelectionAutoScrollEdgeInset = 36.0;
constexpr CGFloat kSelectionAutoScrollMaxStep = 28.0;
constexpr NSTimeInterval kSelectionAutoScrollTickInterval = 1.0 / 60.0;

double MillisecondsSince(const std::chrono::steady_clock::time_point& start) {
  return std::chrono::duration_cast<std::chrono::duration<double, std::milli> >(
             std::chrono::steady_clock::now() - start)
      .count();
}

}  // namespace

@interface AppDelegate () <NSWindowDelegate, PDFRenderCoordinatorDelegate, NSMenuItemValidation, PDFStartupViewDelegate, PDFTabStripViewDelegate, PDFToolbarViewDelegate, PDFRecentDocumentsControllerDelegate, PDFDocumentWorkspaceControllerDelegate, PDFDocumentDropViewDelegate, PDFDocumentInteractionControllerDelegate, PDFPageViewHostDelegate>
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
- (void)openDocumentPaths:(NSArray<NSString*>*)paths;
- (void)renderTabContext:(PDFTabContext*)context;
- (void)updateScrollerVisibilityForContext:(PDFTabContext*)context;
- (void)updateVisiblePagesForContext:(PDFTabContext*)context;
- (BOOL)isContextActive:(PDFTabContext*)context;
- (CGFloat)effectiveDeviceScaleForContext:(PDFTabContext*)context;
- (BOOL)shouldReduceInteractiveScaleForContext:(PDFTabContext*)context
                                   deviceScale:(CGFloat)deviceScale;
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
- (void)installKeyMonitor;
- (IBAction)openDocument:(id)sender;
- (IBAction)copy:(id)sender;
- (IBAction)clearRecentDocuments:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)showHelp:(id)sender;
- (NSMenu*)selectionContextMenu;
- (void)showSelectionContextMenuWithEvent:(NSEvent*)event;
- (void)installStartupViewInHost:(NSView*)hostView;
- (int)textIndexForPageSelectionAtPageIndex:(int)pageIndex
                                   location:(NSPoint)location
                                    context:(PDFTabContext*)context;
- (void)updateTextSelectionAtPageIndex:(int)pageIndex
                              location:(NSPoint)location
                               context:(PDFTabContext*)context;
- (BOOL)resolveDocumentSelectionPoint:(NSPoint)documentLocation
                              context:(PDFTabContext*)context
                            pageIndex:(int*)pageIndex
                         pageLocation:(NSPoint*)pageLocation;
- (BOOL)resolveDocumentSelectionFallback:(NSPoint)documentLocation
                                 context:(PDFTabContext*)context
                               pageIndex:(int*)pageIndex
                               charIndex:(int*)charIndex;
- (void)updateTextSelectionAtDocumentLocation:(NSPoint)documentLocation
                                      context:(PDFTabContext*)context;
- (void)startSelectionAutoScrollForContext:(PDFTabContext*)context;
- (void)stopSelectionAutoScroll;
- (void)updateSelectionAutoScrollForDocumentLocation:(NSPoint)documentLocation
                                             context:(PDFTabContext*)context;
- (void)handleSelectionAutoScrollTick:(NSTimer*)timer;
- (void)selectWordAtPageIndex:(int)pageIndex
                     location:(NSPoint)location
                      context:(PDFTabContext*)context;
- (void)applyTextSelectionForFocusPageIndex:(int)focusPageIndex
                                   charIndex:(int)focusCharIndex
                                     context:(PDFTabContext*)context;
@end

@implementation AppDelegate {
  NSWindow* window_;
  PDFTabStripView* tabBarView_;
  NSView* contentHostView_;
  PDFStartupView* startupView_;
  PDFToolbarView* toolbarStrip_;
  PDFRecentDocumentsController* recentDocumentsController_;
  PDFDocumentWorkspaceController* workspaceController_;
  PDFDocumentInteractionController* interactionController_;
  PDFRenderCoordinator* renderCoordinator_;
  BOOL suppressScrollTracking_;
  NSTimer* selectionAutoScrollTimer_;
  PDFTabContext* selectionAutoScrollContext_;
  NSPoint selectionAutoScrollDocumentLocation_;
  id keyMonitor_;
  id mouseMonitor_;
  int argc_;
  const char** argv_;
}

- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv {
  self = [super init];
  if (self != nil) {
    argc_ = argc;
    argv_ = argv;
    keyMonitor_ = nil;
    mouseMonitor_ = nil;
    recentDocumentsController_ = [[PDFRecentDocumentsController alloc] initWithDelegate:self];
    workspaceController_ = nil;
    interactionController_ = [[PDFDocumentInteractionController alloc] initWithDelegate:self];
    renderCoordinator_ = [[PDFRenderCoordinator alloc] initWithDelegate:self];
    suppressScrollTracking_ = NO;
    selectionAutoScrollTimer_ = nil;
    selectionAutoScrollContext_ = nil;
    selectionAutoScrollDocumentLocation_ = NSZeroPoint;
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  if ([NSWindow respondsToSelector:@selector(setAllowsAutomaticWindowTabbing:)]) {
    [NSWindow setAllowsAutomaticWindowTabbing:NO];
  }

  NSRect frame = PDFViewInitialWindowFrame();
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

  NSMenuItem* editMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:editMenuItem];
  NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  NSMenuItem* copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                    action:@selector(copy:)
                                             keyEquivalent:@"c"];
  [copyItem setTarget:self];
  [editMenu addItem:copyItem];
  [editMenuItem setSubmenu:editMenu];

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
  tabBarView_ =
      [[PDFTabStripView alloc] initWithFrame:NSMakeRect(0, 0, 100, PDFTabBarHeight(1))
                                   delegate:self];
  [contentView addSubview:tabBarView_];

  contentHostView_ = [[PDFDocumentDropView alloc] initWithFrame:[contentView bounds] delegate:self];
  [contentHostView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [contentView addSubview:contentHostView_ positioned:NSWindowBelow relativeTo:tabBarView_];
  workspaceController_ = [[PDFDocumentWorkspaceController alloc] initWithHostView:contentHostView_
                                                                          delegate:self];
  [self installStartupViewInHost:contentHostView_];
}

- (void)installToolbarStripInView:(NSView*)contentView {
  toolbarStrip_ = [[PDFToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 100, PDFToolbarHeight())
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
  const PDFChromeLayoutFrames layoutFrames =
      PDFComputeChromeLayoutFrames(contentBounds, [workspaceController_ tabCount]);
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
  [tabBarView_ setFrame:layoutFrames.tab_bar_frame];
  [tabBarView_ setTabTitles:tabTitles selectedIndex:selectedIndex];

  if (context == nil) {
    [toolbarStrip_ setHidden:YES];
    [contentHostView_ setFrame:layoutFrames.content_frame];
    [startupView_ setHidden:NO];
    [startupView_ setFrame:[contentHostView_ bounds]];
    [startupView_ setRecentDocumentPaths:[recentDocumentsController_ recentDocumentPaths]];
    return;
  }

  [toolbarStrip_ setHidden:NO];
  [startupView_ setHidden:YES];
  [contentHostView_ setFrame:layoutFrames.content_frame];
  [context->containerView_ setFrame:layoutFrames.content_frame];
  [toolbarStrip_ removeFromSuperview];
  [context->containerView_ addSubview:toolbarStrip_];
  [toolbarStrip_ setFrame:layoutFrames.toolbar_frame];
  [context->scrollView_ setFrame:layoutFrames.document_frame];
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

- (void)openDocumentPaths:(NSArray<NSString*>*)paths {
  if (paths == nil || [paths count] == 0) {
    return;
  }

  for (NSUInteger index = 0; index < [paths count]; ++index) {
    NSString* path = [paths objectAtIndex:index];
    if (path == nil || [path length] == 0) {
      continue;
    }
    [self openDocumentAtPath:[path UTF8String] makeActive:index + 1 == [paths count]];
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
                                        frame:NSMakeRect(0, 0, 100, 100)
                                     delegate:self];
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

- (IBAction)copy:(id)sender {
  (void)sender;
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil || ![context hasSelectedText]) {
    return;
  }

  NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard clearContents];
  [pasteboard setString:[context selectedText] forType:NSPasteboardTypeString];
}

- (NSMenu*)selectionContextMenu {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Selection"];
  NSMenuItem* copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                    action:@selector(copy:)
                                             keyEquivalent:@""];
  [copyItem setTarget:self];
  [menu addItem:copyItem];
  return menu;
}

- (void)showSelectionContextMenuWithEvent:(NSEvent*)event {
  if (event == nil) {
    return;
  }

  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil || ![context hasSelectedText]) {
    return;
  }

  [NSMenu popUpContextMenu:[self selectionContextMenu]
                 withEvent:event
                   forView:context->documentView_];
}

- (void)startupViewDidRequestOpenDocument {
  [self openDocument:nil];
}

- (void)startupViewDidRequestOpenDocumentAtPaths:(NSArray<NSString*>*)paths {
  [self openDocumentPaths:paths];
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
  [interactionController_ cancelInteractiveRendering];
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

- (void)documentDropViewDidReceiveDocumentPaths:(NSArray<NSString*>*)paths {
  [self openDocumentPaths:paths];
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
  [interactionController_ hidePageIndicator];
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
  return [interactionController_ shouldReduceInteractiveScaleForContext:context
                                                            deviceScale:deviceScale];
}

- (void)applyScaleChangeForContext:(PDFTabContext*)context
                        invalidate:(BOOL)invalidateRenderedPages
                        updateMode:(void (^)(PDFTabContext* context))updateMode {
  if (context == nil) {
    return;
  }

  [interactionController_ cancelInteractiveRendering];
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

  [interactionController_ cancelInteractiveRendering];
  [clipView scrollToPoint:NSMakePoint(visibleBounds.origin.x, targetOriginY)];
  [context->scrollView_ reflectScrolledClipView:clipView];
  [self updateCurrentPageFromScrollForContext:context];
  [interactionController_ showPageIndicatorForContext:context];
  [interactionController_ beginInteractiveRenderingForContext:context];
  [self updateVisiblePagesForContext:context];
}

- (void)scrollToCurrentPageInContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  [interactionController_ cancelInteractiveRendering];
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
  [interactionController_ showPageIndicatorForContext:context];
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

- (int)textIndexForPageSelectionAtPageIndex:(int)pageIndex
                                   location:(NSPoint)location
                                    context:(PDFTabContext*)context {
  if (context == nil ||
      pageIndex < 0 ||
      pageIndex >= static_cast<int>(context->viewModel_.page_frames().size()) ||
      pageIndex >= static_cast<int>(context->viewModel_.page_sizes().size())) {
    return -1;
  }

  float pageX = 0.0f;
  float pageY = 0.0f;
  if (!pdfview::core::page_point_from_page_view_point(
          location.x,
          location.y,
          context->viewModel_.page_sizes()[pageIndex],
          context->viewModel_.page_frames()[pageIndex],
          &pageX,
          &pageY)) {
    return -1;
  }

  const float logicalScale = std::max(context->viewModel_.current_logical_scale(), 0.1f);
  const float tolerance = 6.0f / logicalScale;
  return context->viewModel_.document()->text_index_at_point(
      pageIndex, pageX, pageY, tolerance, tolerance);
}

- (void)updateTextSelectionAtPageIndex:(int)pageIndex
                              location:(NSPoint)location
                               context:(PDFTabContext*)context {
  if (context == nil || ![self isContextActive:context]) {
    return;
  }

  const int charIndex = [self textIndexForPageSelectionAtPageIndex:pageIndex
                                                          location:location
                                                           context:context];
  if (charIndex < 0) {
    return;
  }

  if (!context->textSelection_.anchor.valid()) {
    [context setTextSelectionAnchorPageIndex:pageIndex charIndex:charIndex];
    return;
  }

  [self applyTextSelectionForFocusPageIndex:pageIndex charIndex:charIndex context:context];
}

- (BOOL)resolveDocumentSelectionPoint:(NSPoint)documentLocation
                              context:(PDFTabContext*)context
                            pageIndex:(int*)pageIndex
                         pageLocation:(NSPoint*)pageLocation {
  if (context == nil || pageIndex == NULL || pageLocation == NULL) {
    return NO;
  }

  float pageX = 0.0f;
  float pageY = 0.0f;
  const bool resolved = pdfview::core::resolve_document_selection_point(
      documentLocation.x,
      documentLocation.y,
      context->viewModel_.page_frames(),
      pageIndex,
      &pageX,
      &pageY);
  if (!resolved) {
    return NO;
  }

  pageLocation->x = pageX;
  pageLocation->y = pageY;
  return YES;
}

- (void)updateTextSelectionAtDocumentLocation:(NSPoint)documentLocation
                                      context:(PDFTabContext*)context {
  [self updateSelectionAutoScrollForDocumentLocation:documentLocation context:context];

  int pageIndex = -1;
  NSPoint pageLocation = NSZeroPoint;
  if (![self resolveDocumentSelectionPoint:documentLocation
                                   context:context
                                 pageIndex:&pageIndex
                              pageLocation:&pageLocation]) {
    int fallbackPageIndex = -1;
    int fallbackCharIndex = -1;
    if ([self resolveDocumentSelectionFallback:documentLocation
                                       context:context
                                     pageIndex:&fallbackPageIndex
                                     charIndex:&fallbackCharIndex]) {
      if (!context->textSelection_.anchor.valid()) {
        [context setTextSelectionAnchorPageIndex:fallbackPageIndex charIndex:fallbackCharIndex];
        return;
      }
      [self applyTextSelectionForFocusPageIndex:fallbackPageIndex
                                      charIndex:fallbackCharIndex
                                        context:context];
    }
    return;
  }

  [self updateTextSelectionAtPageIndex:pageIndex location:pageLocation context:context];
}

- (void)startSelectionAutoScrollForContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  selectionAutoScrollContext_ = context;
  if (selectionAutoScrollTimer_ != nil) {
    return;
  }

  selectionAutoScrollTimer_ =
      [NSTimer scheduledTimerWithTimeInterval:kSelectionAutoScrollTickInterval
                                       target:self
                                     selector:@selector(handleSelectionAutoScrollTick:)
                                     userInfo:nil
                                      repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:selectionAutoScrollTimer_ forMode:NSRunLoopCommonModes];
}

- (void)stopSelectionAutoScroll {
  if (selectionAutoScrollTimer_ != nil) {
    [selectionAutoScrollTimer_ invalidate];
    selectionAutoScrollTimer_ = nil;
  }
  selectionAutoScrollContext_ = nil;
}

- (void)updateSelectionAutoScrollForDocumentLocation:(NSPoint)documentLocation
                                             context:(PDFTabContext*)context {
  selectionAutoScrollDocumentLocation_ = documentLocation;
  if (context == nil || !context->textSelection_.dragging) {
    [self stopSelectionAutoScroll];
    return;
  }

  NSClipView* clipView = [context->scrollView_ contentView];
  const NSRect visibleBounds = [clipView bounds];
  const CGFloat distanceToTop = documentLocation.y - visibleBounds.origin.y;
  const CGFloat distanceToBottom =
      NSMaxY(visibleBounds) - documentLocation.y;
  const BOOL nearTop = distanceToTop < kSelectionAutoScrollEdgeInset;
  const BOOL nearBottom = distanceToBottom < kSelectionAutoScrollEdgeInset;

  if (!nearTop && !nearBottom) {
    [self stopSelectionAutoScroll];
    return;
  }

  [self startSelectionAutoScrollForContext:context];
}

- (void)handleSelectionAutoScrollTick:(NSTimer*)timer {
  if (timer != selectionAutoScrollTimer_ || selectionAutoScrollContext_ == nil) {
    return;
  }

  PDFTabContext* context = selectionAutoScrollContext_;
  NSClipView* clipView = [context->scrollView_ contentView];
  const NSRect visibleBounds = [clipView bounds];
  const CGFloat distanceToTop =
      selectionAutoScrollDocumentLocation_.y - visibleBounds.origin.y;
  const CGFloat distanceToBottom =
      NSMaxY(visibleBounds) - selectionAutoScrollDocumentLocation_.y;

  CGFloat scrollDelta = 0.0;
  if (distanceToTop < kSelectionAutoScrollEdgeInset) {
    const CGFloat intensity =
        std::max((kSelectionAutoScrollEdgeInset - distanceToTop) / kSelectionAutoScrollEdgeInset,
                 0.0);
    scrollDelta = -std::max(intensity * kSelectionAutoScrollMaxStep, 1.0);
  } else if (distanceToBottom < kSelectionAutoScrollEdgeInset) {
    const CGFloat intensity =
        std::max((kSelectionAutoScrollEdgeInset - distanceToBottom) /
                     kSelectionAutoScrollEdgeInset,
                 0.0);
    scrollDelta = std::max(intensity * kSelectionAutoScrollMaxStep, 1.0);
  } else {
    [self stopSelectionAutoScroll];
    return;
  }

  const CGFloat maxScrollY =
      std::max(static_cast<CGFloat>(context->viewModel_.layout_result().document_height) -
                   visibleBounds.size.height,
               static_cast<CGFloat>(0.0));
  const CGFloat targetOriginY =
      std::min(std::max(visibleBounds.origin.y + scrollDelta, 0.0), maxScrollY);
  if (std::abs(targetOriginY - visibleBounds.origin.y) < 0.5f) {
    return;
  }

  suppressScrollTracking_ = YES;
  [clipView scrollToPoint:NSMakePoint(visibleBounds.origin.x, targetOriginY)];
  [context->scrollView_ reflectScrolledClipView:clipView];
  suppressScrollTracking_ = NO;
  [self updateCurrentPageFromScrollForContext:context];
  [self updateVisiblePagesForContext:context];

  const NSPoint windowLocation = [window_ mouseLocationOutsideOfEventStream];
  const NSPoint documentLocation =
      [context->documentView_ convertPoint:windowLocation fromView:nil];
  selectionAutoScrollDocumentLocation_ = documentLocation;
  [self updateTextSelectionAtDocumentLocation:documentLocation context:context];
}

- (BOOL)resolveDocumentSelectionFallback:(NSPoint)documentLocation
                                 context:(PDFTabContext*)context
                               pageIndex:(int*)pageIndex
                               charIndex:(int*)charIndex {
  if (context == nil || pageIndex == NULL || charIndex == NULL) {
    return NO;
  }

  return pdfview::core::resolve_document_selection_fallback(
      documentLocation.y,
      context->textSelection_.anchor.page_index,
      context->viewModel_.page_frames(),
      *context->viewModel_.document(),
      pageIndex,
      charIndex);
}

- (void)applyTextSelectionForFocusPageIndex:(int)focusPageIndex
                                   charIndex:(int)focusCharIndex
                                     context:(PDFTabContext*)context {
  if (context == nil || focusPageIndex < 0 || focusCharIndex < 0) {
    return;
  }

  pdfview::core::TextSelectionEndpoint anchor = context->textSelection_.anchor;
  pdfview::core::TextSelectionEndpoint focus;
  focus.page_index = focusPageIndex;
  focus.char_index = focusCharIndex;

  const pdfview::core::TextSelectionRange range =
      pdfview::core::make_text_selection_range(anchor, focus);
  if (range.empty()) {
    [context updateTextSelectionWithFocusPageIndex:focusPageIndex
                                         charIndex:focusCharIndex
                                             text:std::string()
                                             spans:std::vector<pdfview::core::PageTextSelectionSpan>()];
    return;
  }

  const pdfview::core::DocumentTextSelection selection =
      pdfview::core::build_document_text_selection(*context->viewModel_.document(), range);

  [context updateTextSelectionWithFocusPageIndex:focusPageIndex
                                       charIndex:focusCharIndex
                                            text:selection.text
                                           spans:selection.spans];
}

- (void)selectWordAtPageIndex:(int)pageIndex
                     location:(NSPoint)location
                      context:(PDFTabContext*)context {
  if (context == nil || ![self isContextActive:context]) {
    return;
  }

  const int charIndex = [self textIndexForPageSelectionAtPageIndex:pageIndex
                                                          location:location
                                                           context:context];
  if (charIndex < 0) {
    [context clearTextSelection];
    return;
  }

  const pdfview::core::PageTextSelection selection =
      context->viewModel_.document()->word_selection_at_index(pageIndex, charIndex);
  if (!selection.ok()) {
    [context clearTextSelection];
    return;
  }

  [context beginTextSelectionOnPageIndex:pageIndex charIndex:selection.start_index];
  std::vector<pdfview::core::PageTextSelectionSpan> spans(1);
  spans[0].page_index = pageIndex;
  spans[0].rects = selection.rects;
  [context updateTextSelectionWithFocusPageIndex:pageIndex
                                       charIndex:selection.start_index + selection.count - 1
                                            text:selection.text
                                           spans:spans];
  [context endTextSelection];
}

- (void)tabClipViewDidScroll:(NSNotification*)notification {
  PDFTabContext* context = [workspaceController_ contextForClipView:(NSClipView*)[notification object]];
  [interactionController_ handleClipViewDidScrollForContext:context
                                      suppressScrollTracking:suppressScrollTracking_];
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

  mouseMonitor_ =
      [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown |
                                                     NSEventMaskRightMouseDown |
                                                     NSEventMaskOtherMouseDown
                                            handler:^NSEvent*(NSEvent* event) {
    if (toolbarStrip_ == nil || ![toolbarStrip_ ownsFirstResponder:[window_ firstResponder]]) {
      return event;
    }

    NSWindow* eventWindow = [event window];
    if (eventWindow != window_) {
      [toolbarStrip_ cancelZoomEditing];
      return event;
    }

    const NSPoint locationInWindow = [event locationInWindow];
    const NSPoint locationInToolbar = [toolbarStrip_ convertPoint:locationInWindow fromView:nil];
    if (![toolbarStrip_ mouse:locationInToolbar inRect:[toolbarStrip_ bounds]]) {
      [toolbarStrip_ cancelZoomEditing];
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
  NSView* contentView = [window_ contentView];
  const PDFChromeLayoutFrames layoutFrames =
      PDFComputeChromeLayoutFrames([contentView bounds], [workspaceController_ tabCount]);
  for (PDFTabContext* context in tabContexts) {
    if (context != [workspaceController_ activeContext]) {
      [context->containerView_ setFrame:layoutFrames.content_frame];
      [context->scrollView_ setFrame:layoutFrames.document_frame];
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
  [self stopSelectionAutoScroll];
  [interactionController_ cancelInteractiveRendering];
  [interactionController_ hidePageIndicator];
  if (keyMonitor_ != nil) {
    [NSEvent removeMonitor:keyMonitor_];
    keyMonitor_ = nil;
  }
  if (mouseMonitor_ != nil) {
    [NSEvent removeMonitor:mouseMonitor_];
    mouseMonitor_ = nil;
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  (void)sender;
  const NSUInteger tabCount = [workspaceController_ tabCount];
  if (tabCount <= 1) {
    return NSTerminateNow;
  }

  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleWarning];
  [alert setMessageText:@"Quit PDFView?"];
  [alert setInformativeText:[NSString stringWithFormat:@"Close %lu open tabs and quit PDFView?",
                                                       static_cast<unsigned long>(tabCount)]];
  [alert addButtonWithTitle:@"Quit"];
  [alert addButtonWithTitle:@"Cancel"];
  [alert setShowsSuppressionButton:NO];

  return [alert runModal] == NSAlertFirstButtonReturn ? NSTerminateNow : NSTerminateCancel;
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

  if (action == @selector(copy:)) {
    PDFTabContext* context = [workspaceController_ activeContext];
    return context != nil && [context hasSelectedText];
  }

  if (action == @selector(clearRecentDocuments:)) {
    return ![recentDocumentsController_ recentDocumentPaths].empty();
  }

  return YES;
}

- (BOOL)documentInteractionControllerIsContextActive:(PDFTabContext*)context {
  return [self isContextActive:context];
}

- (void)documentInteractionControllerUpdateVisiblePagesForContext:(PDFTabContext*)context {
  [self updateVisiblePagesForContext:context];
}

- (void)documentInteractionControllerUpdateCurrentPageFromScrollForContext:(PDFTabContext*)context {
  [self updateCurrentPageFromScrollForContext:context];
}

- (void)pageViewHostDidBeginTextSelectionAtPageIndex:(int)pageIndex location:(NSPoint)location {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil || ![self isContextActive:context]) {
    return;
  }

  [self stopSelectionAutoScroll];
  [interactionController_ cancelInteractiveRendering];
  const int charIndex = [self textIndexForPageSelectionAtPageIndex:pageIndex
                                                          location:location
                                                           context:context];
  [context beginTextSelectionOnPageIndex:pageIndex charIndex:charIndex];
}

- (void)pageViewHostDidDoubleClickTextAtPageIndex:(int)pageIndex location:(NSPoint)location {
  PDFTabContext* context = [workspaceController_ activeContext];
  [self stopSelectionAutoScroll];
  [interactionController_ cancelInteractiveRendering];
  [self selectWordAtPageIndex:pageIndex location:location context:context];
}

- (void)pageViewHostDidRequestContextMenuAtPageIndex:(int)pageIndex
                                            location:(NSPoint)location
                                               event:(NSEvent*)event {
  PDFTabContext* context = [workspaceController_ activeContext];
  if (context == nil || ![context selectionContainsPageIndex:pageIndex location:location]) {
    return;
  }
  [self showSelectionContextMenuWithEvent:event];
}

- (void)pageViewHostDidUpdateTextSelectionAtDocumentLocation:(NSPoint)location {
  PDFTabContext* context = [workspaceController_ activeContext];
  [self updateTextSelectionAtDocumentLocation:location context:context];
}

- (void)pageViewHostDidEndTextSelectionAtDocumentLocation:(NSPoint)location {
  PDFTabContext* context = [workspaceController_ activeContext];
  [self updateTextSelectionAtDocumentLocation:location context:context];
  [self stopSelectionAutoScroll];
  [context endTextSelection];
}

@end
