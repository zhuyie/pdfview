#include "core/page_cache.h"

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
      if (!state.loaded || state.render_scale != target_render_scale) {
        update.pages_to_render.push_back(page_index);
      }
      continue;
    }

    if (state.loaded) {
      update.pages_to_discard.push_back(page_index);
    }
  }

  return update;
}

void mark_page_cache_rendered(std::vector<PageCacheSlotState>* states,
                              int page_index,
                              float render_scale) {
  if (states == NULL || page_index < 0 || page_index >= static_cast<int>(states->size())) {
    return;
  }

  (*states)[page_index].loaded = true;
  (*states)[page_index].render_scale = render_scale;
}

void mark_page_cache_discarded(std::vector<PageCacheSlotState>* states, int page_index) {
  if (states == NULL || page_index < 0 || page_index >= static_cast<int>(states->size())) {
    return;
  }

  (*states)[page_index].loaded = false;
  (*states)[page_index].render_scale = 0.0f;
}

}  // namespace core
}  // namespace pdfview
