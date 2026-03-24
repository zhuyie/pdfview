#import "mac/tab_context.h"

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
    lastRenderScale_ = 0.0f;

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
    if (pageImageViews_[pageIndex] != nil) {
      [pageImageViews_[pageIndex] setImage:nil];
    }
  }
  lastRenderScale_ = 0.0f;
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
  lastRenderScale_ = renderScale;
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
  viewModel_.mutable_view_state()->zoom = scale;
}

- (void)setUseFitScale:(BOOL)useFitScale {
  viewModel_.mutable_view_state()->use_fit_scale = useFitScale;
}

- (float)currentScale {
  return viewModel_.current_logical_scale();
}

- (void)setScrollOrigin:(NSPoint)origin {
  pdfview::core::ViewState* state = viewModel_.mutable_view_state();
  state->scroll_x = origin.x;
  state->scroll_y = origin.y;
}

- (void)updateCurrentPageFromScroll {
  viewModel_.update_current_page_from_scroll();
}

- (pdfview::core::ViewRect)currentPageRect {
  return viewModel_.current_page_rect();
}

@end
