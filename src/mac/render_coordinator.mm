#import "mac/render_coordinator.h"

#include <algorithm>
#include <chrono>

#include "core/profiling.h"
#include "mac/image_bridge.h"

namespace {

double MillisecondsSince(const std::chrono::steady_clock::time_point& start) {
  return std::chrono::duration_cast<std::chrono::duration<double, std::milli> >(
             std::chrono::steady_clock::now() - start)
      .count();
}

}  // namespace

@interface PDFRenderCoordinator ()
- (void)applyRenderedPage:(const pdfview::core::RenderPageResult&)renderResult
               forRequest:(const pdfview::core::PageRenderRequest&)request
                requestId:(long long)requestId
                  context:(PDFTabContext*)context
                   pdfMs:(double)pdfMilliseconds;
@end

@implementation PDFRenderCoordinator {
  id<PDFRenderCoordinatorDelegate> delegate_;
  dispatch_queue_t renderQueue_;
  long long nextRenderRequestId_;
}

- (instancetype)initWithDelegate:(id<PDFRenderCoordinatorDelegate>)delegate {
  self = [super init];
  if (self != nil) {
    delegate_ = delegate;
    renderQueue_ = dispatch_queue_create("com.pdfview.render", DISPATCH_QUEUE_SERIAL);
    nextRenderRequestId_ = 1;
  }
  return self;
}

- (void)updateVisiblePagesForContext:(PDFTabContext*)context
                            isActive:(BOOL)isActive
                         deviceScale:(CGFloat)deviceScale {
  if (context == nil || context->viewModel_.page_frames().empty() || !isActive) {
    return;
  }

  const std::chrono::steady_clock::time_point passStart = std::chrono::steady_clock::now();
  double imageApplyMilliseconds = 0.0;
  int submittedPageCount = 0;
  int discardedPageCount = 0;
  int keptPageCount = 0;
  long long submittedPixelCount = 0;

  [context setScrollOrigin:[[context->scrollView_ contentView] bounds].origin];
  context->viewModel_.set_device_scale(static_cast<float>(deviceScale));
  const pdfview::core::PageCachePlan cachePlan =
      context->viewModel_.page_cache_plan(context->viewModel_.visible_rect().height * 0.5f);
  const pdfview::core::PageRenderPlan renderPlan = context->viewModel_.page_render_plan();

  for (size_t discardIndex = 0; discardIndex < renderPlan.pages_to_discard.size(); ++discardIndex) {
    const int pageIndex = renderPlan.pages_to_discard[discardIndex];
    const std::chrono::steady_clock::time_point applyStart = std::chrono::steady_clock::now();
    [context markPageDiscarded:pageIndex];
    [context clearPageImageAtIndex:pageIndex];
    imageApplyMilliseconds += MillisecondsSince(applyStart);
    discardedPageCount += 1;
  }

  for (size_t renderIndex = 0; renderIndex < renderPlan.render_requests.size(); ++renderIndex) {
    const pdfview::core::PageRenderRequest& request = renderPlan.render_requests[renderIndex];
    const int pageIndex = request.page_index;
    NSImageView* imageView = context->pageImageViews_[pageIndex];
    if (imageView == nil) {
      continue;
    }

    const long long requestId = nextRenderRequestId_++;
    [context markPageRequested:pageIndex renderScale:request.render_scale requestId:requestId];
    const pdfview::core::DocumentPtr document = context->viewModel_.document();
    PDFTabContext* retainedContext = context;
    const pdfview::core::PageRenderRequest requestCopy = request;
    dispatch_async(renderQueue_, ^{
      __block BOOL shouldRender = NO;
      dispatch_sync(dispatch_get_main_queue(), ^{
        shouldRender = [retainedContext isRenderRequestCurrent:requestCopy.page_index
                                                   renderScale:requestCopy.render_scale
                                                     requestId:requestId];
      });
      if (!shouldRender) {
        if (pdfview::core::render_profiling_enabled()) {
          pdfview::core::render_log("[pdfview] page_skip page=%d scale=%.3f request=%lld reason=stale_before_render",
                                    requestCopy.page_index,
                                    requestCopy.render_scale,
                                    requestId);
        }
        return;
      }

      const std::chrono::steady_clock::time_point pdfRenderStart = std::chrono::steady_clock::now();
      const pdfview::core::RenderPageResult renderResult =
          document->render_page(requestCopy.page_index, requestCopy.render_scale);
      const double pdfMilliseconds = MillisecondsSince(pdfRenderStart);
      dispatch_async(dispatch_get_main_queue(), ^{
        [self applyRenderedPage:renderResult
                     forRequest:requestCopy
                      requestId:requestId
                        context:retainedContext
                         pdfMs:pdfMilliseconds];
      });
    });

    submittedPageCount += 1;
    submittedPixelCount +=
        static_cast<long long>(request.display_width) * static_cast<long long>(request.display_height);
  }

  for (int pageIndex = renderPlan.keep_range.start; pageIndex < renderPlan.keep_range.end; ++pageIndex) {
    if (context->pageCache_[pageIndex].image != nil) {
      const std::chrono::steady_clock::time_point applyStart = std::chrono::steady_clock::now();
      [context applyPageImage:context->pageCache_[pageIndex].image atIndex:pageIndex];
      imageApplyMilliseconds += MillisecondsSince(applyStart);
      keptPageCount += 1;
    }
  }

  if (pdfview::core::render_profiling_enabled()) {
    const double totalMilliseconds = MillisecondsSince(passStart);
    pdfview::core::render_log("[pdfview] visible_update total_ms=%.2f image_apply_ms=%.2f submitted=%d "
                              "discarded=%d kept=%d submit_pixels=%lld visible=%d..%d preload=%d..%d keep=%d..%d",
                              totalMilliseconds,
                              imageApplyMilliseconds,
                              submittedPageCount,
                              discardedPageCount,
                              keptPageCount,
                              submittedPixelCount,
                              cachePlan.visible_range.start,
                              cachePlan.visible_range.end,
                              cachePlan.preload_range.start,
                              cachePlan.preload_range.end,
                              renderPlan.keep_range.start,
                              renderPlan.keep_range.end);
  }
}

