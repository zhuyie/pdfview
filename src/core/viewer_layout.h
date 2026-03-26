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

const ViewerLayoutMetrics& default_viewer_layout_metrics();

}  // namespace core
}  // namespace pdfview
