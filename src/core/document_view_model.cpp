#include "core/document_view_model.h"

#include <algorithm>

namespace pdfview {
namespace core {

DocumentViewModel::DocumentViewModel() {}

DocumentViewModel::DocumentViewModel(const DocumentPtr& document) : document_(document) {
  const int page_count = document_ ? document_->page_count() : 0;
  page_sizes_.resize(page_count);
  page_cache_states_ = make_page_cache_states(page_count);
  for (int page_index = 0; page_index < page_count; ++page_index) {
    page_sizes_[page_index] = document_->page_size(page_index);
  }
}

void DocumentViewModel::set_viewport_size(float width, float height) {
  viewport_width_ = width;
  viewport_height_ = height;
}

void DocumentViewModel::set_device_scale(float scale) {
  device_scale_ = std::max(scale, 1.0f);
}

float DocumentViewModel::fit_width_scale() const {
  if (!document_ || page_sizes_.empty()) {
    return 1.0f;
  }

  return compute_fit_scale(page_sizes_, viewport_width_, 48.0f, 0.25f);
}

float DocumentViewModel::fit_page_scale() const {
  if (!document_ || page_sizes_.empty()) {
    return 1.0f;
  }

  int page_index = view_state_.current_page;
  if (page_index < 0 || page_index >= static_cast<int>(page_sizes_.size())) {
    page_index = 0;
  }

  const PageSize& page_size = page_sizes_[page_index];
  if (page_size.width <= 0.0f || page_size.height <= 0.0f) {
    return 1.0f;
  }

  const float fit_width = compute_fit_scale(std::vector<PageSize>(1, page_size),
                                            viewport_width_,
                                            48.0f,
                                            0.25f);
  const float target_height = std::max(viewport_height_ - 48.0f, 120.0f);
  const float fit_height = std::max(target_height / page_size.height, 0.25f);
  return std::min(fit_width, fit_height);
}

float DocumentViewModel::current_logical_scale() const {
  switch (view_state_.scale_mode) {
    case ScaleMode::FitWidth:
      return fit_width_scale();
    case ScaleMode::FitPage:
      return fit_page_scale();
    case ScaleMode::Manual:
      break;
  }

  return std::max(0.1f, view_state_.zoom);
}

float DocumentViewModel::current_render_scale() const {
  return current_logical_scale() * device_scale_;
}

void DocumentViewModel::relayout() {
  PageLayoutConfig layout_config;
  layout_config.viewport_width = viewport_width_;
  layout_config.viewport_height = viewport_height_;
  layout_config.zoom = current_logical_scale();
  layout_config.top_margin = 20.0f;
  layout_config.side_margin = 16.0f;
  layout_config.page_gap = 24.0f;

  layout_result_ = compute_continuous_page_layout(page_sizes_, layout_config);
}

ViewRect DocumentViewModel::visible_rect() const {
  ViewRect rect;
  rect.x = view_state_.scroll_x;
  rect.y = view_state_.scroll_y;
  rect.width = viewport_width_;
  rect.height = viewport_height_;
  return rect;
}

PageCachePlan DocumentViewModel::page_cache_plan(float preload_margin_y) const {
  return compute_page_cache_plan(layout_result_.page_frames, visible_rect(), preload_margin_y);
}

PageRenderPlan DocumentViewModel::page_render_plan() const {
  const ViewRect rect = visible_rect();
  const PageCachePlan cache_plan =
      page_cache_plan(rect.height * 0.5f);
  return plan_page_rendering(cache_plan.preload_range,
                             cache_plan.keep_range,
                             page_cache_states_,
                             layout_result_.page_frames,
                             rect,
                             current_render_scale());
}

void DocumentViewModel::update_current_page_from_scroll() {
  if (layout_result_.page_frames.empty()) {
    view_state_.current_page = 0;
    return;
  }

  view_state_.current_page = find_nearest_page_to_viewport_center(
      layout_result_.page_frames, view_state_.scroll_y, viewport_height_);
}

ViewRect DocumentViewModel::current_page_rect() const {
  if (view_state_.current_page < 0 ||
      view_state_.current_page >= static_cast<int>(layout_result_.page_frames.size())) {
    return ViewRect();
  }

  return layout_result_.page_frames[view_state_.current_page];
}

}  // namespace core
}  // namespace pdfview
