#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "core/document_view_model.h"
#include "core/page_cache.h"
#include "core/recent_documents.h"
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
  pdfview::core::mark_page_cache_rendered(&states, 0, 1.4f);
  pdfview::core::mark_page_cache_requested(&states, 1, 1.4f);

  pdfview::core::PageIndexRange keep_range;
  keep_range.start = 0;
  keep_range.end = 2;

  const pdfview::core::PageCacheUpdate update =
      pdfview::core::plan_page_cache_update(keep_range, states, 1.0f);

  return Expect(update.pages_to_render.empty(),
                "slightly higher-scale loaded or pending pages should satisfy a lower-scale target") &&
         Expect(update.pages_to_discard.empty(),
                "pages inside keep range should not be discarded when covered by higher scale");
}

bool TestOverlargeScaleTriggersDownsampleRerender() {
  std::vector<pdfview::core::PageCacheSlotState> states =
      pdfview::core::make_page_cache_states(1);
  pdfview::core::mark_page_cache_rendered(&states, 0, 3.0f);

  pdfview::core::PageIndexRange keep_range;
  keep_range.start = 0;
  keep_range.end = 1;

  const pdfview::core::PageCacheUpdate update =
      pdfview::core::plan_page_cache_update(keep_range, states, 1.0f);

  return Expect(update.pages_to_render.size() == 1 && update.pages_to_render[0] == 0,
                "significantly oversized cached pages should be rerendered at a lower scale");
}

bool TestShouldSubmitPageRender() {
  pdfview::core::PageCacheSlotState state;
  state.pending = true;
  state.render_scale = 1.4f;
  const bool skip_pending_cover =
      !pdfview::core::should_submit_page_render(state, false, 1.0f);

  state.pending = false;
  state.loaded = true;
  const bool skip_loaded_cover =
      !pdfview::core::should_submit_page_render(state, true, 1.0f);
  const bool rerender_without_image =
      pdfview::core::should_submit_page_render(state, false, 1.0f);

  state.render_scale = 3.0f;
  const bool rerender_oversized =
      pdfview::core::should_submit_page_render(state, true, 1.0f);

  return Expect(skip_pending_cover,
                "pending pages at a covering scale should not be resubmitted") &&
         Expect(skip_loaded_cover,
                "loaded pages with an image at a covering scale should not rerender") &&
         Expect(rerender_without_image,
                "loaded pages without an image should still be renderable") &&
         Expect(rerender_oversized,
                "significantly oversized cached pages should rerender after zooming out");
}

bool TestRenderPlanFingerprint() {
  pdfview::core::PageCachePlan plan;
  plan.visible_range.start = 1;
  plan.visible_range.end = 3;
  plan.preload_range.start = 0;
  plan.preload_range.end = 4;
  plan.keep_range.start = 0;
  plan.keep_range.end = 5;

  const pdfview::core::RenderPlanFingerprint fingerprint =
      pdfview::core::render_plan_fingerprint_for_visible_update(plan, 2.0f);
  const bool matches_same =
      pdfview::core::render_plan_matches_fingerprint(fingerprint, plan, 2.0f);
  const bool rejects_other_scale =
      !pdfview::core::render_plan_matches_fingerprint(fingerprint, plan, 1.0f);

  plan.keep_range.end = 4;
  const bool rejects_other_keep =
      !pdfview::core::render_plan_matches_fingerprint(fingerprint, plan, 2.0f);

  return Expect(matches_same, "matching cache plans should hit the same fingerprint") &&
         Expect(rejects_other_scale, "fingerprints should include render scale") &&
         Expect(rejects_other_keep, "fingerprints should include keep range");
}

bool TestRecentDocumentDeduplication() {
  std::vector<std::string> current_paths;
  current_paths.push_back("/tmp/a.pdf");
  current_paths.push_back("/tmp/b.pdf");
  current_paths.push_back("/tmp/c.pdf");

  const std::vector<std::string> updated_paths =
      pdfview::core::note_recent_document(current_paths, "/tmp/b.pdf", 3);

  return Expect(updated_paths.size() == 3, "recent document list should keep its max size") &&
         Expect(updated_paths[0] == "/tmp/b.pdf", "reopened document should move to the front") &&
         Expect(updated_paths[1] == "/tmp/a.pdf", "older documents should keep order after deduplication") &&
         Expect(updated_paths[2] == "/tmp/c.pdf", "non-reopened documents should remain after deduplication");
}

