#pragma once

#include <vector>

#include "core/document.h"
#include "core/page_cache.h"
#include "core/view_state.h"
#include "core/viewport.h"

namespace pdfview {
namespace core {

class DocumentViewModel {
 public:
  DocumentViewModel();
  explicit DocumentViewModel(const DocumentPtr& document);

  const DocumentPtr& document() const { return document_; }

  int page_count() const { return static_cast<int>(page_sizes_.size()); }

  const std::vector<PageSize>& page_sizes() const { return page_sizes_; }
  const std::vector<ViewRect>& page_frames() const { return layout_result_.page_frames; }
  const PageLayoutResult& layout_result() const { return layout_result_; }

  const ViewState& view_state() const { return view_state_; }
  ViewState* mutable_view_state() { return &view_state_; }

  const std::vector<PageCacheSlotState>& page_cache_states() const { return page_cache_states_; }
  std::vector<PageCacheSlotState>* mutable_page_cache_states() { return &page_cache_states_; }

  void set_viewport_size(float width, float height);
  void set_device_scale(float scale);

  float viewport_width() const { return viewport_width_; }
  float viewport_height() const { return viewport_height_; }
  float device_scale() const { return device_scale_; }

  float fit_width_scale() const;
  float fit_page_scale() const;
  float current_logical_scale() const;
  float current_render_scale() const;

  void relayout();
  void set_scroll_origin(float x, float y);
  ViewportAnchor capture_viewport_anchor() const;
  float restored_scroll_y_for_anchor(const ViewportAnchor& anchor) const;
  ViewRect visible_rect() const;
  PageCachePlan page_cache_plan(float preload_margin_y) const;
  PageRenderPlan page_render_plan() const;
  void update_current_page_from_scroll();
  float scroll_y_for_current_page() const;
  ViewRect current_page_rect() const;

 private:
  DocumentPtr document_;
  std::vector<PageSize> page_sizes_;
  std::vector<PageCacheSlotState> page_cache_states_;
  ViewState view_state_;
  PageLayoutResult layout_result_;
  float viewport_width_ = 0.0f;
  float viewport_height_ = 0.0f;
  float device_scale_ = 1.0f;
};

}  // namespace core
}  // namespace pdfview
