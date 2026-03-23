#include "core/page_cache.h"

#include <algorithm>
#include <cmath>

namespace pdfview {
namespace core {

std::vector<PageCacheSlotState> make_page_cache_states(int page_count) {
  return std::vector<PageCacheSlotState>(page_count);
}

void invalidate_page_cache(std::vector<PageCacheSlotState>* states) {
  if (states == NULL) {
    return;
  }

  for (size_t index = 0; index < states->size(); ++index) {
    (*states)[index].loaded = false;
    (*states)[index].pending = false;
    (*states)[index].render_scale = 0.0f;
  }
}

PageCacheUpdate plan_page_cache_update(const PageIndexRange& keep_range,
                                       const std::vector<PageCacheSlotState>& states,
                                       float target_render_scale) {
  PageCacheUpdate update;
  update.keep_range = keep_range;

  for (int page_index = 0; page_index < static_cast<int>(states.size()); ++page_index) {
    const bool in_keep_range =
        !keep_range.empty() && page_index >= keep_range.start && page_index < keep_range.end;
    const PageCacheSlotState& state = states[page_index];

    if (in_keep_range) {
      const bool loaded_at_scale = state.loaded && state.render_scale == target_render_scale;
      const bool pending_at_scale = state.pending && state.render_scale == target_render_scale;
      if (!loaded_at_scale && !pending_at_scale) {
        update.pages_to_render.push_back(page_index);
      }
      continue;
    }

    if (state.loaded || state.pending) {
      update.pages_to_discard.push_back(page_index);
    }
  }

  return update;
}

PageRenderPlan plan_page_rendering(const PageIndexRange& keep_range,
                                   const std::vector<PageCacheSlotState>& states,
                                   const std::vector<ViewRect>& page_frames,
                                   const ViewRect& visible_rect,
                                   float target_render_scale) {
  PageRenderPlan plan;
  const PageCacheUpdate update =
      plan_page_cache_update(keep_range, states, target_render_scale);
  plan.keep_range = update.keep_range;
  plan.pages_to_discard = update.pages_to_discard;

  for (size_t index = 0; index < update.pages_to_render.size(); ++index) {
    const int page_index = update.pages_to_render[index];
    if (page_index < 0 || page_index >= static_cast<int>(page_frames.size())) {
      continue;
    }

    PageRenderRequest request;
    request.page_index = page_index;
    request.render_scale = target_render_scale;
    request.display_width = page_frames[page_index].width;
    request.display_height = page_frames[page_index].height;
    plan.render_requests.push_back(request);
  }

  const float visible_center_y = visible_rect.y + visible_rect.height * 0.5f;
  std::sort(plan.render_requests.begin(),
            plan.render_requests.end(),
            [&page_frames, visible_center_y](const PageRenderRequest& lhs,
                                             const PageRenderRequest& rhs) {
              const float lhs_center_y =
                  page_frames[lhs.page_index].y + page_frames[lhs.page_index].height * 0.5f;
              const float rhs_center_y =
                  page_frames[rhs.page_index].y + page_frames[rhs.page_index].height * 0.5f;
              const float lhs_distance = std::fabs(lhs_center_y - visible_center_y);
              const float rhs_distance = std::fabs(rhs_center_y - visible_center_y);
              if (lhs_distance == rhs_distance) {
                return lhs.page_index < rhs.page_index;
              }
              return lhs_distance < rhs_distance;
            });

  return plan;
}

void mark_page_cache_rendered(std::vector<PageCacheSlotState>* states,
                              int page_index,
                              float render_scale) {
  if (states == NULL || page_index < 0 || page_index >= static_cast<int>(states->size())) {
    return;
  }

  (*states)[page_index].loaded = true;
  (*states)[page_index].pending = false;
  (*states)[page_index].render_scale = render_scale;
}

void mark_page_cache_requested(std::vector<PageCacheSlotState>* states,
                               int page_index,
                               float render_scale) {
  if (states == NULL || page_index < 0 || page_index >= static_cast<int>(states->size())) {
    return;
  }

  (*states)[page_index].loaded = false;
  (*states)[page_index].pending = true;
  (*states)[page_index].render_scale = render_scale;
}

void mark_page_cache_discarded(std::vector<PageCacheSlotState>* states, int page_index) {
  if (states == NULL || page_index < 0 || page_index >= static_cast<int>(states->size())) {
    return;
  }

  (*states)[page_index].loaded = false;
  (*states)[page_index].pending = false;
  (*states)[page_index].render_scale = 0.0f;
}

}  // namespace core
}  // namespace pdfview