bool TestRecentDocumentEscapeRoundTrip() {
#if defined(_WIN32)
  _putenv_s("PDFVIEW_CONFIG_DIR", "C:\\temp\\pdfview_test_recent");
#else
  setenv("PDFVIEW_CONFIG_DIR", "/tmp/pdfview_test_recent", 1);
#endif

  std::vector<std::string> document_paths;
  document_paths.push_back("/tmp/normal.pdf");
  document_paths.push_back("/tmp/line\nbreak.pdf");

  const bool saved = pdfview::core::save_recent_documents(document_paths);
  const std::vector<std::string> loaded = pdfview::core::load_recent_documents();

  return Expect(saved, "recent document list should save successfully") &&
         Expect(loaded.size() >= 2, "saved recent documents should load back") &&
         Expect(loaded[0] == "/tmp/normal.pdf", "recent document loader should preserve normal paths") &&
         Expect(loaded[1] == "/tmp/line\nbreak.pdf", "recent document loader should preserve escaped newlines");
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

bool TestDocumentViewModelViewportAnchorRestore() {
  std::vector<pdfview::core::PageSize> page_sizes(1);
  page_sizes[0].width = 400.0f;
  page_sizes[0].height = 1200.0f;

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.set_viewport_size(500.0f, 300.0f);
  view_model.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::Manual;
  view_model.mutable_view_state()->zoom = 3.0f;
  view_model.relayout();
  view_model.set_scroll_origin(0.0f, 1160.0f);

  const pdfview::core::ViewportAnchor anchor = view_model.capture_viewport_anchor();

  view_model.mutable_view_state()->zoom = 1.0f;
  view_model.relayout();

  return Expect(NearlyEqual(view_model.restored_scroll_y_for_anchor(anchor), 400.0f),
                "view model should restore the captured viewport anchor after relayout");
}

bool TestDocumentViewModelScrollYForCurrentPage() {
  std::vector<pdfview::core::PageSize> page_sizes(3);
  for (int index = 0; index < 3; ++index) {
    page_sizes[index].width = 400.0f;
    page_sizes[index].height = 400.0f;
  }

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.set_viewport_size(500.0f, 300.0f);
  view_model.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::FitWidth;
  view_model.mutable_view_state()->current_page = 2;
  view_model.relayout();

  return Expect(NearlyEqual(view_model.scroll_y_for_current_page(), 972.0f),
                "scroll target for the current page should align to the page top and clamp to the document");
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

bool TestViewportTopPageSelection() {
  std::vector<pdfview::core::ViewRect> page_frames(3);
  page_frames[0].y = 20.0f;
  page_frames[0].height = 300.0f;
  page_frames[1].y = 344.0f;
  page_frames[1].height = 300.0f;
  page_frames[2].y = 668.0f;
  page_frames[2].height = 300.0f;

  return Expect(pdfview::core::find_page_at_viewport_top(page_frames, 310.0f) == 0,
                "viewport top near the end of a page should still anchor to that page") &&
         Expect(pdfview::core::find_page_at_viewport_top(page_frames, 332.0f) == 0,
                "viewport top inside the gap should prefer the previous nearby page") &&
         Expect(pdfview::core::find_page_at_viewport_top(page_frames, 360.0f) == 1,
                "viewport top inside the next page should anchor to that page");
}

bool TestZoomAnchorRatioPreservesViewportTopOffset() {
  std::vector<pdfview::core::ViewRect> old_page_frames(1);
  old_page_frames[0].y = 3440.0f;
  old_page_frames[0].height = 1200.0f;

  const pdfview::core::ViewportAnchor anchor =
      pdfview::core::capture_viewport_anchor(old_page_frames, 4580.0f);

  std::vector<pdfview::core::ViewRect> new_page_frames(1);
  new_page_frames[0].y = 1980.0f;
  new_page_frames[0].height = 400.0f;

  const float new_viewport_top =
      pdfview::core::restore_viewport_anchor(anchor, new_page_frames, 300.0f, 5000.0f);
  return Expect(anchor.page_index == 0, "captured anchor should keep the original page index") &&
         Expect(NearlyEqual(anchor.offset_y, 1140.0f),
                "captured anchor should keep the old viewport top offset inside the page") &&
         Expect(anchor.offset_scales_with_page,
                "captured anchor inside the page should scale with the page height") &&
         Expect(NearlyEqual(new_viewport_top, 2360.0f),
                "restored viewport top should preserve the same relative position inside the page");
}

bool TestZoomAnchorPreservesTopMarginGap() {
  std::vector<pdfview::core::ViewRect> old_page_frames(1);
  old_page_frames[0].y = 20.0f;
  old_page_frames[0].height = 900.0f;

  const pdfview::core::ViewportAnchor anchor =
      pdfview::core::capture_viewport_anchor(old_page_frames, 0.0f);

  std::vector<pdfview::core::ViewRect> new_page_frames(1);
  new_page_frames[0].y = 20.0f;
  new_page_frames[0].height = 400.0f;

  const float new_viewport_top =
      pdfview::core::restore_viewport_anchor(anchor, new_page_frames, 300.0f, 3000.0f);
  return Expect(!anchor.offset_scales_with_page,
                "captured anchor above the page should preserve an absolute gap") &&
         Expect(NearlyEqual(anchor.offset_y, -20.0f),
                "captured top margin gap should keep the absolute offset") &&
         Expect(NearlyEqual(new_viewport_top, 0.0f),
                "restored viewport top should preserve the original top margin gap");
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
  if (!TestOverlargeScaleTriggersDownsampleRerender()) {
    return 1;
  }
  if (!TestShouldSubmitPageRender()) {
    return 1;
  }
  if (!TestRenderPlanFingerprint()) {
    return 1;
  }
  if (!TestRecentDocumentDeduplication()) {
    return 1;
  }
  if (!TestRecentDocumentEscapeRoundTrip()) {
    return 1;
  }
  if (!TestDocumentViewModel()) {
    return 1;
  }
  if (!TestDocumentViewModelViewportAnchorRestore()) {
    return 1;
  }
  if (!TestDocumentViewModelScrollYForCurrentPage()) {
    return 1;
  }
  if (!TestPageCachePlanKeepsNeighborPages()) {
    return 1;
  }
  if (!TestFitPageScale()) {
    return 1;
  }
  if (!TestViewportTopPageSelection()) {
    return 1;
  }
  if (!TestZoomAnchorRatioPreservesViewportTopOffset()) {
    return 1;
  }
  if (!TestZoomAnchorPreservesTopMarginGap()) {
    return 1;
  }
  return 0;
}
