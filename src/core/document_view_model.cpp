#include "core/document_view_model.h"

#include <algorithm>
#include <string>

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

  const ViewerLayoutMetrics& metrics = default_viewer_layout_metrics();
  return compute_fit_scale(page_sizes_,
                           viewport_width_,
                           metrics.fit_width_horizontal_padding,
                           metrics.minimum_fit_scale);
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

  const ViewerLayoutMetrics& metrics = default_viewer_layout_metrics();
  const float fit_width = compute_fit_scale(std::vector<PageSize>(1, page_size),
                                            viewport_width_,
                                            metrics.fit_width_horizontal_padding,
                                            metrics.minimum_fit_scale);
  const float target_height =
      std::max(viewport_height_ - metrics.fit_page_vertical_padding,
               metrics.minimum_fit_dimension);
  const float fit_height = std::max(target_height / page_size.height, metrics.minimum_fit_scale);
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

bool DocumentViewModel::should_reduce_interactive_scale(float device_scale) const {
  if (device_scale <= 1.0f || layout_result_.page_frames.empty()) {
    return false;
  }

  const ViewRect rect = visible_rect();
  const PageCachePlan cache_plan = page_cache_plan(rect.height * 0.5f);
  if (cache_plan.preload_range.empty()) {
    return false;
  }

  double total_visible_pixels = 0.0;
  double max_page_pixels = 0.0;
  for (int page_index = cache_plan.preload_range.start;
       page_index < cache_plan.preload_range.end;
       ++page_index) {
    if (page_index < 0 || page_index >= static_cast<int>(layout_result_.page_frames.size())) {
      continue;
    }

    const ViewRect& frame = layout_result_.page_frames[page_index];
    const double page_pixels =
        static_cast<double>(frame.width) * static_cast<double>(frame.height) *
        static_cast<double>(device_scale) * static_cast<double>(device_scale);
    total_visible_pixels += page_pixels;
    max_page_pixels = std::max(max_page_pixels, page_pixels);
  }

  return max_page_pixels >= 2500000.0 || total_visible_pixels >= 5000000.0;
}

void DocumentViewModel::relayout() {
  const ViewerLayoutMetrics& metrics = default_viewer_layout_metrics();
  PageLayoutConfig layout_config;
  layout_config.viewport_width = viewport_width_;
  layout_config.viewport_height = viewport_height_;
  layout_config.zoom = current_logical_scale();
  layout_config.side_margin = metrics.side_margin;
  layout_config.page_gap = metrics.page_gap;
  layout_config.top_margin = layout_config.page_gap * 0.5f;

  layout_result_ = compute_continuous_page_layout(page_sizes_, layout_config);
}

void DocumentViewModel::set_scroll_origin(float x, float y) {
  view_state_.scroll_x = x;
  view_state_.scroll_y = y;
}

ScaleChangeState DocumentViewModel::capture_scale_change_state() const {
  ScaleChangeState state;
  state.anchor = capture_viewport_anchor();
  state.anchor_page_index = state.anchor.page_index;
  return state;
}

float DocumentViewModel::restored_scroll_y_for_scale_change(const ScaleChangeState& state) {
  view_state_.current_page = state.anchor_page_index;
  return restored_scroll_y_for_anchor(state.anchor);
}

ViewportAnchor DocumentViewModel::capture_viewport_anchor() const {
  return pdfview::core::capture_viewport_anchor(layout_result_.page_frames, view_state_.scroll_y);
}

float DocumentViewModel::restored_scroll_y_for_anchor(const ViewportAnchor& anchor) const {
  return pdfview::core::restore_viewport_anchor(anchor,
                                                layout_result_.page_frames,
                                                viewport_height_,
                                                layout_result_.document_height);
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

float DocumentViewModel::scroll_y_after_viewport_step(float delta) const {
  const float page_step = std::max(80.0f, viewport_height_ * 0.9f);
  const float max_scroll_y = std::max(layout_result_.document_height - viewport_height_, 0.0f);
  return std::min(std::max(view_state_.scroll_y + delta * page_step, 0.0f), max_scroll_y);
}

float DocumentViewModel::scroll_y_for_current_page() const {
  const ViewRect rect = current_page_rect();
  if (rect.height <= 0.0f) {
    return view_state_.scroll_y;
  }

  const float edge_padding =
      layout_result_.page_frames.empty() ? 0.0f : layout_result_.page_frames.front().y;
  const float target_scroll_y = rect.y - edge_padding;

  const float max_scroll_y = std::max(layout_result_.document_height - viewport_height_, 0.0f);
  return std::min(std::max(target_scroll_y, 0.0f), max_scroll_y);
}

std::string DocumentViewModel::page_indicator_text() const {
  if (page_count() <= 0) {
    return std::string();
  }

  const int current_page = std::max(0, std::min(view_state_.current_page, page_count() - 1));
  return std::to_string(current_page + 1) + " / " + std::to_string(page_count());
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
