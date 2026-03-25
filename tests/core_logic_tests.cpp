#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "core/document_view_model.h"
#include "core/page_cache.h"
#include "core/viewport.h"

namespace {

bool NearlyEqual(float lhs, float rhs, float epsilon = 0.001f) {
  return std::fabs(lhs - rhs) <= epsilon;
}

bool Expect(bool condition, const char* message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    return false;
  }
  return true;
}

class FakeDocument : public pdfview::core::Document {
 public:
  explicit FakeDocument(const std::vector<pdfview::core::PageSize>& page_sizes)
      : page_sizes_(page_sizes) {}

  int page_count() const override { return static_cast<int>(page_sizes_.size()); }

  pdfview::core::PageSize page_size(int page_index) const override {
    if (page_index < 0 || page_index >= static_cast<int>(page_sizes_.size())) {
      return pdfview::core::PageSize();
    }
    return page_sizes_[page_index];
  }

  pdfview::core::RenderPageResult render_page(int, float) const override {
    return pdfview::core::RenderPageResult();
  }

 private:
  std::vector<pdfview::core::PageSize> page_sizes_;
};

bool TestComputeFitScale() {
  std::vector<pdfview::core::PageSize> page_sizes(2);
  page_sizes[0].width = 400.0f;
  page_sizes[1].width = 600.0f;

  const float scale = pdfview::core::compute_fit_scale(page_sizes, 800.0f, 48.0f, 0.25f);
  return Expect(NearlyEqual(scale, 752.0f / 600.0f), "compute_fit_scale returned an unexpected value");
}

bool TestContinuousLayout() {
  std::vector<pdfview::core::PageSize> page_sizes(2);
  page_sizes[0].width = 300.0f;
  page_sizes[0].height = 500.0f;
  page_sizes[1].width = 400.0f;
  page_sizes[1].height = 200.0f;

  pdfview::core::PageLayoutConfig config;
  config.viewport_width = 700.0f;
  config.viewport_height = 600.0f;
  config.zoom = 1.0f;
  config.top_margin = 20.0f;
  config.side_margin = 16.0f;
  config.page_gap = 24.0f;

  const pdfview::core::PageLayoutResult result =
      pdfview::core::compute_continuous_page_layout(page_sizes, config);

  return Expect(result.page_frames.size() == 2, "layout should create two page frames") &&
         Expect(NearlyEqual(result.page_frames[0].x, 200.0f), "first page x is incorrect") &&
         Expect(NearlyEqual(result.page_frames[0].y, 20.0f), "first page y is incorrect") &&
         Expect(NearlyEqual(result.page_frames[1].x, 150.0f), "second page x is incorrect") &&
         Expect(NearlyEqual(result.page_frames[1].y, 544.0f), "second page y is incorrect") &&
         Expect(NearlyEqual(result.document_height, 768.0f), "document height is incorrect");
}

bool TestNearestPageSelection() {
  std::vector<pdfview::core::ViewRect> page_frames(3);
  page_frames[0].y = 20.0f;
  page_frames[0].height = 300.0f;
  page_frames[1].y = 360.0f;
  page_frames[1].height = 300.0f;
  page_frames[2].y = 700.0f;
  page_frames[2].height = 300.0f;

  const int nearest = pdfview::core::find_nearest_page_to_viewport_center(page_frames, 400.0f, 200.0f);
  return Expect(nearest == 1, "nearest page selection is incorrect");
}

bool TestPageRenderPlanOrdering() {
  std::vector<pdfview::core::PageCacheSlotState> states =
      pdfview::core::make_page_cache_states(3);
  pdfview::core::mark_page_cache_rendered(&states, 0, 1.0f);
  pdfview::core::mark_page_cache_rendered(&states, 2, 1.0f);

  std::vector<pdfview::core::ViewRect> page_frames(3);
  page_frames[0].y = 0.0f;
  page_frames[0].height = 200.0f;
  page_frames[0].width = 100.0f;
  page_frames[1].y = 220.0f;
  page_frames[1].height = 200.0f;
  page_frames[1].width = 100.0f;
  page_frames[2].y = 440.0f;
  page_frames[2].height = 200.0f;
  page_frames[2].width = 100.0f;

  pdfview::core::ViewRect visible_rect;
  visible_rect.y = 200.0f;
  visible_rect.height = 200.0f;

  pdfview::core::PageIndexRange keep_range;
  keep_range.start = 0;
  keep_range.end = 3;

  pdfview::core::PageIndexRange render_range = keep_range;

  const pdfview::core::PageRenderPlan plan =
      pdfview::core::plan_page_rendering(render_range,
                                         keep_range,
                                         states,
                                         page_frames,
                                         visible_rect,
                                         2.0f);

  return Expect(plan.render_requests.size() == 3, "all pages should be queued when scale changes") &&
         Expect(plan.render_requests[0].page_index == 1, "visible-center page should render first") &&
         Expect(plan.render_requests[1].page_index == 0, "tie should prefer lower page index") &&
         Expect(plan.pages_to_discard.empty(), "no pages should be discarded inside keep range");
}

