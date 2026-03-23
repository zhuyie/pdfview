#include "core/viewport.h"

#include <algorithm>
#include <cmath>

namespace pdfview {
namespace core {

namespace {

bool intersects(const ViewRect& lhs, const ViewRect& rhs) {
  return lhs.x < rhs.x + rhs.width && rhs.x < lhs.x + lhs.width &&
         lhs.y < rhs.y + rhs.height && rhs.y < lhs.y + lhs.height;
}

}  // namespace

PageLayoutResult compute_continuous_page_layout(const std::vector<PageSize>& page_sizes,
                                                const PageLayoutConfig& config) {
  PageLayoutResult result;
  result.page_frames.resize(page_sizes.size());

  float document_width = config.viewport_width;
  float max_page_width = 0.0f;
  float cursor_y = config.top_margin;

  for (size_t index = 0; index < page_sizes.size(); ++index) {
    const PageSize& page_size = page_sizes[index];
    const float page_width = page_size.width * config.zoom;
    const float page_height = page_size.height * config.zoom;
    const float page_x = std::max((config.viewport_width - page_width) * 0.5f, config.side_margin);

    ViewRect frame;
    frame.x = page_x;
    frame.y = cursor_y;
    frame.width = page_width;
    frame.height = page_height;
    result.page_frames[index] = frame;

    cursor_y += page_height + config.page_gap;
    document_width = std::max(document_width, frame.x + frame.width + config.side_margin);
    max_page_width = std::max(max_page_width, page_width);
  }

  result.document_width = std::max(document_width, max_page_width + config.side_margin * 2.0f);
  result.document_height = std::max(cursor_y, config.viewport_height);
  return result;
}

float compute_fit_scale(const std::vector<PageSize>& page_sizes,
                        float viewport_width,
                        float horizontal_padding,
                        float min_scale) {
  float max_page_width = 0.0f;
  for (size_t index = 0; index < page_sizes.size(); ++index) {
    max_page_width = std::max(max_page_width, page_sizes[index].width);
  }

  if (max_page_width <= 0.0f) {
    return 1.0f;
  }

  const float target_width = std::max(viewport_width - horizontal_padding, 120.0f);
  return std::max(target_width / max_page_width, min_scale);
}

ViewRect expand_rect(const ViewRect& rect, float expand_x, float expand_y) {
  ViewRect expanded = rect;
  expanded.x -= expand_x;
  expanded.y -= expand_y;
  expanded.width += expand_x * 2.0f;
  expanded.height += expand_y * 2.0f;
  return expanded;
}

PageIndexRange find_intersecting_pages(const std::vector<ViewRect>& page_frames,
                                       const ViewRect& rect) {
  PageIndexRange range;
  range.start = static_cast<int>(page_frames.size());
  range.end = static_cast<int>(page_frames.size());

  for (int index = 0; index < static_cast<int>(page_frames.size()); ++index) {
    if (!intersects(page_frames[index], rect)) {
      continue;
    }

    if (range.empty()) {
      range.start = index;
      range.end = index + 1;
    } else {
      range.start = std::min(range.start, index);
      range.end = index + 1;
    }
  }

  if (range.empty()) {
    range.start = 0;
    range.end = 0;
  }

  return range;
}

PageCachePlan compute_page_cache_plan(const std::vector<ViewRect>& page_frames,
                                      const ViewRect& visible_rect,
                                      float preload_margin_y) {
  PageCachePlan plan;
  plan.visible_rect = visible_rect;
  plan.preload_rect = expand_rect(visible_rect, 0.0f, preload_margin_y);
  plan.visible_range = find_intersecting_pages(page_frames, visible_rect);
  plan.preload_range = find_intersecting_pages(page_frames, plan.preload_rect);
  return plan;
}

int find_nearest_page_to_viewport_center(const std::vector<ViewRect>& page_frames,
                                         float viewport_y,
                                         float viewport_height) {
  if (page_frames.empty()) {
    return 0;
  }

  const float viewport_center_y = viewport_y + viewport_height * 0.5f;
  int nearest_page = 0;
  float nearest_distance = 0.0f;

  for (int index = 0; index < static_cast<int>(page_frames.size()); ++index) {
    const ViewRect& frame = page_frames[index];
    const float page_center_y = frame.y + frame.height * 0.5f;
    const float distance = std::fabs(page_center_y - viewport_center_y);
    if (index == 0 || distance < nearest_distance) {
      nearest_page = index;
      nearest_distance = distance;
    }
  }

  return nearest_page;
}

}  // namespace core
}  // namespace pdfview
