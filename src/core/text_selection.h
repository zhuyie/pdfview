#pragma once

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

bool is_word_codepoint(unsigned int codepoint);

TextCharRange word_char_range_from_text(const std::vector<unsigned int>& codepoints,
                                        int char_index);

TextCharRange make_text_char_range(int anchor_index, int focus_index);

TextSelectionRange make_text_selection_range(const TextSelectionEndpoint& anchor,
                                             const TextSelectionEndpoint& focus);

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