- (void)applyRenderedPage:(const pdfview::core::RenderPageResult&)renderResult
               forRequest:(const pdfview::core::PageRenderRequest&)request
                requestId:(long long)requestId
                  context:(PDFTabContext*)context
                   pdfMs:(double)pdfMilliseconds {
  if (context == nil ||
      request.page_index < 0 ||
      request.page_index >= static_cast<int>(context->pageCache_.size())) {
    return;
  }

  PageRenderCacheEntry& cacheEntry = context->pageCache_[request.page_index];
  if (cacheEntry.requestId != requestId) {
    return;
  }

  if (!renderResult.ok()) {
    [context markPageDiscarded:request.page_index];
    [delegate_ presentError:[NSString stringWithFormat:@"Failed to render page %d: %s",
                                                       request.page_index + 1,
                                                       renderResult.error.c_str()]];
    return;
  }

  const std::chrono::steady_clock::time_point imageDecodeStart = std::chrono::steady_clock::now();
  cacheEntry.image =
      PDFViewImageFromBitmap(renderResult.bitmap,
                             NSMakeSize(request.display_width, request.display_height));
  const double imageDecodeMilliseconds = MillisecondsSince(imageDecodeStart);

  double imageApplyMilliseconds = 0.0;
  const std::chrono::steady_clock::time_point imageApplyStart = std::chrono::steady_clock::now();
  [context applyPageImage:cacheEntry.image atIndex:request.page_index];
  imageApplyMilliseconds = MillisecondsSince(imageApplyStart);

  [context markPageRendered:request.page_index renderScale:request.render_scale];

  if (pdfview::core::render_profiling_enabled()) {
    pdfview::core::render_log("[pdfview] page_render page=%d scale=%.3f pdf_ms=%.2f decode_ms=%.2f apply_ms=%.2f pixels=%d",
                              request.page_index,
                              request.render_scale,
                              pdfMilliseconds,
                              imageDecodeMilliseconds,
                              imageApplyMilliseconds,
                              renderResult.bitmap.width * renderResult.bitmap.height);
  }
}

@end
