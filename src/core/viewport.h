#pragma once

#include <vector>

#include "core/document.h"

namespace pdfview {
namespace core {

struct ViewRect {
  float x = 0.0f;
  float y = 0.0f;
  float width = 0.0f;
  float height = 0.0f;
};

struct PageLayoutConfig {
  float viewport_width = 0.0f;
  float viewport_height = 0.0f;
  float zoom = 1.0f;
  float top_margin = 0.0f;
  float side_margin = 0.0f;
  float page_gap = 0.0f;
};

struct PageLayoutResult {
  std::vector<ViewRect> page_frames;
  float document_width = 0.0f;
  float document_height = 0.0f;
};

struct PageIndexRange {
  int start = 0;
  int end = 0;

  bool empty() const { return start >= end; }
};

struct PageCachePlan {
  ViewRect visible_rect;
  ViewRect preload_rect;
  PageIndexRange visible_range;
  PageIndexRange preload_range;
  PageIndexRange keep_range;
};

struct ViewportAnchor {
  int page_index = 0;
  float offset_y = 0.0f;
  float page_height = 0.0f;
  bool offset_scales_with_page = false;
};

PageLayoutResult compute_continuous_page_layout(const std::vector<PageSize>& page_sizes,
                                                const PageLayoutConfig& config);

float compute_fit_scale(const std::vector<PageSize>& page_sizes,
                        float viewport_width,
                        float horizontal_padding,
                        float minimum_dimension,
                        float min_scale);

ViewRect expand_rect(const ViewRect& rect, float expand_x, float expand_y);

PageIndexRange find_intersecting_pages(const std::vector<ViewRect>& page_frames,
                                       const ViewRect& rect);

PageCachePlan compute_page_cache_plan(const std::vector<ViewRect>& page_frames,
                                      const ViewRect& visible_rect,
                                      float preload_margin_y);

int find_nearest_page_to_viewport_center(const std::vector<ViewRect>& page_frames,
                                         float viewport_y,
                                         float viewport_height);

int find_page_at_viewport_top(const std::vector<ViewRect>& page_frames, float viewport_top_y);

ViewportAnchor capture_viewport_anchor(const std::vector<ViewRect>& page_frames, float viewport_top_y);

float restore_viewport_anchor(const ViewportAnchor& anchor,
                              const std::vector<ViewRect>& page_frames,
                              float viewport_height,
                              float document_height);

}  // namespace core
}  // namespace pdfview
