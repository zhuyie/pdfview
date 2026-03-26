#pragma once

#import <AppKit/AppKit.h>

struct PDFChromeLayoutFrames {
  NSRect tab_bar_frame;
  NSRect content_frame;
  NSRect toolbar_frame;
  NSRect document_frame;
};

NSRect PDFViewInitialWindowFrame(void);
CGFloat PDFTabBarHeight(NSUInteger tab_count);
CGFloat PDFToolbarHeight(void);
NSTimeInterval PDFInteractiveRenderDebounceInterval(void);
PDFChromeLayoutFrames PDFComputeChromeLayoutFrames(NSRect content_bounds, NSUInteger tab_count);
