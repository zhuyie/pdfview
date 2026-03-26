#import "mac/tab_strip_view.h"

#include <algorithm>
#include <vector>

namespace {

constexpr CGFloat kTabHeight = 26.0f;
constexpr CGFloat kTopInset = 4.0f;
constexpr CGFloat kTabGap = 8.0f;
constexpr CGFloat kLeadingInset = 10.0f;
constexpr CGFloat kTrailingInset = 10.0f;
constexpr CGFloat kLeftPadding = 12.0f;
constexpr CGFloat kCloseButtonSize = 22.0f;
constexpr CGFloat kCloseRightInset = 8.0f;
constexpr CGFloat kTitleToCloseGap = 8.0f;
constexpr CGFloat kRightReserved = kCloseButtonSize + kCloseRightInset + kTitleToCloseGap;
constexpr CGFloat kScrollButtonWidth = 22.0f;
constexpr CGFloat kScrollButtonGap = 6.0f;
constexpr CGFloat kScrollButtonsLeftGap = 10.0f;
constexpr CGFloat kFadeWidth = 32.0f;

}  // namespace

@interface PassiveTabTextField : NSTextField
@end

@implementation PassiveTabTextField

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

@interface PDFTabStripView ()

- (void)rebuildTabs;
- (void)computeMetrics:(std::vector<CGFloat>*)tabWidths
            totalWidth:(CGFloat*)totalTabWidth
            trackWidth:(CGFloat*)trackWidth
     visibleTrackWidth:(CGFloat*)visibleTrackWidth
             maxOffset:(CGFloat*)maxOffset
    needsScrollButtons:(BOOL*)needsScrollButtons;
- (CGFloat)offsetByStepping:(NSInteger)direction;
- (IBAction)scrollLeft:(id)sender;
- (IBAction)scrollRight:(id)sender;
- (IBAction)selectTab:(id)sender;
- (IBAction)closeTab:(id)sender;

@end

@implementation PDFTabStripView {
  id<PDFTabStripViewDelegate> delegate_;
  NSView* tabContentView_;
  NSView* fadeView_;
  NSButton* leftButton_;
  NSButton* rightButton_;
  NSArray<NSString*>* tabTitles_;
  NSInteger selectedIndex_;
  CGFloat scrollOffset_;
  BOOL shouldEnsureSelectedVisible_;
}

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFTabStripViewDelegate>)delegate {
  self = [super initWithFrame:frame];
  if (self != nil) {
    delegate_ = delegate;
    tabTitles_ = @[];
    selectedIndex_ = NSNotFound;
    scrollOffset_ = 0.0f;
    shouldEnsureSelectedVisible_ = YES;

    [self setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self setWantsLayer:YES];
    [[self layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.94 alpha:1.0] CGColor]];
    [[self layer] setMasksToBounds:YES];

    tabContentView_ = [[NSView alloc] initWithFrame:[self bounds]];
    [tabContentView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [tabContentView_ setWantsLayer:YES];
    [[tabContentView_ layer] setMasksToBounds:YES];
    [self addSubview:tabContentView_];

    fadeView_ = [[EdgeFadeView alloc] initWithLeadingEdge:NO];
    [fadeView_ setFrame:NSMakeRect(0, 0, kFadeWidth, 34)];
    [fadeView_ setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [fadeView_ setHidden:YES];
    [self addSubview:fadeView_ positioned:NSWindowAbove relativeTo:tabContentView_];

    NSBox* divider = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
    [divider setBoxType:NSBoxSeparator];
    [divider setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:divider positioned:NSWindowAbove relativeTo:tabContentView_];

    rightButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kScrollButtonWidth, 22)];
    [rightButton_ setTitle:@"›"];
    [rightButton_ setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
    [rightButton_ setBezelStyle:NSBezelStyleTexturedRounded];
    [rightButton_ setTarget:self];
    [rightButton_ setAction:@selector(scrollRight:)];
    [rightButton_ setHidden:YES];
    [self addSubview:rightButton_];

    leftButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kScrollButtonWidth, 22)];
    [leftButton_ setTitle:@"‹"];
    [leftButton_ setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
    [leftButton_ setBezelStyle:NSBezelStyleTexturedRounded];
    [leftButton_ setTarget:self];
    [leftButton_ setAction:@selector(scrollLeft:)];
    [leftButton_ setHidden:YES];
    [self addSubview:leftButton_];
  }
  return self;
}

