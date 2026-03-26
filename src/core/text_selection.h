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

TextCharRange make_text_char_range(int anchor_index, int focus_index);

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
