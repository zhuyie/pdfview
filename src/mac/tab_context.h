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

struct TextSelectionState {
  bool dragging;
  int pageIndex;
  int anchorCharIndex;
  int focusCharIndex;
  std::string text;
  std::vector<pdfview::core::PageTextRect> pageRects;

  TextSelectionState()
      : dragging(false), pageIndex(-1), anchorCharIndex(-1), focusCharIndex(-1) {}
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
  pdfview::core::RenderPlanFingerprint lastRenderPlanFingerprint_;
  TextSelectionState textSelection_;
}

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame
                        delegate:(id<PDFPageViewHostDelegate>)delegate;
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
- (void)setScaleMode:(pdfview::core::ScaleMode)scaleMode;
- (float)currentScale;
- (void)syncPageFrames;
- (void)clearPageImageAtIndex:(int)pageIndex;
- (void)applyPageImage:(NSImage*)image atIndex:(int)pageIndex;
- (BOOL)shouldSkipVisibleUpdateForCachePlan:(const pdfview::core::PageCachePlan&)cachePlan
                                renderScale:(float)renderScale;
- (void)rememberVisibleUpdateForCachePlan:(const pdfview::core::PageCachePlan&)cachePlan
                              renderScale:(float)renderScale;
- (void)beginTextSelectionOnPageIndex:(int)pageIndex charIndex:(int)charIndex;
- (void)setTextSelectionAnchorCharIndex:(int)charIndex;
- (void)updateTextSelectionWithFocusCharIndex:(int)charIndex
                                         text:(const std::string&)text
                                    pageRects:(const std::vector<pdfview::core::PageTextRect>&)pageRects;
- (void)endTextSelection;
- (void)clearTextSelection;
- (void)syncTextSelectionOverlay;
- (BOOL)hasSelectedText;
- (NSString*)selectedText;

@end