- (void)setFrame:(NSRect)frame {
  [super setFrame:frame];
  [self rebuildTabs];
}

- (void)setTabTitles:(NSArray<NSString*>*)tabTitles selectedIndex:(NSInteger)selectedIndex {
  tabTitles_ = [tabTitles copy];
  selectedIndex_ = selectedIndex;
  [self rebuildTabs];
}

- (void)ensureSelectedTabVisibleOnNextLayout {
  shouldEnsureSelectedVisible_ = YES;
}

- (void)computeMetrics:(std::vector<CGFloat>*)tabWidths
            totalWidth:(CGFloat*)totalTabWidth
            trackWidth:(CGFloat*)trackWidth
     visibleTrackWidth:(CGFloat*)visibleTrackWidth
             maxOffset:(CGFloat*)maxOffset
    needsScrollButtons:(BOOL*)needsScrollButtons {
  if (tabWidths != nullptr) {
    tabWidths->clear();
    tabWidths->reserve([tabTitles_ count]);
  }
  CGFloat computedTotalWidth = 0.0f;
  for (NSString* title in tabTitles_) {
    NSDictionary* attributes = @{
      NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
    };
    const CGFloat titleWidth = std::ceil([title sizeWithAttributes:attributes].width);
    const CGFloat tabWidth =
        std::min(std::max(titleWidth + kLeftPadding + kRightReserved + 4.0, 150.0), 320.0);
    if (tabWidths != nullptr) {
      tabWidths->push_back(tabWidth);
    }
    computedTotalWidth += tabWidth;
  }
  if ([tabTitles_ count] > 1) {
    computedTotalWidth += kTabGap * ([tabTitles_ count] - 1);
  }

  const CGFloat fullTrackWidth =
      std::max(NSWidth([self bounds]) - kLeadingInset - kTrailingInset, 0.0);
  const BOOL shouldShowScrollButtons = computedTotalWidth > fullTrackWidth;
  const CGFloat buttonAreaWidth =
      shouldShowScrollButtons
          ? (kScrollButtonWidth * 2.0f + kScrollButtonGap + kScrollButtonsLeftGap)
          : 0.0f;
  const CGFloat computedTrackWidth = std::max(fullTrackWidth - buttonAreaWidth, 0.0);
  const CGFloat computedVisibleTrackWidth =
      std::max(computedTrackWidth - (shouldShowScrollButtons ? kFadeWidth : 0.0f), 0.0);
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

- (CGFloat)offsetByStepping:(NSInteger)direction {
  std::vector<CGFloat> tabWidths;
  CGFloat totalTabWidth = 0.0f;
  CGFloat trackWidth = 0.0f;
  CGFloat visibleTrackWidth = 0.0f;
  CGFloat maxOffset = 0.0f;
  BOOL needsScrollButtons = NO;
  [self computeMetrics:&tabWidths
            totalWidth:&totalTabWidth
            trackWidth:&trackWidth
     visibleTrackWidth:&visibleTrackWidth
             maxOffset:&maxOffset
    needsScrollButtons:&needsScrollButtons];
  (void)totalTabWidth;
  (void)trackWidth;

  if (!needsScrollButtons || tabWidths.empty()) {
    return 0.0f;
  }

  const CGFloat currentOffset = std::min(std::max(scrollOffset_, 0.0), maxOffset);
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
      x = tabEnd + kTabGap;
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
    x = tabEnd + kTabGap;
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
    x = tabEnd + kTabGap;
  }
  return 0.0f;
}