bool TestHigherScaleCacheCoversLowerScaleTarget() {
  std::vector<pdfview::core::PageCacheSlotState> states =
      pdfview::core::make_page_cache_states(2);
  pdfview::core::mark_page_cache_rendered(&states, 0, 2.0f);
  pdfview::core::mark_page_cache_requested(&states, 1, 2.0f);

  pdfview::core::PageIndexRange keep_range;
  keep_range.start = 0;
  keep_range.end = 2;

  const pdfview::core::PageCacheUpdate update =
      pdfview::core::plan_page_cache_update(keep_range, states, 1.0f);

  return Expect(update.pages_to_render.empty(),
                "higher-scale loaded or pending pages should satisfy a lower-scale target") &&
         Expect(update.pages_to_discard.empty(),
                "pages inside keep range should not be discarded when covered by higher scale");
}

bool TestDocumentViewModel() {
  std::vector<pdfview::core::PageSize> page_sizes(3);
  page_sizes[0].width = 400.0f;
  page_sizes[0].height = 400.0f;
  page_sizes[1].width = 400.0f;
  page_sizes[1].height = 400.0f;
  page_sizes[2].width = 400.0f;
  page_sizes[2].height = 400.0f;

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.set_viewport_size(500.0f, 300.0f);
  view_model.set_device_scale(2.0f);
  view_model.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::FitWidth;
  view_model.relayout();

  const float expected_scale = (500.0f - 48.0f) / 400.0f;
  const pdfview::core::ViewRect first_rect = view_model.current_page_rect();

  view_model.mutable_view_state()->scroll_y = 520.0f;
  view_model.update_current_page_from_scroll();
  const pdfview::core::PageRenderPlan render_plan = view_model.page_render_plan();

  return Expect(NearlyEqual(view_model.current_logical_scale(), expected_scale), "view model fit scale is incorrect") &&
         Expect(NearlyEqual(view_model.current_render_scale(), expected_scale * 2.0f), "view model render scale is incorrect") &&
         Expect(NearlyEqual(first_rect.y, 20.0f), "current page rect before scrolling is incorrect") &&
         Expect(view_model.view_state().current_page == 1, "view model current page tracking is incorrect") &&
         Expect(!render_plan.render_requests.empty(), "view model should request visible page rendering");
}

bool TestFitPageScale() {
  std::vector<pdfview::core::PageSize> page_sizes(2);
  page_sizes[0].width = 400.0f;
  page_sizes[0].height = 800.0f;
  page_sizes[1].width = 600.0f;
  page_sizes[1].height = 300.0f;

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.set_viewport_size(500.0f, 300.0f);
  view_model.mutable_view_state()->current_page = 0;
  view_model.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::FitPage;

  return Expect(NearlyEqual(view_model.fit_page_scale(), 252.0f / 800.0f),
                "fit page scale should clamp to viewport height for tall pages") &&
         Expect(NearlyEqual(view_model.current_logical_scale(), 252.0f / 800.0f),
                "current scale should use fit page mode");
}

bool TestPageCachePlanKeepsNeighborPages() {
  std::vector<pdfview::core::ViewRect> page_frames(5);
  for (int index = 0; index < 5; ++index) {
    page_frames[index].x = 0.0f;
    page_frames[index].y = 20.0f + index * 220.0f;
    page_frames[index].width = 100.0f;
    page_frames[index].height = 200.0f;
  }

  pdfview::core::ViewRect visible_rect;
  visible_rect.x = 0.0f;
  visible_rect.y = 230.0f;
  visible_rect.width = 100.0f;
  visible_rect.height = 200.0f;

  const pdfview::core::PageCachePlan plan =
      pdfview::core::compute_page_cache_plan(page_frames, visible_rect, 100.0f);

  return Expect(plan.visible_range.start == 1 && plan.visible_range.end == 2,
                "visible range should contain the centered page") &&
         Expect(plan.preload_range.start == 0 && plan.preload_range.end == 3,
                "preload range should expand by viewport margin") &&
         Expect(plan.keep_range.start == 0 && plan.keep_range.end == 4,
                "keep range should retain one extra page on both sides");
}

}  // namespace

int main() {
  if (!TestComputeFitScale()) {
    return 1;
  }
  if (!TestContinuousLayout()) {
    return 1;
  }
  if (!TestNearestPageSelection()) {
    return 1;
  }
  if (!TestPageRenderPlanOrdering()) {
    return 1;
  }
  if (!TestHigherScaleCacheCoversLowerScaleTarget()) {
    return 1;
  }
  if (!TestDocumentViewModel()) {
    return 1;
  }
  if (!TestPageCachePlanKeepsNeighborPages()) {
    return 1;
  }
  if (!TestFitPageScale()) {
    return 1;
  }
  return 0;
}
