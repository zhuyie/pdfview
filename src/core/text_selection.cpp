#include "core/text_selection.h"

#include <algorithm>

namespace pdfview {
namespace core {

TextCharRange make_text_char_range(int anchor_index, int focus_index) {
  TextCharRange range;
  if (anchor_index < 0 || focus_index < 0 || anchor_index == focus_index) {
    return range;
  }

  range.start_index = std::min(anchor_index, focus_index);
  range.count = std::max(anchor_index, focus_index) - range.start_index + 1;
  return range;
}

bool page_point_from_page_view_point(float view_x,
                                     float view_y,
                                     const PageSize& page_size,
                                     const ViewRect& page_frame,
                                     float* page_x,
                                     float* page_y) {
  if (page_x == NULL || page_y == NULL || page_size.width <= 0.0f ||
      page_size.height <= 0.0f || page_frame.width <= 0.0f ||
      page_frame.height <= 0.0f) {
    return false;
  }

  const float scale_x = page_frame.width / page_size.width;
  const float scale_y = page_frame.height / page_size.height;
  if (scale_x <= 0.0f || scale_y <= 0.0f) {
    return false;
  }

  *page_x = std::max(0.0f, std::min(view_x / scale_x, page_size.width));
  *page_y =
      std::max(0.0f, std::min(page_size.height - (view_y / scale_y), page_size.height));
  return true;
}

std::vector<ViewRect> page_text_rects_to_page_view_rects(
    const std::vector<PageTextRect>& rects,
    const PageSize& page_size,
    const ViewRect& page_frame) {
  std::vector<ViewRect> view_rects;
  if (page_size.width <= 0.0f || page_size.height <= 0.0f ||
      page_frame.width <= 0.0f || page_frame.height <= 0.0f) {
    return view_rects;
  }

  const float scale_x = page_frame.width / page_size.width;
  const float scale_y = page_frame.height / page_size.height;
  for (size_t index = 0; index < rects.size(); ++index) {
    const PageTextRect& rect = rects[index];
    ViewRect view_rect;
    view_rect.x = rect.left * scale_x;
    view_rect.y = (page_size.height - rect.top) * scale_y;
    view_rect.width = std::max(0.0f, rect.right - rect.left) * scale_x;
    view_rect.height = std::max(0.0f, rect.top - rect.bottom) * scale_y;
    if (view_rect.width <= 0.0f || view_rect.height <= 0.0f) {
      continue;
    }
    view_rects.push_back(view_rect);
  }

  return view_rects;
}

}  // namespace core
}  // namespace pdfview
