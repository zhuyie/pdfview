#import "mac/app_delegate.h"

#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <chrono>

#include "core/profiling.h"
#include "core/document.h"
#include "core/document_paths.h"
#include "core/recent_documents.h"
#include "mac/render_coordinator.h"
#include "mac/tab_context.h"

@interface PassiveTextField : NSTextField
@end

@implementation PassiveTextField

- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

@end

@interface PassiveLabel : NSTextField
@end

@implementation PassiveLabel

- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

@end

@interface EdgeFadeView : NSView
- (instancetype)initWithLeadingEdge:(BOOL)isLeadingEdge;
@end

@implementation EdgeFadeView {
  BOOL isLeadingEdge_;
}

- (instancetype)initWithLeadingEdge:(BOOL)isLeadingEdge {
  self = [super initWithFrame:NSZeroRect];
  if (self != nil) {
    isLeadingEdge_ = isLeadingEdge;
  }
  return self;
}

- (BOOL)isOpaque {
  return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSColor* solidColor = [NSColor colorWithCalibratedWhite:0.94 alpha:1.0];
  NSColor* softColor = [NSColor colorWithCalibratedWhite:0.94 alpha:0.32];
  NSColor* clearColor = [NSColor colorWithCalibratedWhite:0.94 alpha:0.0];
  NSArray<NSColor*>* colors = isLeadingEdge_
                                  ? @[ solidColor, softColor, clearColor ]
                                  : @[ clearColor, softColor, solidColor ];
  NSGradient* gradient = [[NSGradient alloc] initWithColors:colors];
  [gradient drawInRect:[self bounds] angle:0.0];
}

@end

namespace {

constexpr float kMinimumManualScale = 0.1f;
constexpr float kMaximumManualScale = 5.0f;

NSRect NSRectFromViewRect(const pdfview::core::ViewRect& rect) {
  return NSMakeRect(rect.x, rect.y, rect.width, rect.height);
}

NSButton* MakeToolbarSymbolButton(NSRect frame,
                                  NSString* symbolName,
                                  NSString* fallbackTitle,
                                  id target,
                                  SEL action,
                                  NSString* toolTip) {
  NSButton* button = [[NSButton alloc] initWithFrame:frame];
  [button setBezelStyle:NSBezelStyleTexturedRounded];
  [button setTarget:target];
  [button setAction:action];
  [button setToolTip:toolTip];

  NSImage* symbolImage = nil;
  if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
    symbolImage = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:toolTip];
  }

  if (symbolImage != nil) {
    if ([NSImageSymbolConfiguration class] != Nil) {
      NSImageSymbolConfiguration* configuration =
          [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightSemibold];
      symbolImage = [symbolImage imageWithSymbolConfiguration:configuration];
    }
    [button setImage:symbolImage];
    [button setImagePosition:NSImageOnly];
  } else {
    [button setTitle:fallbackTitle];
  }

  return button;
}

double MillisecondsSince(const std::chrono::steady_clock::time_point& start) {
  return std::chrono::duration_cast<std::chrono::duration<double, std::milli> >(
             std::chrono::steady_clock::now() - start)
      .count();
}

}  // namespace

@interface AppDelegate () <NSWindowDelegate, NSComboBoxDelegate, NSTextFieldDelegate, PDFRenderCoordinatorDelegate, NSMenuItemValidation>
- (void)installMainMenu;
- (void)rebuildOpenRecentMenu;
- (void)installApplicationIcon;
- (void)installTabStripInView:(NSView*)contentView;
- (void)installToolbarStripInView:(NSView*)contentView;
- (void)layoutChrome;
- (void)rebuildTabStrip;
- (void)computeTabStripMetrics:(std::vector<CGFloat>*)tabWidths
                    totalWidth:(CGFloat*)totalTabWidth
                    trackWidth:(CGFloat*)trackWidth
              visibleTrackWidth:(CGFloat*)visibleTrackWidth
                     maxOffset:(CGFloat*)maxOffset
            needsScrollButtons:(BOOL*)needsScrollButtons;
- (CGFloat)tabStripOffsetByStepping:(NSInteger)direction;
- (IBAction)scrollTabStripLeft:(id)sender;
- (IBAction)scrollTabStripRight:(id)sender;
- (void)updateToolbarForActiveTab;
- (BOOL)applyZoomString:(NSString*)rawValue;
- (IBAction)zoomComboBoxChanged:(id)sender;
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
- (PDFTabContext*)activeTabContext;
- (PDFTabContext*)contextForDocumentPath:(const std::string&)path;
- (void)selectTabContext:(PDFTabContext*)context;
- (void)closeTabContext:(PDFTabContext*)context;
- (IBAction)selectTabFromStrip:(id)sender;
- (IBAction)closeTabFromStrip:(id)sender;
- (PDFTabContext*)contextForClipView:(NSClipView*)clipView;
- (IBAction)openDocument:(id)sender;
- (IBAction)openRecentDocument:(id)sender;
- (IBAction)openStartupRecentDocument:(id)sender;
- (IBAction)clearRecentDocuments:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)showHelp:(id)sender;
- (void)installStartupViewInHost:(NSView*)hostView;
- (void)rebuildStartupView;
- (void)layoutStartupView;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSView* tabBarView_;
  NSView* tabStripContentView_;
  NSView* tabStripRightFadeView_;
  NSView* contentHostView_;
  NSView* startupView_;
  NSView* startupOpenPanelView_;
  NSView* startupRecentListView_;
  NSButton* startupClearButton_;
  NSButton* startupSelectFileButton_;
  NSButton* tabScrollLeftButton_;
  NSButton* tabScrollRightButton_;
  NSView* toolbarStrip_;
  NSView* pageIndicatorView_;
  PassiveLabel* pageIndicatorLabel_;
  NSComboBox* zoomComboBox_;
  NSButton* zoomOutButton_;
  NSButton* zoomInButton_;
  NSButton* zoomActualButton_;
  NSButton* fitWidthButton_;
  NSButton* fitPageButton_;
  NSMenu* openRecentMenu_;
  std::vector<std::string> recentDocumentPaths_;
  BOOL zoomComboBoxEditing_;
  NSMutableArray* tabContexts_;
  PDFTabContext* selectedTabContext_;
  CGFloat tabStripScrollOffset_;
  PDFRenderCoordinator* renderCoordinator_;
  NSTimer* interactiveRenderTimer_;
  NSTimer* pageIndicatorTimer_;
  PDFTabContext* interactiveRenderContext_;
  BOOL suppressScrollTracking_;
  BOOL shouldEnsureSelectedTabVisible_;
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
    openRecentMenu_ = nil;
    selectedTabContext_ = nil;
    tabStripScrollOffset_ = 0.0f;
    recentDocumentPaths_ = pdfview::core::load_recent_documents();
    renderCoordinator_ = [[PDFRenderCoordinator alloc] initWithDelegate:self];
    interactiveRenderTimer_ = nil;
    pageIndicatorTimer_ = nil;
    interactiveRenderContext_ = nil;
    suppressScrollTracking_ = NO;
    shouldEnsureSelectedTabVisible_ = YES;
    tabContexts_ = [[NSMutableArray alloc] init];
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
  openRecentMenu_ = [[NSMenu alloc] initWithTitle:@"Open Recent"];
  [openRecentItem setSubmenu:openRecentMenu_];
  [fileMenu addItem:openRecentItem];
  [self rebuildOpenRecentMenu];

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

