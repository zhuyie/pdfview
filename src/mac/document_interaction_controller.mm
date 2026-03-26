#import "mac/document_interaction_controller.h"

#include <algorithm>

#import "mac/chrome_metrics.h"
#import "mac/page_indicator_view.h"

namespace {

constexpr CGFloat kSelectionAutoScrollEdgeInset = 36.0;
constexpr CGFloat kSelectionAutoScrollMaxStep = 28.0;
constexpr NSTimeInterval kSelectionAutoScrollTickInterval = 1.0 / 60.0;

}  // namespace

@interface PDFDocumentInteractionController ()

- (void)endInteractiveRendering:(NSTimer*)timer;
- (void)hidePageIndicatorTimerFired:(NSTimer*)timer;
- (void)ensurePageIndicatorAttachedToContext:(PDFTabContext*)context;
- (void)handleSelectionAutoScrollTick:(NSTimer*)timer;
- (void)startSelectionAutoScrollForContext:(PDFTabContext*)context;

@end

@implementation PDFDocumentInteractionController {
  id<PDFDocumentInteractionControllerDelegate> delegate_;
  PDFPageIndicatorView* pageIndicatorView_;
  NSTimer* interactiveRenderTimer_;
  NSTimer* pageIndicatorTimer_;
  NSTimer* selectionAutoScrollTimer_;
  PDFTabContext* selectionAutoScrollContext_;
  NSPoint selectionAutoScrollDocumentLocation_;
  PDFTabContext* interactiveRenderContext_;
}

- (instancetype)initWithDelegate:(id<PDFDocumentInteractionControllerDelegate>)delegate {
  self = [super init];
  if (self != nil) {
    delegate_ = delegate;
    pageIndicatorView_ = nil;
    interactiveRenderTimer_ = nil;
    pageIndicatorTimer_ = nil;
    selectionAutoScrollTimer_ = nil;
    selectionAutoScrollContext_ = nil;
    selectionAutoScrollDocumentLocation_ = NSZeroPoint;
    interactiveRenderContext_ = nil;
  }
  return self;
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
      [NSTimer scheduledTimerWithTimeInterval:PDFInteractiveRenderDebounceInterval()
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
  if (delegate_ != nil &&
      [delegate_ documentInteractionControllerIsContextActive:context]) {
    [delegate_ documentInteractionControllerUpdateVisiblePagesForContext:context];
  }
}

- (void)cancelInteractiveRendering {
  if (interactiveRenderTimer_ != nil) {
    [interactiveRenderTimer_ invalidate];
    interactiveRenderTimer_ = nil;
  }
  interactiveRenderContext_ = nil;
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
    [context->containerView_ addSubview:pageIndicatorView_
                             positioned:NSWindowAbove
                             relativeTo:context->scrollView_];
  }
}

- (void)showPageIndicatorForContext:(PDFTabContext*)context {
  if (context == nil ||
      delegate_ == nil ||
      ![delegate_ documentInteractionControllerIsContextActive:context] ||
      context->viewModel_.page_count() <= 0) {
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
                                     selector:@selector(hidePageIndicatorTimerFired:)
                                     userInfo:nil
                                      repeats:NO];
  [[NSRunLoop mainRunLoop] addTimer:pageIndicatorTimer_ forMode:NSRunLoopCommonModes];
}

- (void)hidePageIndicatorTimerFired:(NSTimer*)timer {
  if (timer != pageIndicatorTimer_) {
    return;
  }
  [self hidePageIndicator];
}

- (void)hidePageIndicator {
  if (pageIndicatorTimer_ != nil) {
    [pageIndicatorTimer_ invalidate];
    pageIndicatorTimer_ = nil;
  }
  [pageIndicatorView_ setHidden:YES];
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
  const CGFloat distanceToBottom = NSMaxY(visibleBounds) - documentLocation.y;
  const BOOL nearTop = distanceToTop < kSelectionAutoScrollEdgeInset;
  const BOOL nearBottom = distanceToBottom < kSelectionAutoScrollEdgeInset;
  if (!nearTop && !nearBottom) {
    [self stopSelectionAutoScroll];
    return;
  }

  [self startSelectionAutoScrollForContext:context];
}

- (void)handleSelectionAutoScrollTick:(NSTimer*)timer {
  if (timer != selectionAutoScrollTimer_ || selectionAutoScrollContext_ == nil || delegate_ == nil) {
    return;
  }

  PDFTabContext* context = selectionAutoScrollContext_;
  NSClipView* clipView = [context->scrollView_ contentView];
  const NSRect visibleBounds = [clipView bounds];
  const CGFloat distanceToTop = selectionAutoScrollDocumentLocation_.y - visibleBounds.origin.y;
  const CGFloat distanceToBottom = NSMaxY(visibleBounds) - selectionAutoScrollDocumentLocation_.y;

  CGFloat scrollDelta = 0.0;
  if (distanceToTop < kSelectionAutoScrollEdgeInset) {
    const CGFloat intensity =
        std::max((kSelectionAutoScrollEdgeInset - distanceToTop) / kSelectionAutoScrollEdgeInset,
                 0.0);
    scrollDelta = -std::max(intensity * kSelectionAutoScrollMaxStep, 1.0);
  } else if (distanceToBottom < kSelectionAutoScrollEdgeInset) {
    const CGFloat intensity =
        std::max((kSelectionAutoScrollEdgeInset - distanceToBottom) / kSelectionAutoScrollEdgeInset,
                 0.0);
    scrollDelta = std::max(intensity * kSelectionAutoScrollMaxStep, 1.0);
  } else {
    [self stopSelectionAutoScroll];
    return;
  }

  if (![delegate_ documentInteractionControllerPerformSelectionAutoScrollForContext:context
                                                                             deltaY:scrollDelta]) {
    return;
  }

  NSWindow* window = [context->documentView_ window];
  const NSPoint windowLocation = [window mouseLocationOutsideOfEventStream];
  const NSPoint documentLocation = [context->documentView_ convertPoint:windowLocation fromView:nil];
  selectionAutoScrollDocumentLocation_ = documentLocation;
  [delegate_ documentInteractionControllerUpdateTextSelectionAtDocumentLocation:documentLocation
                                                                        context:context];
}

- (void)handleClipViewDidScrollForContext:(PDFTabContext*)context
                    suppressScrollTracking:(BOOL)suppressScrollTracking {
  if (suppressScrollTracking || context == nil || delegate_ == nil) {
    return;
  }

  [delegate_ documentInteractionControllerUpdateCurrentPageFromScrollForContext:context];
  [self showPageIndicatorForContext:context];
  [self beginInteractiveRenderingForContext:context];
  [delegate_ documentInteractionControllerUpdateVisiblePagesForContext:context];
}

@end
