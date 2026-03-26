#import "mac/document_interaction_controller.h"

#import "mac/chrome_metrics.h"
#import "mac/page_indicator_view.h"

@interface PDFDocumentInteractionController ()

- (void)endInteractiveRendering:(NSTimer*)timer;
- (void)hidePageIndicatorTimerFired:(NSTimer*)timer;
- (void)ensurePageIndicatorAttachedToContext:(PDFTabContext*)context;

@end

@implementation PDFDocumentInteractionController {
  id<PDFDocumentInteractionControllerDelegate> delegate_;
  PDFPageIndicatorView* pageIndicatorView_;
  NSTimer* interactiveRenderTimer_;
  NSTimer* pageIndicatorTimer_;
  PDFTabContext* interactiveRenderContext_;
}

- (instancetype)initWithDelegate:(id<PDFDocumentInteractionControllerDelegate>)delegate {
  self = [super init];
  if (self != nil) {
    delegate_ = delegate;
    pageIndicatorView_ = nil;
    interactiveRenderTimer_ = nil;
    pageIndicatorTimer_ = nil;
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
