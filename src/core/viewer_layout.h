#pragma once

namespace pdfview {
namespace core {

struct ViewerLayoutMetrics {
  float page_gap = 24.0f;
  float side_margin = 16.0f;
  float fit_width_horizontal_padding = 48.0f;
  float fit_page_vertical_padding = 24.0f;
  float minimum_fit_scale = 0.25f;
  float minimum_fit_dimension = 120.0f;
};

struct ViewerBehaviorMetrics {
  float preload_margin_viewport_ratio = 0.5f;
  int keep_extra_pages_before = 1;
  int keep_extra_pages_after = 1;
  float viewport_step_min = 80.0f;
  float viewport_step_ratio = 0.9f;
  float interactive_scale_max_page_pixels = 2500000.0f;
  float interactive_scale_total_visible_pixels = 5000000.0f;
  float cache_covering_scale_ratio = 1.5f;
  float float_epsilon = 0.001f;
};

const ViewerLayoutMetrics& default_viewer_layout_metrics();
const ViewerBehaviorMetrics& default_viewer_behavior_metrics();

}  // namespace core
}  // namespace pdfview
