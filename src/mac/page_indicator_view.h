#pragma once

#import <AppKit/AppKit.h>

@interface PDFPageIndicatorView : NSView

- (void)updateWithText:(NSString*)text
       containerBounds:(NSRect)containerBounds
  hasHorizontalScroller:(BOOL)hasHorizontalScroller;

@end
