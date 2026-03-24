#pragma once

namespace pdfview {
namespace core {

enum class LayoutMode {
  SinglePage,
  Continuous,
};

struct ViewState {
  LayoutMode layout_mode = LayoutMode::Continuous;
  float zoom = 1.0f;
  bool use_fit_scale = false;
  float scroll_x = 0.0f;
  float scroll_y = 0.0f;
  int current_page = 0;
};

}  // namespace core
}  // namespace pdfview
