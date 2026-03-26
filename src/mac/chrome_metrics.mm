#import "mac/chrome_metrics.h"

#include <algorithm>

namespace {

constexpr CGFloat kInitialWindowWidth = 1080.0;
constexpr CGFloat kInitialWindowHeight = 800.0;
constexpr CGFloat kTabBarHeight = 34.0;
constexpr CGFloat kToolbarHeight = 32.0;
constexpr NSTimeInterval kInteractiveRenderDebounceInterval = 0.12;

}  // namespace

NSRect PDFViewInitialWindowFrame(void) {
  return NSMakeRect(0, 0, kInitialWindowWidth, kInitialWindowHeight);
}

CGFloat PDFTabBarHeight(NSUInteger tab_count) {
  return tab_count > 0 ? kTabBarHeight : 0.0;
}

CGFloat PDFToolbarHeight(void) {
  return kToolbarHeight;
}

NSTimeInterval PDFInteractiveRenderDebounceInterval(void) {
  return kInteractiveRenderDebounceInterval;
}

PDFChromeLayoutFrames PDFComputeChromeLayoutFrames(NSRect content_bounds, NSUInteger tab_count) {
  PDFChromeLayoutFrames frames;
  const CGFloat tab_bar_height = PDFTabBarHeight(tab_count);
  const CGFloat toolbar_height = PDFToolbarHeight();

  frames.tab_bar_frame = NSMakeRect(0,
                                    NSHeight(content_bounds) - tab_bar_height,
                                    NSWidth(content_bounds),
                                    tab_bar_height);
  frames.content_frame = NSMakeRect(0,
                                    0,
                                    NSWidth(content_bounds),
                                    std::max(NSHeight(content_bounds) - tab_bar_height, 0.0));
  frames.toolbar_frame = NSMakeRect(0,
                                    NSHeight(frames.content_frame) - toolbar_height,
                                    NSWidth(frames.content_frame),
                                    toolbar_height);
  frames.document_frame = NSMakeRect(0,
                                     0,
                                     NSWidth(frames.content_frame),
                                     std::max(NSHeight(frames.content_frame) - toolbar_height, 0.0));
  return frames;
}
