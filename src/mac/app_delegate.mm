#import "mac/app_delegate.h"

#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <chrono>

#include "core/profiling.h"
#include "core/document.h"
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

@interface AppDelegate () <NSWindowDelegate, NSComboBoxDelegate, NSTextFieldDelegate, PDFRenderCoordinatorDelegate, NSMenuItemValidation>
- (void)installMainMenu;
- (void)rebuildOpenRecentMenu;
- (void)installApplicationIcon;
- (void)installTabStripInView:(NSView*)contentView;
- (void)installToolbarStripInView:(NSView*)contentView;
- (void)layoutChrome;
- (void)rebuildTabStrip;
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
- (void)scrollToCurrentPageInContext:(PDFTabContext*)context;
- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context;
- (void)installKeyMonitor;
- (PDFTabContext*)activeTabContext;
- (void)selectTabContext:(PDFTabContext*)context;
- (void)closeTabContext:(PDFTabContext*)context;
- (IBAction)selectTabFromStrip:(id)sender;
- (IBAction)closeTabFromStrip:(id)sender;
- (PDFTabContext*)contextForClipView:(NSClipView*)clipView;
- (IBAction)openDocument:(id)sender;
- (IBAction)openRecentDocument:(id)sender;
- (IBAction)clearRecentDocuments:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)showHelp:(id)sender;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSView* tabBarView_;
  NSView* contentHostView_;
  NSView* toolbarStrip_;
  NSComboBox* zoomComboBox_;
  NSButton* zoomOutButton_;
  NSButton* zoomInButton_;
  NSButton* fitWidthButton_;
  NSButton* fitPageButton_;
  NSMenu* openRecentMenu_;
  BOOL zoomComboBoxEditing_;
  NSMutableArray* tabContexts_;
  PDFTabContext* selectedTabContext_;
  PDFRenderCoordinator* renderCoordinator_;
  NSTimer* interactiveRenderTimer_;
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
    zoomComboBoxEditing_ = NO;
    openRecentMenu_ = nil;
    selectedTabContext_ = nil;
    renderCoordinator_ = [[PDFRenderCoordinator alloc] initWithDelegate:self];
    interactiveRenderTimer_ = nil;
    interactiveRenderContext_ = nil;
    suppressScrollTracking_ = NO;
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
  [window_ setTitle:@"pdfview"];
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
  NSMenuItem* helpItem = [[NSMenuItem alloc] initWithTitle:@"pdfview Help"
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

  NSArray<NSURL*>* recentURLs = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
  if ([recentURLs count] == 0) {
    NSMenuItem* emptyItem =
        [[NSMenuItem alloc] initWithTitle:@"No Recent Documents" action:nil keyEquivalent:@""];
    [emptyItem setEnabled:NO];
    [openRecentMenu_ addItem:emptyItem];
    return;
  }

  for (NSURL* url in recentURLs) {
    NSMenuItem* item =
        [[NSMenuItem alloc] initWithTitle:[url lastPathComponent]
                                   action:@selector(openRecentDocument:)
                            keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:url];
    [item setToolTip:[url path]];
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

- (void)rebuildTabStrip {
  if (tabBarView_ == nil) {
    return;
  }

  NSArray<NSView*>* subviews = [[tabBarView_ subviews] copy];
  for (NSView* subview in subviews) {
    if ([subview isKindOfClass:[NSBox class]]) {
      continue;
    }
    [subview removeFromSuperview];
  }

  CGFloat x = 10.0f;
  const CGFloat tabHeight = 26.0f;
  const CGFloat topInset = 4.0f;
  const CGFloat leftPadding = 12.0f;
  const CGFloat closeButtonSize = 22.0f;
  const CGFloat closeRightInset = 8.0f;
  const CGFloat titleToCloseGap = 8.0f;
  const CGFloat rightReserved = closeButtonSize + closeRightInset + titleToCloseGap;
  for (PDFTabContext* context in tabContexts_) {
    const BOOL isSelected = context == selectedTabContext_;
    NSString* title = [context tabTitle];
    NSDictionary* attributes = @{
      NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
    };
    const CGFloat titleWidth =
        std::ceil([title sizeWithAttributes:attributes].width);
    const CGFloat tabWidth =
        std::min(std::max(titleWidth + leftPadding + rightReserved + 4.0, 150.0), 320.0);

    NSView* tabContainer =
        [[NSView alloc] initWithFrame:NSMakeRect(x, topInset, tabWidth, tabHeight)];
    [tabContainer setWantsLayer:YES];
    [[tabContainer layer] setCornerRadius:7.0];
    [[tabContainer layer] setBorderWidth:isSelected ? 1.0 : 0.0];
    [[tabContainer layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.78 alpha:1.0] CGColor]];
    [[tabContainer layer] setBackgroundColor:[(isSelected
                                               ? [NSColor colorWithCalibratedWhite:1.0 alpha:1.0]
                                               : [NSColor colorWithCalibratedWhite:0.90 alpha:1.0]) CGColor]];
    [tabBarView_ addSubview:tabContainer];

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

    x += tabWidth + 8.0f;
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
  [contentView addSubview:tabBarView_];

  NSBox* divider = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
  [divider setBoxType:NSBoxSeparator];
  [divider setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [tabBarView_ addSubview:divider];

  contentHostView_ = [[NSView alloc] initWithFrame:[contentView bounds]];
  [contentHostView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [contentHostView_ setWantsLayer:YES];
  [[contentHostView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
  [contentView addSubview:contentHostView_ positioned:NSWindowBelow relativeTo:tabBarView_];
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
    return;
  }

  [toolbarStrip_ setHidden:NO];
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
  NSURL* recentURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
  if (recentURL != nil) {
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:recentURL];
    [self rebuildOpenRecentMenu];
  }
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

- (IBAction)openRecentDocument:(id)sender {
  if (![sender isKindOfClass:[NSMenuItem class]]) {
    return;
  }

  NSURL* url = [(NSMenuItem*)sender representedObject];
  if (url == nil || ![url isFileURL]) {
    return;
  }

  [self openDocumentAtPath:[[url path] UTF8String] makeActive:YES];
}

- (IBAction)clearRecentDocuments:(id)sender {
  (void)sender;
  [[NSDocumentController sharedDocumentController] clearRecentDocuments:nil];
  [self rebuildOpenRecentMenu];
}

- (IBAction)closeCurrentTab:(id)sender {
  (void)sender;
  [self closeTabContext:[self activeTabContext]];
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
  return selectedTabContext_;
}

- (void)selectTabContext:(PDFTabContext*)context {
  if (context == nil) {
    selectedTabContext_ = nil;
    [window_ setTitle:@"pdfview"];
    [self layoutChrome];
    [self updateToolbarForActiveTab];
    return;
  }

  selectedTabContext_ = context;
  for (PDFTabContext* tabContext in tabContexts_) {
    [tabContext->containerView_ setHidden:tabContext != selectedTabContext_];
  }

  [window_ setTitle:[NSString stringWithFormat:@"pdfview - %@", [context tabTitle]]];
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
    [window_ setTitle:@"pdfview"];
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
                          [scaleContext setManualScale:std::min([self currentScaleForContext:scaleContext] * 1.25f, 5.0f)];
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
                          [scaleContext setManualScale:std::max([self currentScaleForContext:scaleContext] / 1.25f, 0.1f)];
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

- (void)tabClipViewDidScroll:(NSNotification*)notification {
  if (suppressScrollTracking_) {
    return;
  }
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
    return [[[NSDocumentController sharedDocumentController] recentDocumentURLs] count] > 0;
  }

  return YES;
}

@end
