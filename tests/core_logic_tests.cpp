#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "core/document_view_model.h"
#include "core/document_paths.h"
#include "core/page_cache.h"
#include "core/recent_documents.h"
#include "core/text_selection.h"
#include "core/viewer_layout.h"
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
      : page_sizes_(page_sizes),
        page_char_counts_(page_sizes.size(), 0),
        page_range_selections_(page_sizes.size()) {}

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

  int text_index_at_point(int, float, float, float, float) const override {
    return -1;
  }

  int nearest_text_index_at_point(int, float, float) const override {
    return -1;
  }

  int page_text_char_count(int page_index) const override {
    if (page_index < 0 || page_index >= static_cast<int>(page_sizes_.size())) {
      return 0;
    }
    return page_char_counts_[page_index];
  }

  pdfview::core::PageTextSelection text_selection_for_range(int page_index,
                                                            int start_index,
                                                            int count) const override {
    if (page_index < 0 || page_index >= static_cast<int>(page_range_selections_.size())) {
      return pdfview::core::PageTextSelection();
    }
    for (size_t selection_index = 0; selection_index < page_range_selections_[page_index].size();
         ++selection_index) {
      const pdfview::core::PageTextSelection& selection =
          page_range_selections_[page_index][selection_index];
      if (selection.start_index == start_index && selection.count == count) {
        return selection;
      }
    }
    return pdfview::core::PageTextSelection();
  }

  pdfview::core::PageTextSelection word_selection_at_index(int, int) const override {
    return pdfview::core::PageTextSelection();
  }

  void set_page_text_char_count(int page_index, int count) {
    if (page_index < 0 || page_index >= static_cast<int>(page_char_counts_.size())) {
      return;
    }
    page_char_counts_[page_index] = count;
  }

  void add_page_range_selection(const pdfview::core::PageTextSelection& selection) {
    if (selection.page_index < 0 ||
        selection.page_index >= static_cast<int>(page_range_selections_.size())) {
      return;
    }
    page_range_selections_[selection.page_index].push_back(selection);
  }

 private:
  std::vector<pdfview::core::PageSize> page_sizes_;
  std::vector<int> page_char_counts_;
  std::vector<std::vector<pdfview::core::PageTextSelection> > page_range_selections_;
};

bool TestComputeFitScale() {
  const pdfview::core::ViewerLayoutMetrics& metrics =
      pdfview::core::default_viewer_layout_metrics();
  std::vector<pdfview::core::PageSize> page_sizes(2);
  page_sizes[0].width = 400.0f;
  page_sizes[1].width = 600.0f;

  const float scale = pdfview::core::compute_fit_scale(page_sizes,
                                                       800.0f,
                                                       metrics.fit_width_horizontal_padding,
                                                       metrics.minimum_fit_dimension,
                                                       metrics.minimum_fit_scale);
  return Expect(NearlyEqual(scale, (800.0f - metrics.fit_width_horizontal_padding) / 600.0f),
                "compute_fit_scale returned an unexpected value");
}

