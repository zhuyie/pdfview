#import "mac/tab_context.h"

namespace {

}  // namespace

@implementation FlippedDocumentView

- (BOOL)isFlipped {
  return YES;
}

@end

@implementation PDFTabContext

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame {
  self = [super init];
  if (self != nil) {
    viewModel_ = pdfview::core::DocumentViewModel(document);
    documentPath_ = path;

    const int pageCount = viewModel_.page_count();
    pageImageViews_.resize(pageCount, nil);
    pageCache_.resize(pageCount);

    containerView_ = [[NSView alloc] initWithFrame:frame];
    [containerView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    scrollView_ = [[NSScrollView alloc] initWithFrame:frame];
    [scrollView_ setHasVerticalScroller:YES];
    [scrollView_ setHasHorizontalScroller:YES];
    [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scrollView_ setBorderType:NSNoBorder];
    [scrollView_ setBackgroundColor:[NSColor colorWithCalibratedWhite:0.92 alpha:1.0]];
    [[scrollView_ contentView] setPostsBoundsChangedNotifications:YES];

    documentView_ = [[FlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [documentView_ setWantsLayer:YES];
    [[documentView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
    pageViewHost_ = [[PDFPageViewHost alloc] initWithDocumentView:documentView_
                                                   pageImageViews:&pageImageViews_];
    [scrollView_ setDocumentView:documentView_];
    [containerView_ addSubview:scrollView_];
  }
  return self;
}

- (NSString*)tabTitle {
  NSString* path = [NSString stringWithUTF8String:documentPath_.c_str()];
  return [path lastPathComponent];
}

- (void)invalidateRenderedPages {
  pdfview::core::invalidate_page_cache(viewModel_.mutable_page_cache_states());
  for (size_t pageIndex = 0; pageIndex < pageCache_.size(); ++pageIndex) {
    pageCache_[pageIndex].image = nil;
    pageCache_[pageIndex].requestId = 0;
    [pageViewHost_ clearPageImageAtIndex:static_cast<int>(pageIndex)];
  }
  lastRenderPlanFingerprint_.valid = false;
}

- (BOOL)isRenderRequestCurrent:(int)pageIndex
                   renderScale:(float)renderScale
                     requestId:(long long)requestId {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return NO;
  }

  const PageRenderCacheEntry& cacheEntry = pageCache_[pageIndex];
  const pdfview::core::PageCacheSlotState& state = viewModel_.page_cache_states()[pageIndex];
  return cacheEntry.requestId == requestId && state.pending && state.render_scale == renderScale;
}

- (BOOL)hasPageImageAtIndex:(int)pageIndex {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return NO;
  }

  return pageCache_[pageIndex].image != nil;
}

- (BOOL)shouldSubmitRenderForPageIndex:(int)pageIndex renderScale:(float)renderScale {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return NO;
  }

  const pdfview::core::PageCacheSlotState& state = viewModel_.page_cache_states()[pageIndex];
  return pdfview::core::should_submit_page_render(state,
                                                  [self hasPageImageAtIndex:pageIndex],
                                                  renderScale);
}

- (void)markPageDiscarded:(int)pageIndex {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return;
  }

  pageCache_[pageIndex].image = nil;
  pageCache_[pageIndex].requestId = 0;
  pdfview::core::mark_page_cache_discarded(viewModel_.mutable_page_cache_states(), pageIndex);
}

- (void)markPageRendered:(int)pageIndex renderScale:(float)renderScale {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return;
  }

  pageCache_[pageIndex].requestId = 0;
  pdfview::core::mark_page_cache_rendered(viewModel_.mutable_page_cache_states(),
                                          pageIndex,
                                          renderScale);
}

- (void)markPageRequested:(int)pageIndex renderScale:(float)renderScale requestId:(long long)requestId {
  if (pageIndex < 0 || pageIndex >= static_cast<int>(pageCache_.size())) {
    return;
  }

  pageCache_[pageIndex].requestId = requestId;
  pdfview::core::mark_page_cache_requested(viewModel_.mutable_page_cache_states(),
                                           pageIndex,
                                           renderScale);
}

- (void)setManualScale:(float)scale {
  viewModel_.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::Manual;
  viewModel_.mutable_view_state()->zoom = scale;
}

- (void)setScaleMode:(pdfview::core::ScaleMode)scaleMode {
  viewModel_.mutable_view_state()->scale_mode = scaleMode;
}

- (float)currentScale {
  return viewModel_.current_logical_scale();
}

- (void)syncPageFrames {
  [pageViewHost_ syncPageFrames:viewModel_.page_frames()];
}

- (void)clearPageImageAtIndex:(int)pageIndex {
  [pageViewHost_ clearPageImageAtIndex:pageIndex];
}

- (void)applyPageImage:(NSImage*)image atIndex:(int)pageIndex {
  [pageViewHost_ applyPageImage:image atIndex:pageIndex];
}

- (BOOL)shouldSkipVisibleUpdateForCachePlan:(const pdfview::core::PageCachePlan&)cachePlan
                                renderScale:(float)renderScale {
  return pdfview::core::render_plan_matches_fingerprint(lastRenderPlanFingerprint_,
                                                        cachePlan,
                                                        renderScale);
}

- (void)rememberVisibleUpdateForCachePlan:(const pdfview::core::PageCachePlan&)cachePlan
                              renderScale:(float)renderScale {
  lastRenderPlanFingerprint_ =
      pdfview::core::render_plan_fingerprint_for_visible_update(cachePlan, renderScale);
}

@end