- (void)rebuildOpenRecentMenu {
  if (openRecentMenu_ == nil) {
    return;
  }

  [openRecentMenu_ removeAllItems];

  if (recentDocumentPaths_.empty()) {
    NSMenuItem* emptyItem =
        [[NSMenuItem alloc] initWithTitle:@"No Recent Documents" action:nil keyEquivalent:@""];
    [emptyItem setEnabled:NO];
    [openRecentMenu_ addItem:emptyItem];
    return;
  }

  for (size_t index = 0; index < recentDocumentPaths_.size(); ++index) {
    NSString* path = [NSString stringWithUTF8String:recentDocumentPaths_[index].c_str()];
    if (path == nil || [path length] == 0) {
      continue;
    }
    NSMenuItem* item =
        [[NSMenuItem alloc] initWithTitle:[path lastPathComponent]
                                   action:@selector(openRecentDocument:)
                            keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:path];
    [item setToolTip:path];
    [openRecentMenu_ addItem:item];
  }

  [openRecentMenu_ addItem:[NSMenuItem separatorItem]];
  NSMenuItem* clearItem =
      [[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                 action:@selector(clearRecentDocuments:)
                          keyEquivalent:@""];
  [clearItem setTarget:self];
  [openRecentMenu_ addItem:clearItem];
}

- (void)computeTabStripMetrics:(std::vector<CGFloat>*)tabWidths
                    totalWidth:(CGFloat*)totalTabWidth
                    trackWidth:(CGFloat*)trackWidth
              visibleTrackWidth:(CGFloat*)visibleTrackWidth
                     maxOffset:(CGFloat*)maxOffset
            needsScrollButtons:(BOOL*)needsScrollButtons {
  if (tabWidths != nullptr) {
    tabWidths->clear();
    tabWidths->reserve([tabContexts_ count]);
  }
  if (totalTabWidth != nullptr) {
    *totalTabWidth = 0.0f;
  }

  const CGFloat tabGap = 8.0f;
  const CGFloat leadingInset = 10.0f;
  const CGFloat trailingInset = 10.0f;
  const CGFloat leftPadding = 12.0f;
  const CGFloat closeButtonSize = 22.0f;
  const CGFloat closeRightInset = 8.0f;
  const CGFloat titleToCloseGap = 8.0f;
  const CGFloat rightReserved = closeButtonSize + closeRightInset + titleToCloseGap;
  const CGFloat scrollButtonWidth = 22.0f;
  const CGFloat scrollButtonGap = 6.0f;
  const CGFloat scrollButtonsLeftGap = 10.0f;
  const CGFloat fadeWidth = 32.0f;

  CGFloat computedTotalWidth = 0.0f;
  for (PDFTabContext* context in tabContexts_) {
    NSString* title = [context tabTitle];
    NSDictionary* attributes = @{
      NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
    };
    const CGFloat titleWidth = std::ceil([title sizeWithAttributes:attributes].width);
    const CGFloat tabWidth =
        std::min(std::max(titleWidth + leftPadding + rightReserved + 4.0, 150.0), 320.0);
    if (tabWidths != nullptr) {
      tabWidths->push_back(tabWidth);
    }
    computedTotalWidth += tabWidth;
  }

  if ([tabContexts_ count] > 1) {
    computedTotalWidth += tabGap * ([tabContexts_ count] - 1);
  }

  const CGFloat fullTrackWidth =
      std::max(NSWidth([tabBarView_ bounds]) - leadingInset - trailingInset, 0.0);
  const BOOL shouldShowScrollButtons = computedTotalWidth > fullTrackWidth;
  const CGFloat buttonAreaWidth =
      shouldShowScrollButtons
          ? (scrollButtonWidth * 2.0f + scrollButtonGap + scrollButtonsLeftGap)
          : 0.0f;
  const CGFloat computedTrackWidth = std::max(fullTrackWidth - buttonAreaWidth, 0.0);
  const CGFloat computedVisibleTrackWidth =
      std::max(computedTrackWidth - (shouldShowScrollButtons ? fadeWidth : 0.0f), 0.0);
  const CGFloat computedMaxOffset = std::max(computedTotalWidth - computedTrackWidth, 0.0);

  if (totalTabWidth != nullptr) {
    *totalTabWidth = computedTotalWidth;
  }
  if (trackWidth != nullptr) {
    *trackWidth = computedTrackWidth;
  }
  if (visibleTrackWidth != nullptr) {
    *visibleTrackWidth = computedVisibleTrackWidth;
  }
  if (maxOffset != nullptr) {
    *maxOffset = computedMaxOffset;
  }
  if (needsScrollButtons != nullptr) {
    *needsScrollButtons = shouldShowScrollButtons;
  }
}

- (CGFloat)tabStripOffsetByStepping:(NSInteger)direction {
  std::vector<CGFloat> tabWidths;
  CGFloat totalTabWidth = 0.0f;
  CGFloat trackWidth = 0.0f;
  CGFloat visibleTrackWidth = 0.0f;
  CGFloat maxOffset = 0.0f;
  BOOL needsScrollButtons = NO;
  [self computeTabStripMetrics:&tabWidths
                    totalWidth:&totalTabWidth
                    trackWidth:&trackWidth
              visibleTrackWidth:&visibleTrackWidth
                     maxOffset:&maxOffset
            needsScrollButtons:&needsScrollButtons];
  (void)totalTabWidth;

  if (!needsScrollButtons || tabWidths.empty()) {
    return 0.0f;
  }

  const CGFloat tabGap = 8.0f;
  const CGFloat currentOffset = std::min(std::max(tabStripScrollOffset_, 0.0), maxOffset);
  const CGFloat visibleStart = currentOffset;
  const CGFloat visibleEnd = currentOffset + visibleTrackWidth;

  CGFloat x = 0.0f;
  if (direction > 0) {
    for (CGFloat tabWidth : tabWidths) {
      const CGFloat tabStart = x;
      const CGFloat tabEnd = x + tabWidth;
      if (tabEnd > visibleEnd + 0.5f) {
        return std::min(tabStart, maxOffset);
      }
      x = tabEnd + tabGap;
    }
    return maxOffset;
  }

  for (CGFloat tabWidth : tabWidths) {
    const CGFloat tabStart = x;
    const CGFloat tabEnd = x + tabWidth;
    if (tabStart >= visibleStart - 0.5f) {
      break;
    }
    if (tabEnd > visibleStart + 0.5f) {
      return tabStart;
    }
    x = tabEnd + tabGap;
  }

  CGFloat previousStart = 0.0f;
  x = 0.0f;
  for (CGFloat tabWidth : tabWidths) {
    const CGFloat tabStart = x;
    const CGFloat tabEnd = x + tabWidth;
    if (tabEnd >= visibleStart - 0.5f) {
      return previousStart;
    }
    previousStart = tabStart;
    x = tabEnd + tabGap;
  }

  return 0.0f;
}

- (void)rebuildTabStrip {
  if (tabBarView_ == nil) {
    return;
  }

  NSArray<NSView*>* subviews = [[tabBarView_ subviews] copy];
  for (NSView* subview in subviews) {
    if ([subview isKindOfClass:[NSBox class]] ||
        subview == tabStripContentView_ ||
        subview == tabStripRightFadeView_ ||
        subview == tabScrollLeftButton_ ||
        subview == tabScrollRightButton_) {
      continue;
    }
    [subview removeFromSuperview];
  }

  NSArray<NSView*>* tabSubviews = [[tabStripContentView_ subviews] copy];
  for (NSView* subview in tabSubviews) {
    [subview removeFromSuperview];
  }

  if ([tabContexts_ count] == 0) {
    tabStripScrollOffset_ = 0.0f;
    [tabScrollLeftButton_ setHidden:YES];
    [tabScrollRightButton_ setHidden:YES];
    [tabStripRightFadeView_ setHidden:YES];
    return;
  }

  const CGFloat tabHeight = 26.0f;
  const CGFloat topInset = 4.0f;
  const CGFloat tabGap = 8.0f;
  const CGFloat leadingInset = 10.0f;
  const CGFloat trailingInset = 10.0f;
  const CGFloat leftPadding = 12.0f;
  const CGFloat closeButtonSize = 22.0f;
  const CGFloat closeRightInset = 8.0f;
  const CGFloat titleToCloseGap = 8.0f;
  const CGFloat rightReserved = closeButtonSize + closeRightInset + titleToCloseGap;
  const CGFloat scrollButtonWidth = 22.0f;
  const CGFloat scrollButtonGap = 6.0f;
  const CGFloat scrollButtonsLeftGap = 12.0f;
  const CGFloat fadeWidth = 32.0f;
  std::vector<CGFloat> tabWidths;
  CGFloat totalTabWidth = 0.0f;
  CGFloat trackWidth = 0.0f;
  CGFloat visibleTrackWidth = 0.0f;
  CGFloat maxOffset = 0.0f;
  BOOL needsScrollButtons = NO;
  [self computeTabStripMetrics:&tabWidths
                    totalWidth:&totalTabWidth
                    trackWidth:&trackWidth
              visibleTrackWidth:&visibleTrackWidth
                     maxOffset:&maxOffset
            needsScrollButtons:&needsScrollButtons];
  tabStripScrollOffset_ = std::min(std::max(tabStripScrollOffset_, 0.0), maxOffset);

  NSUInteger selectedIndex = NSNotFound;
  for (NSUInteger index = 0; index < [tabContexts_ count]; ++index) {
    if ([tabContexts_ objectAtIndex:index] == selectedTabContext_) {
      selectedIndex = index;
      break;
    }
  }

  if (shouldEnsureSelectedTabVisible_ && selectedIndex != NSNotFound) {
    CGFloat selectedMinX = 0.0f;
    for (NSUInteger index = 0; index < selectedIndex; ++index) {
      selectedMinX += tabWidths[index] + tabGap;
    }
    const CGFloat selectedMaxX = selectedMinX + tabWidths[selectedIndex];
    if (selectedMinX < tabStripScrollOffset_) {
      tabStripScrollOffset_ = selectedMinX;
    } else if (selectedMaxX > tabStripScrollOffset_ + visibleTrackWidth) {
      tabStripScrollOffset_ = selectedMaxX - visibleTrackWidth;
    }
    tabStripScrollOffset_ = std::min(std::max(tabStripScrollOffset_, 0.0), maxOffset);
  }
  shouldEnsureSelectedTabVisible_ = NO;

  [tabScrollLeftButton_ setHidden:!needsScrollButtons];
  [tabScrollRightButton_ setHidden:!needsScrollButtons];
  [tabStripContentView_ setFrame:NSMakeRect(leadingInset,
                                            0.0f,
                                            trackWidth,
                                            NSHeight([tabBarView_ bounds]))];
  const BOOL hasClippedTabsBehindFade =
      needsScrollButtons && (tabStripScrollOffset_ < maxOffset - 0.5f);
  [tabStripRightFadeView_ setFrame:NSMakeRect(leadingInset + trackWidth - fadeWidth,
                                              1.0f,
                                              fadeWidth,
                                              NSHeight([tabBarView_ bounds]) - 1.0f)];
  [tabStripRightFadeView_ setHidden:!hasClippedTabsBehindFade];
  if (needsScrollButtons) {
    const CGFloat buttonY = 6.0f;
    const CGFloat rightButtonX = NSWidth([tabBarView_ bounds]) - trailingInset - scrollButtonWidth;
    const CGFloat leftButtonX = rightButtonX - scrollButtonGap - scrollButtonWidth;
    [tabScrollLeftButton_ setFrame:NSMakeRect(leftButtonX, buttonY, scrollButtonWidth, 22.0f)];
    [tabScrollRightButton_ setFrame:NSMakeRect(rightButtonX, buttonY, scrollButtonWidth, 22.0f)];
    [tabScrollLeftButton_ setEnabled:tabStripScrollOffset_ > 0.5f];
    [tabScrollRightButton_ setEnabled:tabStripScrollOffset_ + visibleTrackWidth < totalTabWidth - 0.5f];
  }

  CGFloat x = -tabStripScrollOffset_;
  for (NSUInteger tabIndex = 0; tabIndex < [tabContexts_ count]; ++tabIndex) {
    PDFTabContext* context = [tabContexts_ objectAtIndex:tabIndex];
    const BOOL isSelected = context == selectedTabContext_;
    const CGFloat tabWidth = tabWidths[tabIndex];
    NSString* title = [context tabTitle];

    if (x + tabWidth < -tabGap) {
      x += tabWidth + tabGap;
      continue;
    }
    if (x > trackWidth + tabGap) {
      break;
    }

    NSView* tabContainer =
        [[NSView alloc] initWithFrame:NSMakeRect(x, topInset, tabWidth, tabHeight)];
    [tabContainer setWantsLayer:YES];
    [[tabContainer layer] setCornerRadius:7.0];
    [[tabContainer layer] setBorderWidth:isSelected ? 1.0 : 0.0];
    [[tabContainer layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.78 alpha:1.0] CGColor]];
    [[tabContainer layer] setBackgroundColor:[(isSelected
                                               ? [NSColor colorWithCalibratedWhite:1.0 alpha:1.0]
                                               : [NSColor colorWithCalibratedWhite:0.90 alpha:1.0]) CGColor]];
    [tabStripContentView_ addSubview:tabContainer];

    const CGFloat labelHeight = 17.0f;
    const CGFloat labelY = std::floor((tabHeight - labelHeight) * 0.5f) - 1.0f;
    PassiveTextField* titleLabel =
        [[PassiveTextField alloc] initWithFrame:NSMakeRect(leftPadding,
                                                           labelY,
                                                           tabWidth - leftPadding - rightReserved,
                                                           labelHeight)];
    [titleLabel setEditable:NO];
    [titleLabel setBezeled:NO];
    [titleLabel setBordered:NO];
    [titleLabel setDrawsBackground:NO];
    [titleLabel setSelectable:NO];
    [titleLabel setStringValue:title];
    [titleLabel setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
    [titleLabel setTextColor:(isSelected
                              ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]
                              : [NSColor colorWithCalibratedWhite:0.28 alpha:1.0])];
    [titleLabel setUsesSingleLineMode:YES];
    [[titleLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[titleLabel cell] setWraps:NO];
    [titleLabel setAlignment:NSTextAlignmentLeft];
    [tabContainer addSubview:titleLabel];

    NSButton* tabButton =
        [[NSButton alloc] initWithFrame:[tabContainer bounds]];
    [tabButton setTitle:@""];
    [tabButton setBezelStyle:NSBezelStyleRegularSquare];
    [tabButton setButtonType:NSButtonTypeMomentaryPushIn];
    [tabButton setBordered:NO];
    [tabButton setTransparent:YES];
    [tabButton setTarget:self];
    [tabButton setAction:@selector(selectTabFromStrip:)];
    [tabButton setTag:[tabContexts_ indexOfObjectIdenticalTo:context]];
    [tabContainer addSubview:tabButton positioned:NSWindowBelow relativeTo:titleLabel];

    NSButton* closeButton =
        [[NSButton alloc] initWithFrame:NSMakeRect(tabWidth - closeRightInset - closeButtonSize,
                                                   2.0f,
                                                   closeButtonSize,
                                                   closeButtonSize)];
    [closeButton setTitle:@"×"];
    [closeButton setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
    [closeButton setBezelStyle:NSBezelStyleRegularSquare];
    [closeButton setBordered:NO];
    [closeButton setContentTintColor:(isSelected
                                      ? [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]
                                      : [NSColor colorWithCalibratedWhite:0.45 alpha:1.0])];
    [closeButton setTarget:self];
    [closeButton setAction:@selector(closeTabFromStrip:)];
    [closeButton setTag:[tabContexts_ indexOfObjectIdenticalTo:context]];
    [tabContainer addSubview:closeButton];

    x += tabWidth + tabGap;
  }

  if (needsScrollButtons) {
    [tabBarView_ addSubview:tabStripRightFadeView_ positioned:NSWindowAbove relativeTo:nil];
    [tabBarView_ addSubview:tabScrollLeftButton_ positioned:NSWindowAbove relativeTo:nil];
    [tabBarView_ addSubview:tabScrollRightButton_ positioned:NSWindowAbove relativeTo:nil];
  }
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
  tabBarView_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 34)];
  [tabBarView_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [tabBarView_ setWantsLayer:YES];
  [[tabBarView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.94 alpha:1.0] CGColor]];
  [[tabBarView_ layer] setMasksToBounds:YES];
  [contentView addSubview:tabBarView_];

  tabStripContentView_ = [[NSView alloc] initWithFrame:[tabBarView_ bounds]];
  [tabStripContentView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [tabStripContentView_ setWantsLayer:YES];
  [[tabStripContentView_ layer] setMasksToBounds:YES];
  [tabBarView_ addSubview:tabStripContentView_];

  tabStripRightFadeView_ = [[EdgeFadeView alloc] initWithLeadingEdge:NO];
  [tabStripRightFadeView_ setFrame:NSMakeRect(0, 0, 32, 34)];
  [tabStripRightFadeView_ setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
  [tabStripRightFadeView_ setHidden:YES];
  [tabBarView_ addSubview:tabStripRightFadeView_ positioned:NSWindowAbove relativeTo:tabStripContentView_];

  NSBox* divider = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
  [divider setBoxType:NSBoxSeparator];
  [divider setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [tabBarView_ addSubview:divider positioned:NSWindowAbove relativeTo:tabStripContentView_];

  tabScrollRightButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
  [tabScrollRightButton_ setTitle:@"›"];
  [tabScrollRightButton_ setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
  [tabScrollRightButton_ setBezelStyle:NSBezelStyleTexturedRounded];
  [tabScrollRightButton_ setTarget:self];
  [tabScrollRightButton_ setAction:@selector(scrollTabStripRight:)];
  [tabScrollRightButton_ setHidden:YES];
  [tabBarView_ addSubview:tabScrollRightButton_];

  tabScrollLeftButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
  [tabScrollLeftButton_ setTitle:@"‹"];
  [tabScrollLeftButton_ setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
  [tabScrollLeftButton_ setBezelStyle:NSBezelStyleTexturedRounded];
  [tabScrollLeftButton_ setTarget:self];
  [tabScrollLeftButton_ setAction:@selector(scrollTabStripLeft:)];
  [tabScrollLeftButton_ setHidden:YES];
  [tabBarView_ addSubview:tabScrollLeftButton_];

  contentHostView_ = [[NSView alloc] initWithFrame:[contentView bounds]];
  [contentHostView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [contentHostView_ setWantsLayer:YES];
  [[contentHostView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
  [contentView addSubview:contentHostView_ positioned:NSWindowBelow relativeTo:tabBarView_];
  [self installStartupViewInHost:contentHostView_];
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

  zoomOutButton_ = MakeToolbarSymbolButton(NSMakeRect(12, 4, 26, 22),
                                           @"minus",
                                           @"-",
                                           self,
                                           @selector(zoomOut),
                                           @"Zoom Out");
  [toolbarStrip_ addSubview:zoomOutButton_];

  zoomComboBox_ = [[NSComboBox alloc] initWithFrame:NSMakeRect(44, 3, 92, 24)];
  [zoomComboBox_ setUsesDataSource:NO];
  [zoomComboBox_ setCompletes:NO];
  [zoomComboBox_ setEditable:YES];
  [zoomComboBox_ setDelegate:self];
  [[zoomComboBox_ cell] setWraps:NO];
  [zoomComboBox_ addItemsWithObjectValues:[NSArray arrayWithObjects:@"50%", @"75%", @"100%", @"125%", @"150%", @"200%", @"300%", nil]];
  [toolbarStrip_ addSubview:zoomComboBox_];

  zoomInButton_ = MakeToolbarSymbolButton(NSMakeRect(142, 4, 26, 22),
                                          @"plus",
                                          @"+",
                                          self,
                                          @selector(zoomIn),
                                          @"Zoom In");
  [toolbarStrip_ addSubview:zoomInButton_];

  zoomActualButton_ = MakeToolbarSymbolButton(NSMakeRect(176, 4, 32, 22),
                                              @"1.circle",
                                              @"100",
                                              self,
                                              @selector(zoomToActualSize),
                                              @"Zoom to 100%");
  [toolbarStrip_ addSubview:zoomActualButton_];

  fitWidthButton_ = MakeToolbarSymbolButton(NSMakeRect(214, 4, 32, 22),
                                            @"arrow.left.and.right.square",
                                            @"Width",
                                            self,
                                            @selector(resetZoomToFitWidth),
                                            @"Fit Width");
  [toolbarStrip_ addSubview:fitWidthButton_];

  fitPageButton_ = MakeToolbarSymbolButton(NSMakeRect(252, 4, 32, 22),
                                           @"document",
                                           @"Page",
                                           self,
                                           @selector(fitZoomToPage),
                                           @"Fit Page");
  [toolbarStrip_ addSubview:fitPageButton_];
}

- (void)installStartupViewInHost:(NSView*)hostView {
  startupView_ = [[NSView alloc] initWithFrame:[hostView bounds]];
  [startupView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [startupView_ setWantsLayer:YES];
  [[startupView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.96 alpha:1.0] CGColor]];
  [hostView addSubview:startupView_];

  NSTextField* titleLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
  [titleLabel setEditable:NO];
  [titleLabel setBezeled:NO];
  [titleLabel setBordered:NO];
  [titleLabel setDrawsBackground:NO];
  [titleLabel setSelectable:NO];
  [titleLabel setStringValue:@"Recents"];
  [titleLabel setFont:[NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold]];
  [titleLabel setTextColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
  [titleLabel setTag:1001];
  [startupView_ addSubview:titleLabel];

  startupClearButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 116, 28)];
  [startupClearButton_ setTitle:@"Clear Recents"];
  [startupClearButton_ setBezelStyle:NSBezelStyleRounded];
  [startupClearButton_ setTarget:self];
  [startupClearButton_ setAction:@selector(clearRecentDocuments:)];
  [startupView_ addSubview:startupClearButton_];

  startupOpenPanelView_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 132)];
  [startupOpenPanelView_ setWantsLayer:YES];
  [[startupOpenPanelView_ layer] setCornerRadius:16.0f];
  [[startupOpenPanelView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] CGColor]];
  [[startupOpenPanelView_ layer] setBorderWidth:1.0f];
  [[startupOpenPanelView_ layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] CGColor]];
  [startupView_ addSubview:startupOpenPanelView_];

  NSTextField* openTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
  [openTitleLabel setEditable:NO];
  [openTitleLabel setBezeled:NO];
  [openTitleLabel setBordered:NO];
  [openTitleLabel setDrawsBackground:NO];
  [openTitleLabel setSelectable:NO];
  [openTitleLabel setStringValue:@"Open new document"];
  [openTitleLabel setFont:[NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold]];
  [openTitleLabel setTextColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
  [openTitleLabel setTag:1002];
  [startupView_ addSubview:openTitleLabel];

  startupSelectFileButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(24, 48, 108, 30)];
  [startupSelectFileButton_ setTitle:@"Select File"];
  [startupSelectFileButton_ setBezelStyle:NSBezelStyleRounded];
  [startupSelectFileButton_ setTarget:self];
  [startupSelectFileButton_ setAction:@selector(openDocument:)];
  [startupOpenPanelView_ addSubview:startupSelectFileButton_];

  NSTextField* openHintLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 84, 220, 16)];
  [openHintLabel setEditable:NO];
  [openHintLabel setBezeled:NO];
  [openHintLabel setBordered:NO];
  [openHintLabel setDrawsBackground:NO];
  [openHintLabel setSelectable:NO];
  [openHintLabel setStringValue:@"Choose a PDF from disk, or drag one here."];
  [openHintLabel setFont:[NSFont systemFontOfSize:12.0]];
  [openHintLabel setTextColor:[NSColor colorWithCalibratedWhite:0.46 alpha:1.0]];
  [openHintLabel setTag:1003];
  [startupOpenPanelView_ addSubview:openHintLabel];

  NSImageView* openIconView = [[NSImageView alloc] initWithFrame:NSMakeRect(442, 18, 92, 92)];
  if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
    NSImage* icon = [NSImage imageWithSystemSymbolName:@"doc.text.image"
                               accessibilityDescription:@"Document"];
    if (icon != nil && [NSImageSymbolConfiguration class] != Nil) {
      icon = [icon imageWithSymbolConfiguration:
                  [NSImageSymbolConfiguration configurationWithPointSize:56.0
                                                                  weight:NSFontWeightLight]];
    }
    [openIconView setImage:icon];
    [openIconView setContentTintColor:[NSColor colorWithCalibratedWhite:0.65 alpha:1.0]];
  }
  [openIconView setImageScaling:NSImageScaleProportionallyUpOrDown];
  [startupOpenPanelView_ addSubview:openIconView];

  startupRecentListView_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 300)];
  [startupRecentListView_ setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin |
                                           NSViewMinYMargin | NSViewMaxYMargin];
  [startupRecentListView_ setWantsLayer:YES];
  [[startupRecentListView_ layer] setCornerRadius:14.0f];
  [[startupRecentListView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] CGColor]];
  [[startupRecentListView_ layer] setBorderWidth:1.0f];
  [[startupRecentListView_ layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] CGColor]];
  [startupView_ addSubview:startupRecentListView_];

  [self layoutStartupView];
  [self rebuildStartupView];
}

