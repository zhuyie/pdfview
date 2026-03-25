#pragma once

#include <vector>

#include "core/viewport.h"

namespace pdfview {
namespace core {

struct PageCacheSlotState {
  bool loaded = false;
  bool pending = false;
  float render_scale = 0.0f;
};

struct PageCacheUpdate {
  PageIndexRange keep_range;
  std::vector<int> pages_to_render;
  std::vector<int> pages_to_discard;
};

struct PageRenderRequest {
  int page_index = 0;
  float render_scale = 0.0f;
  float display_width = 0.0f;
  float display_height = 0.0f;
};

struct PageRenderPlan {
  PageIndexRange keep_range;
  std::vector<int> pages_to_discard;
  std::vector<PageRenderRequest> render_requests;
};

struct RenderPlanFingerprint {
  float render_scale = 0.0f;
  PageIndexRange visible_range;
  PageIndexRange preload_range;
  PageIndexRange keep_range;
  bool valid = false;
};

std::vector<PageCacheSlotState> make_page_cache_states(int page_count);

void invalidate_page_cache(std::vector<PageCacheSlotState>* states);

bool cache_covers_render_scale(const PageCacheSlotState& state, float target_render_scale);

bool should_submit_page_render(const PageCacheSlotState& state,
                               bool has_page_image,
                               float target_render_scale);

PageCacheUpdate plan_page_cache_update(const PageIndexRange& keep_range,
                                       const std::vector<PageCacheSlotState>& states,
                                       float target_render_scale);

PageRenderPlan plan_page_rendering(const PageIndexRange& render_range,
                                   const PageIndexRange& keep_range,
                                   const std::vector<PageCacheSlotState>& states,
                                   const std::vector<ViewRect>& page_frames,
                                   const ViewRect& visible_rect,
                                   float target_render_scale);

void mark_page_cache_rendered(std::vector<PageCacheSlotState>* states,
                              int page_index,
                              float render_scale);

void mark_page_cache_requested(std::vector<PageCacheSlotState>* states,
                               int page_index,
                               float render_scale);

void mark_page_cache_discarded(std::vector<PageCacheSlotState>* states, int page_index);

RenderPlanFingerprint render_plan_fingerprint_for_visible_update(
    const PageCachePlan& cache_plan,
    float render_scale);

bool render_plan_matches_fingerprint(const RenderPlanFingerprint& fingerprint,
                                     const PageCachePlan& cache_plan,
                                     float render_scale);

}  // namespace core
}  // namespace pdfview
