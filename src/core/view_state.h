#pragma once

namespace pdfview::core {

enum class LayoutMode {
  SinglePage,
  Continuous,
};

struct ViewState {
  LayoutMode layout_mode = LayoutMode::Continuous;
  float zoom = 1.0f;
  float scroll_x = 0.0f;
  float scroll_y = 0.0f;
  int current_page = 0;
};

}  // namespace pdfview::core
