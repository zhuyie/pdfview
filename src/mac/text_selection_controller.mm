#import "mac/text_selection_controller.h"

#include <algorithm>
#include <string>
#include <vector>

#include "core/text_selection.h"

@interface PDFTextSelectionController ()

- (BOOL)resolveDocumentSelectionPoint:(NSPoint)documentLocation
                              context:(PDFTabContext*)context
                            pageIndex:(int*)pageIndex
                         pageLocation:(NSPoint*)pageLocation;
- (BOOL)resolveDocumentSelectionFallback:(NSPoint)documentLocation
                                 context:(PDFTabContext*)context
                               pageIndex:(int*)pageIndex
                               charIndex:(int*)charIndex;
- (void)applyTextSelectionForFocusPageIndex:(int)focusPageIndex
                                   charIndex:(int)focusCharIndex
                                     context:(PDFTabContext*)context;

@end

@implementation PDFTextSelectionController

- (int)textIndexForPageSelectionAtPageIndex:(int)pageIndex
                                   location:(NSPoint)location
                                    context:(PDFTabContext*)context {
  if (context == nil ||
      pageIndex < 0 ||
      pageIndex >= static_cast<int>(context->viewModel_.page_frames().size()) ||
      pageIndex >= static_cast<int>(context->viewModel_.page_sizes().size())) {
    return -1;
  }

  float pageX = 0.0f;
  float pageY = 0.0f;
  if (!pdfview::core::page_point_from_page_view_point(
          location.x,
          location.y,
          context->viewModel_.page_sizes()[pageIndex],
          context->viewModel_.page_frames()[pageIndex],
          &pageX,
          &pageY)) {
    return -1;
  }

  const float logicalScale = std::max(context->viewModel_.current_logical_scale(), 0.1f);
  const float tolerance = 6.0f / logicalScale;
  return context->viewModel_.document()->text_index_at_point(
      pageIndex, pageX, pageY, tolerance, tolerance);
}

- (void)updateTextSelectionAtPageIndex:(int)pageIndex
                              location:(NSPoint)location
                               context:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  const int charIndex = [self textIndexForPageSelectionAtPageIndex:pageIndex
                                                          location:location
                                                           context:context];
  if (charIndex < 0) {
    if (!context->textSelection_.anchor.valid()) {
      return;
    }

    float pageX = 0.0f;
    float pageY = 0.0f;
    if (!pdfview::core::page_point_from_page_view_point(
            location.x,
            location.y,
            context->viewModel_.page_sizes()[pageIndex],
            context->viewModel_.page_frames()[pageIndex],
            &pageX,
            &pageY)) {
      return;
    }

    const int fallbackCharIndex =
        context->viewModel_.document()->nearest_text_index_at_point(pageIndex, pageX, pageY);
    if (fallbackCharIndex < 0) {
      return;
    }

    [self applyTextSelectionForFocusPageIndex:pageIndex
                                    charIndex:fallbackCharIndex
                                      context:context];
    return;
  }

  if (!context->textSelection_.anchor.valid()) {
    [context setTextSelectionAnchorPageIndex:pageIndex charIndex:charIndex];
    return;
  }

  [self applyTextSelectionForFocusPageIndex:pageIndex charIndex:charIndex context:context];
}

- (BOOL)resolveDocumentSelectionPoint:(NSPoint)documentLocation
                              context:(PDFTabContext*)context
                            pageIndex:(int*)pageIndex
                         pageLocation:(NSPoint*)pageLocation {
  if (context == nil || pageIndex == NULL || pageLocation == NULL) {
    return NO;
  }

  float pageX = 0.0f;
  float pageY = 0.0f;
  const bool resolved = pdfview::core::resolve_document_selection_point(
      documentLocation.x,
      documentLocation.y,
      context->viewModel_.page_frames(),
      pageIndex,
      &pageX,
      &pageY);
  if (!resolved) {
    return NO;
  }

  pageLocation->x = pageX;
  pageLocation->y = pageY;
  return YES;
}

- (BOOL)resolveDocumentSelectionFallback:(NSPoint)documentLocation
                                 context:(PDFTabContext*)context
                               pageIndex:(int*)pageIndex
                               charIndex:(int*)charIndex {
  if (context == nil || pageIndex == NULL || charIndex == NULL) {
    return NO;
  }

  return pdfview::core::resolve_document_selection_fallback(
      documentLocation.y,
      context->textSelection_.anchor.page_index,
      context->viewModel_.page_frames(),
      *context->viewModel_.document(),
      pageIndex,
      charIndex);
}

