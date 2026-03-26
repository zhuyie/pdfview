#pragma once

#include <string>
#include <vector>

#include "core/document.h"
#include "core/viewport.h"

namespace pdfview {
namespace core {

struct TextCharRange {
  int start_index = -1;
  int count = 0;

  bool empty() const { return start_index < 0 || count <= 0; }
};

struct TextSelectionEndpoint {
  int page_index = -1;
  int char_index = -1;

  bool valid() const { return page_index >= 0 && char_index >= 0; }
};

struct TextSelectionRange {
  TextSelectionEndpoint start;
  TextSelectionEndpoint end;

  bool empty() const {
    return !start.valid() || !end.valid() ||
           (start.page_index == end.page_index && start.char_index == end.char_index);
  }
};

struct TextSelectionState {
  bool dragging = false;
  TextSelectionEndpoint anchor;
  TextSelectionEndpoint focus;
  std::string text;
  std::vector<PageTextSelectionSpan> spans;

  bool has_selected_text() const { return !text.empty(); }
};

struct DocumentTextSelection {
  std::string text;
  std::vector<PageTextSelectionSpan> spans;

  bool empty() const { return text.empty() && spans.empty(); }
};

bool is_word_codepoint(unsigned int codepoint);

TextCharRange word_char_range_from_text(const std::vector<unsigned int>& codepoints,
                                        int char_index);

TextCharRange make_text_char_range(int anchor_index, int focus_index);

TextSelectionRange make_text_selection_range(const TextSelectionEndpoint& anchor,
                                             const TextSelectionEndpoint& focus);

DocumentTextSelection build_document_text_selection(const Document& document,
                                                    const TextSelectionRange& range);

bool resolve_document_selection_point(float document_x,
                                      float document_y,
                                      const std::vector<ViewRect>& page_frames,
                                      int* page_index,
                                      float* page_x,
                                      float* page_y);

bool resolve_document_selection_fallback(float document_y,
                                         int anchor_page_index,
                                         const std::vector<ViewRect>& page_frames,
                                         const Document& document,
                                         int* page_index,
                                         int* char_index);

bool page_point_from_page_view_point(float view_x,
                                     float view_y,
                                     const PageSize& page_size,
                                     const ViewRect& page_frame,
                                     float* page_x,
                                     float* page_y);

std::vector<ViewRect> page_text_rects_to_page_view_rects(
    const std::vector<PageTextRect>& rects,
    const PageSize& page_size,
    const ViewRect& page_frame);

}  // namespace core
}  // namespace pdfview
