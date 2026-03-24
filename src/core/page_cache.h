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

std::vector<PageCacheSlotState> make_page_cache_states(int page_count);

void invalidate_page_cache(std::vector<PageCacheSlotState>* states);

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

}  // namespace core
}  // namespace pdfview