- (void)rebuildStartupView {
  if (startupRecentListView_ == nil) {
    return;
  }

  [self layoutStartupView];
  [startupClearButton_ setEnabled:!recentDocumentPaths_.empty()];

  NSArray<NSView*>* subviews = [[startupRecentListView_ subviews] copy];
  for (NSView* subview in subviews) {
    [subview removeFromSuperview];
  }

  if (recentDocumentPaths_.empty()) {
    NSTextField* emptyLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(24, 26, 360, 22)];
    [emptyLabel setEditable:NO];
    [emptyLabel setBezeled:NO];
    [emptyLabel setBordered:NO];
    [emptyLabel setDrawsBackground:NO];
    [emptyLabel setSelectable:NO];
    [emptyLabel setStringValue:@"No recent documents yet."];
    [emptyLabel setFont:[NSFont systemFontOfSize:14.0]];
    [emptyLabel setTextColor:[NSColor colorWithCalibratedWhite:0.46 alpha:1.0]];
    [startupRecentListView_ addSubview:emptyLabel];
    return;
  }

  const CGFloat rowHeight = 44.0f;
  const CGFloat rowGap = 10.0f;
  const CGFloat leftInset = 18.0f;
  const CGFloat topInset = 18.0f;
  const CGFloat maxWidth = NSWidth([startupRecentListView_ bounds]) - leftInset * 2.0f;

  for (size_t index = 0; index < recentDocumentPaths_.size(); ++index) {
    NSString* path = [NSString stringWithUTF8String:recentDocumentPaths_[index].c_str()];
    if (path == nil || [path length] == 0) {
      continue;
    }

    const CGFloat y = NSHeight([startupRecentListView_ bounds]) - topInset - rowHeight - index * (rowHeight + rowGap);
    if (y < 16.0f) {
      break;
    }

    NSButton* rowButton =
        [[NSButton alloc] initWithFrame:NSMakeRect(leftInset, y, maxWidth, rowHeight)];
    [rowButton setBezelStyle:NSBezelStyleRegularSquare];
    [rowButton setBordered:NO];
    [rowButton setButtonType:NSButtonTypeMomentaryPushIn];
    [rowButton setTarget:self];
    [rowButton setAction:@selector(openStartupRecentDocument:)];
    [rowButton setTag:static_cast<NSInteger>(index)];
    [rowButton setTitle:@""];
    [rowButton setToolTip:path];
    [rowButton setWantsLayer:YES];
    [[rowButton layer] setCornerRadius:10.0f];
    [[rowButton layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.97 alpha:1.0] CGColor]];
    [[rowButton layer] setBorderWidth:1.0f];
    [[rowButton layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] CGColor]];
    [startupRecentListView_ addSubview:rowButton];

    NSTextField* nameLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(14.0f, 20.0f, maxWidth - 28.0f, 18.0f)];
    [nameLabel setEditable:NO];
    [nameLabel setBezeled:NO];
    [nameLabel setBordered:NO];
    [nameLabel setDrawsBackground:NO];
    [nameLabel setSelectable:NO];
    [nameLabel setStringValue:[path lastPathComponent]];
    [nameLabel setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium]];
    [nameLabel setTextColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
    [nameLabel setUsesSingleLineMode:YES];
    [[nameLabel cell] setWraps:NO];
    [[nameLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [rowButton addSubview:nameLabel];

    NSTextField* pathLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(14.0f, 6.0f, maxWidth - 28.0f, 14.0f)];
    [pathLabel setEditable:NO];
    [pathLabel setBezeled:NO];
    [pathLabel setBordered:NO];
    [pathLabel setDrawsBackground:NO];
    [pathLabel setSelectable:NO];
    NSString* directoryPath = [path stringByDeletingLastPathComponent];
    [pathLabel setStringValue:directoryPath];
    [pathLabel setFont:[NSFont systemFontOfSize:11.0]];
    [pathLabel setTextColor:[NSColor colorWithCalibratedWhite:0.47 alpha:1.0]];
    [pathLabel setUsesSingleLineMode:YES];
    [[pathLabel cell] setWraps:NO];
    [[pathLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [rowButton addSubview:pathLabel];
  }
}

- (void)layoutStartupView {
  if (startupView_ == nil || startupOpenPanelView_ == nil ||
      startupRecentListView_ == nil || startupClearButton_ == nil) {
    return;
  }

  const NSRect bounds = [startupView_ bounds];
  NSTextField* titleLabel = (NSTextField*)[startupView_ viewWithTag:1001];
  NSTextField* openTitleLabel = (NSTextField*)[startupView_ viewWithTag:1002];
  const CGFloat contentWidth = 560.0f;
  const CGFloat openPanelHeight = 132.0f;
  const CGFloat openHeaderHeight = 28.0f;
  const CGFloat rowHeight = 44.0f;
  const CGFloat rowGap = 10.0f;
  const CGFloat listTopInset = 18.0f;
  const CGFloat listBottomInset = 18.0f;
  const size_t visibleRowCount = std::min<size_t>(recentDocumentPaths_.empty() ? 1 : recentDocumentPaths_.size(), 5);
  const CGFloat listHeight =
      recentDocumentPaths_.empty()
          ? 76.0f
          : listTopInset + listBottomInset +
                visibleRowCount * rowHeight +
                std::max<CGFloat>(0.0f, static_cast<CGFloat>(visibleRowCount - 1)) * rowGap;
  const CGFloat headerHeight = 32.0f;
  const CGFloat openHeaderSpacing = 8.0f;
  const CGFloat sectionSpacing = 26.0f;
  const CGFloat headerSpacing = 8.0f;
  const CGFloat totalHeight =
      openHeaderHeight + openHeaderSpacing + openPanelHeight +
      sectionSpacing + headerHeight + headerSpacing + listHeight;
  const CGFloat originX = std::floor((NSWidth(bounds) - contentWidth) * 0.5f);
  const CGFloat originY = std::floor((NSHeight(bounds) - totalHeight) * 0.5f);

  [openTitleLabel setFrame:NSMakeRect(originX,
                                      originY + listHeight + headerHeight + headerSpacing +
                                          sectionSpacing + openPanelHeight + openHeaderSpacing + 2.0f,
                                      260.0f,
                                      24.0f)];
  [startupOpenPanelView_ setFrame:NSMakeRect(originX,
                                             originY + listHeight + headerHeight + headerSpacing + sectionSpacing,
                                             contentWidth,
                                             openPanelHeight)];
  [titleLabel setFrame:NSMakeRect(originX,
                                  originY + listHeight + headerSpacing + 2.0f,
                                  200.0f,
                                  28.0f)];
  [startupClearButton_ setFrame:NSMakeRect(originX + contentWidth - 116.0f,
                                           originY + listHeight + headerSpacing,
                                           116.0f,
                                           28.0f)];
  [startupRecentListView_ setFrame:NSMakeRect(originX, originY, contentWidth, listHeight)];
}

- (void)layoutChrome {
  if (contentHostView_ == nil || toolbarStrip_ == nil || tabBarView_ == nil) {
    return;
  }

  NSView* contentView = [window_ contentView];
  const NSRect contentBounds = [contentView bounds];
  const CGFloat tabBarHeight = [tabContexts_ count] > 0 ? 34.0f : 0.0f;
  const CGFloat toolbarHeight = 32.0f;
  PDFTabContext* context = [self activeTabContext];
  [tabBarView_ setHidden:[tabContexts_ count] == 0];
  [tabBarView_ setFrame:NSMakeRect(0,
                                   contentBounds.size.height - tabBarHeight,
                                   contentBounds.size.width,
                                   tabBarHeight)];
  [self rebuildTabStrip];

  if (context == nil) {
    [toolbarStrip_ setHidden:YES];
    [contentHostView_ setFrame:NSMakeRect(0, 0, contentBounds.size.width, contentBounds.size.height)];
    [startupView_ setHidden:NO];
    [startupView_ setFrame:[contentHostView_ bounds]];
    [self layoutStartupView];
    [self rebuildStartupView];
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

  const float currentScale = [self currentScaleForContext:context];
  [zoomComboBox_ setEnabled:YES];
  [zoomOutButton_ setEnabled:currentScale > kMinimumManualScale + 0.001f];
  [zoomInButton_ setEnabled:currentScale < kMaximumManualScale - 0.001f];
  [zoomActualButton_ setEnabled:std::abs(currentScale - 1.0f) > 0.001f];
  [fitWidthButton_ setEnabled:YES];
  [fitPageButton_ setEnabled:YES];
  [fitWidthButton_ setState:context->viewModel_.view_state().scale_mode == pdfview::core::ScaleMode::FitWidth
                                ? NSControlStateValueOn
                                : NSControlStateValueOff];
  [fitPageButton_ setState:context->viewModel_.view_state().scale_mode == pdfview::core::ScaleMode::FitPage
                               ? NSControlStateValueOn
                               : NSControlStateValueOff];
  [zoomComboBox_ setStringValue:[NSString stringWithFormat:@"%.0f%%",
                                                           currentScale * 100.0f]];
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

  [context setManualScale:std::min(std::max(static_cast<float>(zoomPercent / 100.0f),
                                            kMinimumManualScale),
                                   kMaximumManualScale)];
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
  PDFTabContext* existingContext = [self contextForDocumentPath:path];
  if (existingContext != nil) {
    [self selectTabContext:existingContext];
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
  recentDocumentPaths_ = pdfview::core::note_recent_document(recentDocumentPaths_, path);
  pdfview::core::save_recent_documents(recentDocumentPaths_);
  [self rebuildOpenRecentMenu];
  [self rebuildStartupView];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(tabClipViewDidScroll:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:[context->scrollView_ contentView]];

  [tabContexts_ addObject:context];
  [contentHostView_ addSubview:context->containerView_];
  [context->containerView_ setHidden:YES];

  if (makeActive || [tabContexts_ count] == 1) {
    [self selectTabContext:context];
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

- (IBAction)openStartupRecentDocument:(id)sender {
  if (![sender isKindOfClass:[NSButton class]]) {
    return;
  }

  const NSInteger index = [(NSButton*)sender tag];
  if (index < 0 || index >= static_cast<NSInteger>(recentDocumentPaths_.size())) {
    return;
  }

  [self openDocumentAtPath:recentDocumentPaths_[index] makeActive:YES];
}

- (IBAction)openRecentDocument:(id)sender {
  if (![sender isKindOfClass:[NSMenuItem class]]) {
    return;
  }

  NSString* path = [(NSMenuItem*)sender representedObject];
  if (path == nil || [path length] == 0) {
    return;
  }

  [self openDocumentAtPath:[path UTF8String] makeActive:YES];
}

- (IBAction)clearRecentDocuments:(id)sender {
  (void)sender;
  recentDocumentPaths_.clear();
  pdfview::core::save_recent_documents(recentDocumentPaths_);
  [self rebuildOpenRecentMenu];
  [self rebuildStartupView];
}

- (IBAction)closeCurrentTab:(id)sender {
  (void)sender;
  [self closeTabContext:[self activeTabContext]];
}

- (IBAction)showHelp:(id)sender {
  (void)sender;
  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleInformational];
  [alert setMessageText:@"PDFView Help"];
  [alert setInformativeText:@"Use File > Open... to open PDFs, tabs to switch documents, Cmd+W to close the current tab, and Cmd+Q to quit."];
  [alert runModal];
}

- (PDFTabContext*)activeTabContext {
  return selectedTabContext_;
}

- (PDFTabContext*)contextForDocumentPath:(const std::string&)path {
  for (PDFTabContext* context in tabContexts_) {
    if (pdfview::core::same_document_path(context->documentPath_, path)) {
      return context;
    }
  }

  return nil;
}

- (void)selectTabContext:(PDFTabContext*)context {
  if (context == nil) {
    selectedTabContext_ = nil;
    shouldEnsureSelectedTabVisible_ = YES;
    [self hidePageIndicator:nil];
    [window_ setTitle:@"PDFView"];
    [self layoutChrome];
    [self updateToolbarForActiveTab];
    return;
  }

  selectedTabContext_ = context;
  shouldEnsureSelectedTabVisible_ = YES;
  [self hidePageIndicator:nil];
  for (PDFTabContext* tabContext in tabContexts_) {
    [tabContext->containerView_ setHidden:tabContext != selectedTabContext_];
  }

  [window_ setTitle:[NSString stringWithFormat:@"PDFView - %@", [context tabTitle]]];
  [self layoutChrome];
  [self renderTabContext:context];
  [self updateToolbarForActiveTab];
}

- (void)closeTabContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  const NSUInteger closingIndex = [tabContexts_ indexOfObjectIdenticalTo:context];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:[context->scrollView_ contentView]];
  [context->containerView_ removeFromSuperview];
  [tabContexts_ removeObject:context];

  if ([tabContexts_ count] == 0) {
    selectedTabContext_ = nil;
    [self hidePageIndicator:nil];
    [window_ setTitle:@"PDFView"];
    [self layoutChrome];
    [self updateToolbarForActiveTab];
    return;
  }

  if (selectedTabContext_ == context) {
    const NSUInteger fallbackIndex =
        std::min(closingIndex, [tabContexts_ count] - 1);
    [self selectTabContext:[tabContexts_ objectAtIndex:fallbackIndex]];
    return;
  }

  shouldEnsureSelectedTabVisible_ = YES;
  [self layoutChrome];
  [self updateToolbarForActiveTab];
}

- (IBAction)selectTabFromStrip:(id)sender {
  if (![sender isKindOfClass:[NSButton class]]) {
    return;
  }

  const NSInteger index = [(NSButton*)sender tag];
  if (index < 0 || index >= [tabContexts_ count]) {
    return;
  }

  [self cancelInteractiveRendering];
  [self selectTabContext:[tabContexts_ objectAtIndex:index]];
}

- (IBAction)closeTabFromStrip:(id)sender {
  if (![sender isKindOfClass:[NSButton class]]) {
    return;
  }

  const NSInteger index = [(NSButton*)sender tag];
  if (index < 0 || index >= [tabContexts_ count]) {
    return;
  }

  [self closeTabContext:[tabContexts_ objectAtIndex:index]];
}

- (IBAction)scrollTabStripLeft:(id)sender {
  (void)sender;
  tabStripScrollOffset_ = [self tabStripOffsetByStepping:-1];
  shouldEnsureSelectedTabVisible_ = NO;
  [self rebuildTabStrip];
}

- (IBAction)scrollTabStripRight:(id)sender {
  (void)sender;
  tabStripScrollOffset_ = [self tabStripOffsetByStepping:1];
  shouldEnsureSelectedTabVisible_ = NO;
  [self rebuildTabStrip];
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

- (void)applyScaleChangeForContext:(PDFTabContext*)context
                        invalidate:(BOOL)invalidateRenderedPages
                        updateMode:(void (^)(PDFTabContext* context))updateMode {
  if (context == nil) {
    return;
  }

  [self cancelInteractiveRendering];
  [self updateCurrentPageFromScrollForContext:context];

  const NSRect visibleBounds = [[context->scrollView_ contentView] bounds];
  const pdfview::core::ViewportAnchor anchor = context->viewModel_.capture_viewport_anchor();
  const int anchorPageIndex = anchor.page_index;

  updateMode(context);
  if (invalidateRenderedPages) {
    [context invalidateRenderedPages];
  }

  suppressScrollTracking_ = YES;
  [self renderTabContext:context];
  context->viewModel_.mutable_view_state()->current_page = anchorPageIndex;

  const pdfview::core::ViewRect newPageRect = context->viewModel_.current_page_rect();
  if (newPageRect.height > 0.0f) {
    NSClipView* clipView = [context->scrollView_ contentView];
    const CGFloat targetOriginY = context->viewModel_.restored_scroll_y_for_anchor(anchor);
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
  PDFTabContext* context = [self activeTabContext];
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
  PDFTabContext* context = [self activeTabContext];
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
  PDFTabContext* context = [self activeTabContext];
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
  PDFTabContext* context = [self activeTabContext];
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
  PDFTabContext* context = [self activeTabContext];
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

- (void)pageDown {
  [self scrollActiveContextByViewportDelta:1.0f];
}

- (void)pageUp {
  [self scrollActiveContextByViewportDelta:-1.0f];
}

- (void)scrollActiveContextByViewportDelta:(CGFloat)deltaY {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  NSClipView* clipView = [context->scrollView_ contentView];
  const NSRect visibleBounds = [clipView bounds];
  const CGFloat viewportHeight = NSHeight(visibleBounds);
  const CGFloat pageStep = std::max(static_cast<CGFloat>(80.0), viewportHeight * 0.9f);
  const CGFloat maxOriginY = std::max(static_cast<CGFloat>(0.0),
                                      NSHeight([context->documentView_ frame]) - viewportHeight);
  const CGFloat targetOriginY =
      std::min(std::max(visibleBounds.origin.y + deltaY * pageStep, static_cast<CGFloat>(0.0)),
               maxOriginY);
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
  [clipView scrollToPoint:NSMakePoint([clipView bounds].origin.x,
                                      context->viewModel_.scroll_y_for_current_page())];
  [context->scrollView_ reflectScrolledClipView:clipView];
  context->viewModel_.set_scroll_origin([[context->scrollView_ contentView] bounds].origin.x,
                                        [[context->scrollView_ contentView] bounds].origin.y);
  [self updateVisiblePagesForContext:context];
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
    pageIndicatorView_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 72, 30)];
    [pageIndicatorView_ setWantsLayer:YES];
    [[pageIndicatorView_ layer] setCornerRadius:8.0f];
    [[pageIndicatorView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.10 alpha:0.78] CGColor]];
    [pageIndicatorView_ setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [pageIndicatorView_ setHidden:YES];

    pageIndicatorLabel_ = [[PassiveLabel alloc] initWithFrame:NSMakeRect(12, 6, 48, 18)];
    [pageIndicatorLabel_ setEditable:NO];
    [pageIndicatorLabel_ setBezeled:NO];
    [pageIndicatorLabel_ setBordered:NO];
    [pageIndicatorLabel_ setDrawsBackground:NO];
    [pageIndicatorLabel_ setSelectable:NO];
    [pageIndicatorLabel_ setAlignment:NSTextAlignmentCenter];
    [pageIndicatorLabel_ setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]];
    [pageIndicatorLabel_ setTextColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.96]];
    [pageIndicatorLabel_ setUsesSingleLineMode:YES];
    [[pageIndicatorLabel_ cell] setWraps:NO];
    [[pageIndicatorLabel_ cell] setLineBreakMode:NSLineBreakByClipping];
    [pageIndicatorView_ addSubview:pageIndicatorLabel_];
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

  const int currentPage = std::max(0, context->viewModel_.view_state().current_page);
  const int totalPages = context->viewModel_.page_count();
  NSString* text = [NSString stringWithFormat:@"%d / %d", currentPage + 1, totalPages];
  [pageIndicatorLabel_ setStringValue:text];

  NSDictionary* attributes = @{
    NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]
  };
  const CGFloat textWidth = std::ceil([text sizeWithAttributes:attributes].width);
  const CGFloat indicatorWidth = std::max(static_cast<CGFloat>(88.0), textWidth + 24.0f);
  const CGFloat indicatorHeight = 30.0f;
  const CGFloat rightMargin = 30.0f;
  const BOOL hasHorizontalScroller = [context->scrollView_ hasHorizontalScroller];
  const CGFloat bottomMargin = hasHorizontalScroller ? 24.0f : 16.0f;
  const NSRect containerBounds = [context->containerView_ bounds];
  [pageIndicatorView_ setFrame:NSMakeRect(containerBounds.size.width - indicatorWidth - rightMargin,
                                          bottomMargin,
                                          indicatorWidth,
                                          indicatorHeight)];
  [pageIndicatorLabel_ setFrame:NSMakeRect(12.0f,
                                           6.0f,
                                           indicatorWidth - 24.0f,
                                           18.0f)];
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
  PDFTabContext* context = [self contextForClipView:(NSClipView*)[notification object]];
  [self updateCurrentPageFromScrollForContext:context];
  [self showPageIndicatorForContext:context];
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
  for (PDFTabContext* context in tabContexts_) {
    if (context != [self activeTabContext]) {
      NSView* contentView = [window_ contentView];
      const NSRect contentBounds = [contentView bounds];
      const CGFloat tabBarHeight = [tabContexts_ count] > 0 ? 34.0f : 0.0f;
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
  const BOOL hasActiveDocument = [self activeTabContext] != nil;

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

  if (action == @selector(openRecentDocument:)) {
    return menuItem.representedObject != nil;
  }

  if (action == @selector(clearRecentDocuments:)) {
    return !recentDocumentPaths_.empty();
  }

  return YES;
}

@end