- (void)rebuildTabs {
  NSArray<NSView*>* tabSubviews = [[tabContentView_ subviews] copy];
  for (NSView* subview in tabSubviews) {
    [subview removeFromSuperview];
  }

  if ([tabTitles_ count] == 0) {
    scrollOffset_ = 0.0f;
    [leftButton_ setHidden:YES];
    [rightButton_ setHidden:YES];
    [fadeView_ setHidden:YES];
    return;
  }

  std::vector<CGFloat> tabWidths;
  CGFloat totalTabWidth = 0.0f;
  CGFloat trackWidth = 0.0f;
  CGFloat visibleTrackWidth = 0.0f;
  CGFloat maxOffset = 0.0f;
  BOOL needsScrollButtons = NO;
  [self computeMetrics:&tabWidths
            totalWidth:&totalTabWidth
            trackWidth:&trackWidth
     visibleTrackWidth:&visibleTrackWidth
             maxOffset:&maxOffset
    needsScrollButtons:&needsScrollButtons];
  scrollOffset_ = std::min(std::max(scrollOffset_, 0.0), maxOffset);

  if (shouldEnsureSelectedVisible_ &&
      selectedIndex_ != NSNotFound &&
      selectedIndex_ >= 0 &&
      selectedIndex_ < static_cast<NSInteger>(tabWidths.size())) {
    CGFloat selectedMinX = 0.0f;
    for (NSInteger index = 0; index < selectedIndex_; ++index) {
      selectedMinX += tabWidths[index] + kTabGap;
    }
    const CGFloat selectedMaxX = selectedMinX + tabWidths[selectedIndex_];
    if (selectedMinX < scrollOffset_) {
      scrollOffset_ = selectedMinX;
    } else if (selectedMaxX > scrollOffset_ + visibleTrackWidth) {
      scrollOffset_ = selectedMaxX - visibleTrackWidth;
    }
    scrollOffset_ = std::min(std::max(scrollOffset_, 0.0), maxOffset);
  }
  shouldEnsureSelectedVisible_ = NO;

  [leftButton_ setHidden:!needsScrollButtons];
  [rightButton_ setHidden:!needsScrollButtons];
  [tabContentView_ setFrame:NSMakeRect(kLeadingInset, 0.0f, trackWidth, NSHeight([self bounds]))];
  const BOOL hasClippedTabsBehindFade =
      needsScrollButtons && (scrollOffset_ < maxOffset - 0.5f);
  [fadeView_ setFrame:NSMakeRect(kLeadingInset + trackWidth - kFadeWidth,
                                 1.0f,
                                 kFadeWidth,
                                 NSHeight([self bounds]) - 1.0f)];
  [fadeView_ setHidden:!hasClippedTabsBehindFade];

  if (needsScrollButtons) {
    const CGFloat buttonY = 6.0f;
    const CGFloat rightButtonX = NSWidth([self bounds]) - kTrailingInset - kScrollButtonWidth;
    const CGFloat leftButtonX = rightButtonX - kScrollButtonGap - kScrollButtonWidth;
    [leftButton_ setFrame:NSMakeRect(leftButtonX, buttonY, kScrollButtonWidth, 22.0f)];
    [rightButton_ setFrame:NSMakeRect(rightButtonX, buttonY, kScrollButtonWidth, 22.0f)];
    [leftButton_ setEnabled:scrollOffset_ > 0.5f];
    [rightButton_ setEnabled:scrollOffset_ + visibleTrackWidth < totalTabWidth - 0.5f];
  }

  CGFloat x = -scrollOffset_;
  for (NSInteger tabIndex = 0; tabIndex < static_cast<NSInteger>(tabWidths.size()); ++tabIndex) {
    const BOOL isSelected = tabIndex == selectedIndex_;
    const CGFloat tabWidth = tabWidths[tabIndex];
    NSString* title = [tabTitles_ objectAtIndex:tabIndex];

    if (x + tabWidth < -kTabGap) {
      x += tabWidth + kTabGap;
      continue;
    }
    if (x > trackWidth + kTabGap) {
      break;
    }

    NSView* tabContainer =
        [[NSView alloc] initWithFrame:NSMakeRect(x, kTopInset, tabWidth, kTabHeight)];
    [tabContainer setWantsLayer:YES];
    [[tabContainer layer] setCornerRadius:7.0];
    [[tabContainer layer] setBorderWidth:isSelected ? 1.0 : 0.0];
    [[tabContainer layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.78 alpha:1.0] CGColor]];
    [[tabContainer layer] setBackgroundColor:[(isSelected
                                               ? [NSColor colorWithCalibratedWhite:1.0 alpha:1.0]
                                               : [NSColor colorWithCalibratedWhite:0.90 alpha:1.0]) CGColor]];
    [tabContentView_ addSubview:tabContainer];

    const CGFloat labelHeight = 17.0f;
    const CGFloat labelY = std::floor((kTabHeight - labelHeight) * 0.5f) - 1.0f;
    PassiveTabTextField* titleLabel =
        [[PassiveTabTextField alloc] initWithFrame:NSMakeRect(kLeftPadding,
                                                              labelY,
                                                              tabWidth - kLeftPadding - kRightReserved,
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

    NSButton* selectButton = [[NSButton alloc] initWithFrame:[tabContainer bounds]];
    [selectButton setTitle:@""];
    [selectButton setBezelStyle:NSBezelStyleRegularSquare];
    [selectButton setButtonType:NSButtonTypeMomentaryPushIn];
    [selectButton setBordered:NO];
    [selectButton setTransparent:YES];
    [selectButton setTarget:self];
    [selectButton setAction:@selector(selectTab:)];
    [selectButton setTag:tabIndex];
    [tabContainer addSubview:selectButton positioned:NSWindowBelow relativeTo:titleLabel];

    NSButton* closeButton =
        [[NSButton alloc] initWithFrame:NSMakeRect(tabWidth - kCloseRightInset - kCloseButtonSize,
                                                   2.0f,
                                                   kCloseButtonSize,
                                                   kCloseButtonSize)];
    [closeButton setTitle:@"×"];
    [closeButton setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
    [closeButton setBezelStyle:NSBezelStyleRegularSquare];
    [closeButton setBordered:NO];
    [closeButton setContentTintColor:(isSelected
                                      ? [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]
                                      : [NSColor colorWithCalibratedWhite:0.45 alpha:1.0])];
    [closeButton setTarget:self];
    [closeButton setAction:@selector(closeTab:)];
    [closeButton setTag:tabIndex];
    [tabContainer addSubview:closeButton];

    x += tabWidth + kTabGap;
  }

  if (needsScrollButtons) {
    [self addSubview:fadeView_ positioned:NSWindowAbove relativeTo:nil];
    [self addSubview:leftButton_ positioned:NSWindowAbove relativeTo:nil];
    [self addSubview:rightButton_ positioned:NSWindowAbove relativeTo:nil];
  }
}

- (IBAction)scrollLeft:(id)sender {
  (void)sender;
  scrollOffset_ = [self offsetByStepping:-1];
  shouldEnsureSelectedVisible_ = NO;
  [self rebuildTabs];
}

- (IBAction)scrollRight:(id)sender {
  (void)sender;
  scrollOffset_ = [self offsetByStepping:1];
  shouldEnsureSelectedVisible_ = NO;
  [self rebuildTabs];
}

- (IBAction)selectTab:(id)sender {
  if ([sender isKindOfClass:[NSButton class]] && delegate_ != nil) {
    [delegate_ tabStripViewDidSelectTabAtIndex:[(NSButton*)sender tag]];
  }
}

- (IBAction)closeTab:(id)sender {
  if ([sender isKindOfClass:[NSButton class]] && delegate_ != nil) {
    [delegate_ tabStripViewDidCloseTabAtIndex:[(NSButton*)sender tag]];
  }
}

@end