bool TestContinuousLayout() {
  const pdfview::core::ViewerLayoutMetrics& metrics =
      pdfview::core::default_viewer_layout_metrics();
  std::vector<pdfview::core::PageSize> page_sizes(2);
  page_sizes[0].width = 300.0f;
  page_sizes[0].height = 500.0f;
  page_sizes[1].width = 400.0f;
  page_sizes[1].height = 200.0f;

  pdfview::core::PageLayoutConfig config;
  config.viewport_width = 700.0f;
  config.viewport_height = 600.0f;
  config.zoom = 1.0f;
  config.top_margin = metrics.page_gap * 0.5f;
  config.side_margin = metrics.side_margin;
  config.page_gap = metrics.page_gap;

  const pdfview::core::PageLayoutResult result =
      pdfview::core::compute_continuous_page_layout(page_sizes, config);

  return Expect(result.page_frames.size() == 2, "layout should create two page frames") &&
         Expect(NearlyEqual(result.page_frames[0].x, 200.0f), "first page x is incorrect") &&
         Expect(NearlyEqual(result.page_frames[0].y, metrics.page_gap * 0.5f), "first page y is incorrect") &&
         Expect(NearlyEqual(result.page_frames[1].x, 150.0f), "second page x is incorrect") &&
         Expect(NearlyEqual(result.page_frames[1].y, 500.0f + metrics.page_gap * 0.5f + metrics.page_gap), "second page y is incorrect") &&
         Expect(NearlyEqual(result.document_height,
                            500.0f + 200.0f + metrics.page_gap * 2.0f),
                "document height is incorrect");
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

bool TestMakeTextCharRange() {
  const pdfview::core::TextCharRange forward = pdfview::core::make_text_char_range(2, 6);
  const pdfview::core::TextCharRange backward = pdfview::core::make_text_char_range(6, 2);
  const pdfview::core::TextCharRange empty = pdfview::core::make_text_char_range(3, 3);

  return Expect(forward.start_index == 2 && forward.count == 5,
                "forward drag should include both endpoints") &&
         Expect(backward.start_index == 2 && backward.count == 5,
                "backward drag should normalize to the same range") &&
         Expect(empty.empty(), "same-character drag should not create a visible selection");
}

bool TestMakeTextSelectionRange() {
  pdfview::core::TextSelectionEndpoint anchor;
  anchor.page_index = 3;
  anchor.char_index = 4;
  pdfview::core::TextSelectionEndpoint focus;
  focus.page_index = 1;
  focus.char_index = 9;

  const pdfview::core::TextSelectionRange range =
      pdfview::core::make_text_selection_range(anchor, focus);

  return Expect(range.start.page_index == 1 && range.start.char_index == 9,
                "multi-page selection range should normalize the earlier endpoint first") &&
         Expect(range.end.page_index == 3 && range.end.char_index == 4,
                "multi-page selection range should keep the later endpoint second");
}

bool TestBuildDocumentTextSelection() {
  std::vector<pdfview::core::PageSize> page_sizes(3);
  FakeDocument document(page_sizes);
  document.set_page_text_char_count(0, 6);
  document.set_page_text_char_count(1, 5);
  document.set_page_text_char_count(2, 4);

  pdfview::core::PageTextSelection first_page_selection;
  first_page_selection.page_index = 0;
  first_page_selection.start_index = 2;
  first_page_selection.count = 4;
  first_page_selection.text = "cdef";
  first_page_selection.rects.resize(1);
  document.add_page_range_selection(first_page_selection);

  pdfview::core::PageTextSelection second_page_selection;
  second_page_selection.page_index = 1;
  second_page_selection.start_index = 0;
  second_page_selection.count = 5;
  second_page_selection.text = "ghijk";
  second_page_selection.rects.resize(1);
  document.add_page_range_selection(second_page_selection);

  pdfview::core::PageTextSelection third_page_selection;
  third_page_selection.page_index = 2;
  third_page_selection.start_index = 0;
  third_page_selection.count = 2;
  third_page_selection.text = "lm";
  third_page_selection.rects.resize(1);
  document.add_page_range_selection(third_page_selection);

  pdfview::core::TextSelectionEndpoint anchor;
  anchor.page_index = 0;
  anchor.char_index = 2;
  pdfview::core::TextSelectionEndpoint focus;
  focus.page_index = 2;
  focus.char_index = 1;

  const pdfview::core::DocumentTextSelection selection =
      pdfview::core::build_document_text_selection(
          document, pdfview::core::make_text_selection_range(anchor, focus));

  return Expect(selection.text == "cdef\nghijk\nlm",
                "document text selection should join per-page text with line breaks") &&
         Expect(selection.spans.size() == 3,
                "document text selection should keep one span per selected page") &&
         Expect(selection.spans[0].page_index == 0 && selection.spans[2].page_index == 2,
                "document text selection should preserve page order");
}

bool TestResolveDocumentSelectionPoint() {
  std::vector<pdfview::core::ViewRect> page_frames(2);
  page_frames[0].x = 20.0f;
  page_frames[0].y = 40.0f;
  page_frames[0].width = 100.0f;
  page_frames[0].height = 200.0f;
  page_frames[1].x = 10.0f;
  page_frames[1].y = 280.0f;
  page_frames[1].width = 120.0f;
  page_frames[1].height = 160.0f;

  int page_index = -1;
  float page_x = 0.0f;
  float page_y = 0.0f;
  const bool resolved = pdfview::core::resolve_document_selection_point(
      75.0f, 120.0f, page_frames, &page_index, &page_x, &page_y);
  const bool rejected = !pdfview::core::resolve_document_selection_point(
      5.0f, 10.0f, page_frames, &page_index, &page_x, &page_y);

  return Expect(resolved, "document point inside a page should resolve") &&
         Expect(page_index == 0, "document point should resolve to the matching page index") &&
         Expect(NearlyEqual(page_x, 55.0f) && NearlyEqual(page_y, 80.0f),
                "document point should convert to page-local coordinates") &&
         Expect(rejected, "document point outside all pages should not resolve");
}

bool TestResolveDocumentSelectionFallback() {
  std::vector<pdfview::core::PageSize> page_sizes(3);
  FakeDocument document(page_sizes);
  document.set_page_text_char_count(0, 4);
  document.set_page_text_char_count(1, 0);
  document.set_page_text_char_count(2, 6);

  std::vector<pdfview::core::ViewRect> page_frames(3);
  page_frames[0].y = 20.0f;
  page_frames[0].height = 200.0f;
  page_frames[1].y = 260.0f;
  page_frames[1].height = 200.0f;
  page_frames[2].y = 500.0f;
  page_frames[2].height = 200.0f;

  int forward_page_index = -1;
  int forward_char_index = -1;
  const bool forward = pdfview::core::resolve_document_selection_fallback(
      470.0f, 0, page_frames, document, &forward_page_index, &forward_char_index);
  int backward_page_index = -1;
  int backward_char_index = -1;
  const bool backward = pdfview::core::resolve_document_selection_fallback(
      10.0f, 2, page_frames, document, &backward_page_index, &backward_char_index);

  return Expect(forward && forward_page_index == 2 && forward_char_index == 0,
                "forward fallback should snap to the next page start with text") &&
         Expect(backward && backward_page_index == 0 && backward_char_index == 3,
                "backward fallback should snap to the previous page end with text");
}

bool TestPageTextRectsToPageViewRects() {
  pdfview::core::PageSize page_size;
  page_size.width = 100.0f;
  page_size.height = 200.0f;

  pdfview::core::ViewRect page_frame;
  page_frame.width = 200.0f;
  page_frame.height = 400.0f;

  std::vector<pdfview::core::PageTextRect> text_rects(1);
  text_rects[0].left = 10.0f;
  text_rects[0].right = 50.0f;
  text_rects[0].top = 180.0f;
  text_rects[0].bottom = 160.0f;

  const std::vector<pdfview::core::ViewRect> view_rects =
      pdfview::core::page_text_rects_to_page_view_rects(text_rects, page_size, page_frame);

  return Expect(view_rects.size() == 1, "text rect conversion should preserve valid rects") &&
         Expect(NearlyEqual(view_rects[0].x, 20.0f), "converted text rect x is incorrect") &&
         Expect(NearlyEqual(view_rects[0].y, 40.0f), "converted text rect y is incorrect") &&
         Expect(NearlyEqual(view_rects[0].width, 80.0f), "converted text rect width is incorrect") &&
         Expect(NearlyEqual(view_rects[0].height, 40.0f), "converted text rect height is incorrect");
}

bool TestWordCharRangeFromText() {
  std::vector<unsigned int> codepoints;
  codepoints.push_back('a');
  codepoints.push_back('l');
  codepoints.push_back('p');
  codepoints.push_back('h');
  codepoints.push_back('a');
  codepoints.push_back(' ');
  codepoints.push_back('b');
  codepoints.push_back('e');
  codepoints.push_back('t');
  codepoints.push_back('a');

  const pdfview::core::TextCharRange alpha =
      pdfview::core::word_char_range_from_text(codepoints, 2);
  const pdfview::core::TextCharRange beta =
      pdfview::core::word_char_range_from_text(codepoints, 7);
  const pdfview::core::TextCharRange gap =
      pdfview::core::word_char_range_from_text(codepoints, 5);
  std::vector<unsigned int> symbol_codepoints;
  symbol_codepoints.push_back('$');
  symbol_codepoints.push_back('+');
  symbol_codepoints.push_back('+');
  symbol_codepoints.push_back(' ');
  symbol_codepoints.push_back('=');
  const pdfview::core::TextCharRange symbols =
      pdfview::core::word_char_range_from_text(symbol_codepoints, 1);
  const pdfview::core::TextCharRange equals =
      pdfview::core::word_char_range_from_text(symbol_codepoints, 4);
  std::vector<unsigned int> cjk_codepoints;
  cjk_codepoints.push_back(0x4F60);
  cjk_codepoints.push_back(0x597D);
  cjk_codepoints.push_back(0xFF0C);
  cjk_codepoints.push_back(0x4E16);
  cjk_codepoints.push_back(0x754C);
  const pdfview::core::TextCharRange cjk =
      pdfview::core::word_char_range_from_text(cjk_codepoints, 1);
  const pdfview::core::TextCharRange cjk_punctuation =
      pdfview::core::word_char_range_from_text(cjk_codepoints, 2);
  const pdfview::core::TextCharRange cjk_after_punctuation =
      pdfview::core::word_char_range_from_text(cjk_codepoints, 3);
  std::vector<unsigned int> adjacent_cjk_punctuation;
  adjacent_cjk_punctuation.push_back(0xFF09);
  adjacent_cjk_punctuation.push_back(0xFF1A);
  const pdfview::core::TextCharRange adjacent_cjk_punctuation_range =
      pdfview::core::word_char_range_from_text(adjacent_cjk_punctuation, 0);

  return Expect(alpha.start_index == 0 && alpha.count == 5,
                "word range should expand to the full leading word") &&
         Expect(beta.start_index == 6 && beta.count == 4,
                "word range should expand to the full trailing word") &&
         Expect(gap.empty(), "word range should stay empty on whitespace") &&
         Expect(symbols.start_index == 0 && symbols.count == 3,
                "ASCII punctuation should expand across adjacent symbol runs") &&
         Expect(equals.start_index == 4 && equals.count == 1,
                "standalone ASCII symbols should still be selectable") &&
         Expect(cjk.start_index == 0 && cjk.count == 2,
                "CJK text should expand until punctuation boundaries") &&
         Expect(cjk_punctuation.start_index == 2 && cjk_punctuation.count == 1,
                "CJK punctuation should be selectable as its own token") &&
         Expect(adjacent_cjk_punctuation_range.start_index == 0 &&
                    adjacent_cjk_punctuation_range.count == 1,
                "adjacent CJK punctuation marks should not merge into one selection") &&
         Expect(cjk_after_punctuation.start_index == 3 && cjk_after_punctuation.count == 2,
                "CJK punctuation should break non-ASCII word expansion");
}

bool TestThinTextRectsStayVisible() {
  pdfview::core::PageSize page_size;
  page_size.width = 100.0f;
  page_size.height = 200.0f;

  pdfview::core::ViewRect page_frame;
  page_frame.width = 100.0f;
  page_frame.height = 200.0f;

  std::vector<pdfview::core::PageTextRect> text_rects(1);
  text_rects[0].left = 10.0f;
  text_rects[0].right = 11.0f;
  text_rects[0].top = 180.0f;
  text_rects[0].bottom = 160.0f;

  const std::vector<pdfview::core::ViewRect> view_rects =
      pdfview::core::page_text_rects_to_page_view_rects(text_rects, page_size, page_frame);

  return Expect(view_rects.size() == 1, "thin text rect conversion should keep valid rects") &&
         Expect(NearlyEqual(view_rects[0].width, 5.0f), "thin text rects should get a minimum visible width");
}

bool TestThinHorizontalTextRectsStayVisible() {
  pdfview::core::PageSize page_size;
  page_size.width = 100.0f;
  page_size.height = 200.0f;

  pdfview::core::ViewRect page_frame;
  page_frame.width = 100.0f;
  page_frame.height = 200.0f;

  std::vector<pdfview::core::PageTextRect> text_rects(1);
  text_rects[0].left = 10.0f;
  text_rects[0].right = 20.0f;
  text_rects[0].top = 180.0f;
  text_rects[0].bottom = 179.0f;

  const std::vector<pdfview::core::ViewRect> view_rects =
      pdfview::core::page_text_rects_to_page_view_rects(text_rects, page_size, page_frame);

  return Expect(view_rects.size() == 1, "thin horizontal rect conversion should keep valid rects") &&
         Expect(NearlyEqual(view_rects[0].height, 5.0f), "thin horizontal rects should get a minimum visible height");
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

bool TestSameDocumentPath() {
  return Expect(pdfview::core::same_document_path("/tmp/pdfview_path_test/../smoke.pdf",
                                                  "/tmp/smoke.pdf"),
                "document path comparison should normalize equivalent paths");
}

bool TestDocumentViewModel() {
  const pdfview::core::ViewerLayoutMetrics& metrics =
      pdfview::core::default_viewer_layout_metrics();
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

  const float expected_scale = (500.0f - metrics.fit_width_horizontal_padding) / 400.0f;
  const pdfview::core::ViewRect first_rect = view_model.current_page_rect();

  view_model.mutable_view_state()->scroll_y = 520.0f;
  view_model.update_current_page_from_scroll();
  const pdfview::core::PageRenderPlan render_plan = view_model.page_render_plan();

  return Expect(NearlyEqual(view_model.current_logical_scale(), expected_scale), "view model fit scale is incorrect") &&
         Expect(NearlyEqual(view_model.current_render_scale(), expected_scale * 2.0f), "view model render scale is incorrect") &&
         Expect(NearlyEqual(first_rect.y, metrics.page_gap * 0.5f), "current page rect before scrolling is incorrect") &&
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

  return Expect(NearlyEqual(view_model.restored_scroll_y_for_anchor(anchor), 394.6667f),
                "view model should restore the captured viewport anchor after relayout");
}

bool TestDocumentViewModelScaleChangeState() {
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

  const pdfview::core::ScaleChangeState state = view_model.capture_scale_change_state();

  view_model.mutable_view_state()->zoom = 1.0f;
  view_model.relayout();

  return Expect(state.anchor_page_index == 0, "scale change state should keep the anchored page index") &&
         Expect(NearlyEqual(view_model.restored_scroll_y_for_scale_change(state), 394.6667f),
                "scale change state should restore the target scroll position after relayout") &&
         Expect(view_model.view_state().current_page == 0,
                "scale change restore should keep the current page anchored to the captured page");
}

bool TestDocumentViewModelScrollYForCurrentPage() {
  const pdfview::core::ViewerLayoutMetrics& metrics =
      pdfview::core::default_viewer_layout_metrics();
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

  const bool third_page_target =
      Expect(NearlyEqual(view_model.scroll_y_for_current_page(),
                         2.0f * ((500.0f - metrics.fit_width_horizontal_padding) + metrics.page_gap)),
             "scroll target for later pages should align above the page by the shared edge margin");

  view_model.mutable_view_state()->current_page = 0;
  const bool first_page_target =
      Expect(NearlyEqual(view_model.scroll_y_for_current_page(), 0.0f),
             "first page should align to the top of the scrollable document");

  return third_page_target && first_page_target;
}

bool TestDocumentViewModelViewportStepScroll() {
  std::vector<pdfview::core::PageSize> page_sizes(2);
  for (int index = 0; index < 2; ++index) {
    page_sizes[index].width = 400.0f;
    page_sizes[index].height = 800.0f;
  }

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.set_viewport_size(500.0f, 300.0f);
  view_model.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::Manual;
  view_model.mutable_view_state()->zoom = 1.0f;
  view_model.relayout();
  view_model.set_scroll_origin(0.0f, 100.0f);

  return Expect(NearlyEqual(view_model.scroll_y_after_viewport_step(1.0f), 370.0f),
                "viewport step should scroll by ninety percent of the viewport height") &&
         Expect(NearlyEqual(view_model.scroll_y_after_viewport_step(-1.0f), 0.0f),
                "viewport step should clamp at the document start");
}

bool TestDocumentViewModelPageIndicatorText() {
  std::vector<pdfview::core::PageSize> page_sizes(12);
  for (int index = 0; index < 12; ++index) {
    page_sizes[index].width = 400.0f;
    page_sizes[index].height = 400.0f;
  }

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.mutable_view_state()->current_page = 4;

  return Expect(view_model.page_indicator_text() == "5 / 12",
                "page indicator text should format the current page and total pages");
}

bool TestDocumentViewModelInteractiveScaleHeuristic() {
  std::vector<pdfview::core::PageSize> page_sizes(2);
  page_sizes[0].width = 1200.0f;
  page_sizes[0].height = 1800.0f;
  page_sizes[1].width = 1200.0f;
  page_sizes[1].height = 1800.0f;

  pdfview::core::DocumentPtr document(new FakeDocument(page_sizes));
  pdfview::core::DocumentViewModel view_model(document);
  view_model.set_viewport_size(1400.0f, 900.0f);
  view_model.mutable_view_state()->scale_mode = pdfview::core::ScaleMode::Manual;
  view_model.mutable_view_state()->zoom = 1.0f;
  view_model.relayout();
  view_model.set_scroll_origin(0.0f, 0.0f);

  return Expect(view_model.should_reduce_interactive_scale(2.0f),
                "interactive scale heuristic should downscale large high-DPI pages") &&
         Expect(!view_model.should_reduce_interactive_scale(1.0f),
                "interactive scale heuristic should not trigger at 1x device scale");
}

bool TestFitPageScale() {
  const pdfview::core::ViewerLayoutMetrics& metrics =
      pdfview::core::default_viewer_layout_metrics();
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

  return Expect(NearlyEqual(view_model.fit_page_scale(),
                            (300.0f - metrics.fit_page_vertical_padding) / 800.0f),
                "fit page scale should clamp to viewport height for tall pages") &&
         Expect(NearlyEqual(view_model.current_logical_scale(),
                            (300.0f - metrics.fit_page_vertical_padding) / 800.0f),
                "current scale should use fit page mode");
}

bool TestViewerBehaviorMetricsDefaults() {
  const pdfview::core::ViewerBehaviorMetrics& behavior =
      pdfview::core::default_viewer_behavior_metrics();

  return Expect(NearlyEqual(behavior.preload_margin_viewport_ratio, 0.5f),
                "preload margin ratio should match the shared viewer behavior metrics") &&
         Expect(behavior.keep_extra_pages_before == 1,
                "keep range should retain one page before the preload range by default") &&
         Expect(behavior.keep_extra_pages_after == 1,
                "keep range should retain one page after the preload range by default") &&
         Expect(NearlyEqual(behavior.viewport_step_min, 80.0f),
                "viewport step minimum should match the shared viewer behavior metrics") &&
         Expect(NearlyEqual(behavior.viewport_step_ratio, 0.9f),
                "viewport step ratio should match the shared viewer behavior metrics") &&
         Expect(NearlyEqual(behavior.interactive_scale_max_page_pixels, 2500000.0f),
                "interactive page pixel threshold should match the shared viewer behavior metrics") &&
         Expect(NearlyEqual(behavior.interactive_scale_total_visible_pixels, 5000000.0f),
                "interactive total pixel threshold should match the shared viewer behavior metrics") &&
         Expect(NearlyEqual(behavior.cache_covering_scale_ratio, 1.5f),
                "covering scale ratio should match the shared viewer behavior metrics") &&
         Expect(NearlyEqual(behavior.float_epsilon, 0.001f),
                "float epsilon should match the shared viewer behavior metrics");
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
  if (!TestMakeTextCharRange()) {
    return 1;
  }
  if (!TestMakeTextSelectionRange()) {
    return 1;
  }
  if (!TestBuildDocumentTextSelection()) {
    return 1;
  }
  if (!TestResolveDocumentSelectionPoint()) {
    return 1;
  }
  if (!TestResolveDocumentSelectionFallback()) {
    return 1;
  }
  if (!TestPageTextRectsToPageViewRects()) {
    return 1;
  }
  if (!TestWordCharRangeFromText()) {
    return 1;
  }
  if (!TestThinTextRectsStayVisible()) {
    return 1;
  }
  if (!TestThinHorizontalTextRectsStayVisible()) {
    return 1;
  }
  if (!TestRecentDocumentDeduplication()) {
    return 1;
  }
  if (!TestRecentDocumentEscapeRoundTrip()) {
    return 1;
  }
  if (!TestSameDocumentPath()) {
    return 1;
  }
  if (!TestDocumentViewModel()) {
    return 1;
  }
  if (!TestDocumentViewModelViewportAnchorRestore()) {
    return 1;
  }
  if (!TestDocumentViewModelScaleChangeState()) {
    return 1;
  }
  if (!TestDocumentViewModelScrollYForCurrentPage()) {
    return 1;
  }
  if (!TestDocumentViewModelViewportStepScroll()) {
    return 1;
  }
  if (!TestDocumentViewModelPageIndicatorText()) {
    return 1;
  }
  if (!TestDocumentViewModelInteractiveScaleHeuristic()) {
    return 1;
  }
  if (!TestPageCachePlanKeepsNeighborPages()) {
    return 1;
  }
  if (!TestFitPageScale()) {
    return 1;
  }
  if (!TestViewerBehaviorMetricsDefaults()) {
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
