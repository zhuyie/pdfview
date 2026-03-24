#pragma once

#import <AppKit/AppKit.h>

#include <string>
#include <vector>

#include "core/document_view_model.h"
#include "mac/page_view_host.h"

struct PageRenderCacheEntry {
  NSImage* image;
  long long requestId;

  PageRenderCacheEntry() : image(nil), requestId(0) {}
};

struct RenderPlanFingerprint {
  float renderScale = 0.0f;
  pdfview::core::PageIndexRange visibleRange;
  pdfview::core::PageIndexRange preloadRange;
  pdfview::core::PageIndexRange keepRange;
  bool valid = false;
};

@interface FlippedDocumentView : NSView
@end

@interface PDFTabContext : NSObject {
 @public
  std::string documentPath_;
  NSView* containerView_;
  NSScrollView* scrollView_;
  FlippedDocumentView* documentView_;
  pdfview::core::DocumentViewModel viewModel_;
  std::vector<NSImageView*> pageImageViews_;
  PDFPageViewHost* pageViewHost_;
  std::vector<PageRenderCacheEntry> pageCache_;
  RenderPlanFingerprint lastRenderPlanFingerprint_;
}

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame;
- (NSString*)tabTitle;
- (void)invalidateRenderedPages;
- (BOOL)isRenderRequestCurrent:(int)pageIndex
                   renderScale:(float)renderScale
                     requestId:(long long)requestId;
- (BOOL)hasPageImageAtIndex:(int)pageIndex;
- (BOOL)shouldSubmitRenderForPageIndex:(int)pageIndex renderScale:(float)renderScale;
- (void)markPageDiscarded:(int)pageIndex;
- (void)markPageRendered:(int)pageIndex renderScale:(float)renderScale;
- (void)markPageRequested:(int)pageIndex renderScale:(float)renderScale requestId:(long long)requestId;
- (void)setManualScale:(float)scale;
- (void)setUseFitScale:(BOOL)useFitScale;
- (float)currentScale;
- (void)setScrollOrigin:(NSPoint)origin;
- (void)updateCurrentPageFromScroll;
- (pdfview::core::ViewRect)currentPageRect;
- (void)syncPageFrames;
- (void)clearPageImageAtIndex:(int)pageIndex;
- (void)applyPageImage:(NSImage*)image atIndex:(int)pageIndex;
- (BOOL)shouldSkipVisibleUpdateForCachePlan:(const pdfview::core::PageCachePlan&)cachePlan
                                 renderPlan:(const pdfview::core::PageRenderPlan&)renderPlan
                                renderScale:(float)renderScale;
- (void)rememberVisibleUpdateForCachePlan:(const pdfview::core::PageCachePlan&)cachePlan
                               renderPlan:(const pdfview::core::PageRenderPlan&)renderPlan
                              renderScale:(float)renderScale;

@end
