#import "mac/page_indicator_view.h"

#include <algorithm>
#include <cmath>

@interface PassivePageIndicatorLabel : NSTextField
@end

@implementation PassivePageIndicatorLabel

- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

@end

@implementation PDFPageIndicatorView {
  PassivePageIndicatorLabel* label_;
}

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self != nil) {
    [self setWantsLayer:YES];
    [[self layer] setCornerRadius:8.0f];
    [[self layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.10 alpha:0.78] CGColor]];
    [self setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [self setHidden:YES];

    label_ = [[PassivePageIndicatorLabel alloc] initWithFrame:NSMakeRect(12, 6, 48, 18)];
    [label_ setEditable:NO];
    [label_ setBezeled:NO];
    [label_ setBordered:NO];
    [label_ setDrawsBackground:NO];
    [label_ setSelectable:NO];
    [label_ setAlignment:NSTextAlignmentCenter];
    [label_ setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]];
    [label_ setTextColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.96]];
    [label_ setUsesSingleLineMode:YES];
    [[label_ cell] setWraps:NO];
    [[label_ cell] setLineBreakMode:NSLineBreakByClipping];
    [self addSubview:label_];
  }
  return self;
}

- (void)updateWithText:(NSString*)text
       containerBounds:(NSRect)containerBounds
  hasHorizontalScroller:(BOOL)hasHorizontalScroller {
  [label_ setStringValue:text];

  NSDictionary* attributes = @{
    NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]
  };
  const CGFloat textWidth = std::ceil([text sizeWithAttributes:attributes].width);
  const CGFloat indicatorWidth = std::max(static_cast<CGFloat>(88.0), textWidth + 24.0f);
  const CGFloat indicatorHeight = 30.0f;
  const CGFloat rightMargin = 30.0f;
  const CGFloat bottomMargin = hasHorizontalScroller ? 24.0f : 16.0f;

  [self setFrame:NSMakeRect(containerBounds.size.width - indicatorWidth - rightMargin,
                            bottomMargin,
                            indicatorWidth,
                            indicatorHeight)];
  [label_ setFrame:NSMakeRect(12.0f,
                              6.0f,
                              indicatorWidth - 24.0f,
                              18.0f)];
}

@end
