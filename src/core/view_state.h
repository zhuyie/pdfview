#pragma once

namespace pdfview {
namespace core {

enum class LayoutMode {
  SinglePage,
  Continuous,
};

enum class ScaleMode {
  Manual,
  FitWidth,
  FitPage,
};

struct ViewState {
  LayoutMode layout_mode = LayoutMode::Continuous;
  ScaleMode scale_mode = ScaleMode::Manual;
  float zoom = 1.0f;
  float scroll_x = 0.0f;
  float scroll_y = 0.0f;
  int current_page = 0;
};

}  // namespace core
}  // namespace pdfview