- (void)refreshTextSelectionAtDocumentLocation:(NSPoint)documentLocation
                                       context:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  int pageIndex = -1;
  NSPoint pageLocation = NSZeroPoint;
  if (![self resolveDocumentSelectionPoint:documentLocation
                                   context:context
                                 pageIndex:&pageIndex
                              pageLocation:&pageLocation]) {
    int fallbackPageIndex = -1;
    int fallbackCharIndex = -1;
    if ([self resolveDocumentSelectionFallback:documentLocation
                                       context:context
                                     pageIndex:&fallbackPageIndex
                                     charIndex:&fallbackCharIndex]) {
      if (!context->textSelection_.anchor.valid()) {
        [context setTextSelectionAnchorPageIndex:fallbackPageIndex charIndex:fallbackCharIndex];
        return;
      }
      [self applyTextSelectionForFocusPageIndex:fallbackPageIndex
                                      charIndex:fallbackCharIndex
                                        context:context];
    }
    return;
  }

  [self updateTextSelectionAtPageIndex:pageIndex location:pageLocation context:context];
}

- (void)applyTextSelectionForFocusPageIndex:(int)focusPageIndex
                                   charIndex:(int)focusCharIndex
                                     context:(PDFTabContext*)context {
  if (context == nil || focusPageIndex < 0 || focusCharIndex < 0) {
    return;
  }

  pdfview::core::TextSelectionEndpoint anchor = context->textSelection_.anchor;
  pdfview::core::TextSelectionEndpoint focus;
  focus.page_index = focusPageIndex;
  focus.char_index = focusCharIndex;

  const pdfview::core::TextSelectionRange range =
      pdfview::core::make_text_selection_range(anchor, focus);
  if (range.empty()) {
    [context updateTextSelectionWithFocusPageIndex:focusPageIndex
                                         charIndex:focusCharIndex
                                             text:std::string()
                                            spans:std::vector<pdfview::core::PageTextSelectionSpan>()];
    return;
  }

  const pdfview::core::DocumentTextSelection selection =
      pdfview::core::build_document_text_selection(*context->viewModel_.document(), range);

  [context updateTextSelectionWithFocusPageIndex:focusPageIndex
                                       charIndex:focusCharIndex
                                            text:selection.text
                                           spans:selection.spans];
}

- (void)selectWordAtPageIndex:(int)pageIndex
                     location:(NSPoint)location
                      context:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  const int charIndex = [self textIndexForPageSelectionAtPageIndex:pageIndex
                                                          location:location
                                                           context:context];
  if (charIndex < 0) {
    [context clearTextSelection];
    return;
  }

  const pdfview::core::PageTextSelection selection =
      context->viewModel_.document()->word_selection_at_index(pageIndex, charIndex);
  if (!selection.ok()) {
    [context clearTextSelection];
    return;
  }

  [context beginTextSelectionOnPageIndex:pageIndex charIndex:selection.start_index];
  std::vector<pdfview::core::PageTextSelectionSpan> spans(1);
  spans[0].page_index = pageIndex;
  spans[0].rects = selection.rects;
  [context updateTextSelectionWithFocusPageIndex:pageIndex
                                       charIndex:selection.start_index + selection.count - 1
                                            text:selection.text
                                           spans:spans];
  [context endTextSelection];
}

- (BOOL)selectAllTextInContext:(PDFTabContext*)context {
  if (context == nil) {
    return NO;
  }

  int firstPageIndex = -1;
  int lastPageIndex = -1;
  int lastCharIndex = -1;
  for (int pageIndex = 0; pageIndex < context->viewModel_.page_count(); ++pageIndex) {
    const int pageCharCount = context->viewModel_.document()->page_text_char_count(pageIndex);
    if (pageCharCount <= 0) {
      continue;
    }

    if (firstPageIndex < 0) {
      firstPageIndex = pageIndex;
    }
    lastPageIndex = pageIndex;
    lastCharIndex = pageCharCount - 1;
  }

  if (firstPageIndex < 0 || lastPageIndex < 0 || lastCharIndex < 0) {
    [context clearTextSelection];
    return NO;
  }

  [context beginTextSelectionOnPageIndex:firstPageIndex charIndex:0];
  [self applyTextSelectionForFocusPageIndex:lastPageIndex
                                  charIndex:lastCharIndex
                                    context:context];
  [context endTextSelection];
  return [context hasSelectedText];
}

@end
