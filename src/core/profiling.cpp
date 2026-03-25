#include "core/profiling.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <atomic>
#include <mutex>

namespace pdfview {
namespace core {

namespace {

struct RenderProfileSummary {
  long long render_tab_count = 0;
  double render_tab_total_ms = 0.0;
  double render_tab_layout_ms = 0.0;

  long long visible_update_count = 0;
  long long visible_update_skip_count = 0;
  double visible_update_total_ms = 0.0;
  double visible_update_image_apply_ms = 0.0;
  long long visible_update_submitted_pages = 0;
  long long visible_update_discarded_pages = 0;
  long long visible_update_kept_pages = 0;
  long long visible_update_submitted_pixels = 0;

  long long page_render_count = 0;
  double page_render_pdf_ms = 0.0;
  double page_render_decode_ms = 0.0;
  double page_render_apply_ms = 0.0;
  long long page_render_pixels = 0;

  long long page_skip_count = 0;
  long long page_submit_skip_count = 0;
};

RenderProfileSummary& render_profile_summary() {
  static RenderProfileSummary* summary = new RenderProfileSummary();
  return *summary;
}

std::mutex& render_profile_summary_mutex() {
  static std::mutex* mutex = new std::mutex();
  return *mutex;
}

FILE* render_log_stream() {
  static FILE* stream = []() -> FILE* {
    const char* path = std::getenv("PDFVIEW_PROFILE_RENDER_FILE");
    if (path == NULL || path[0] == '\0') {
      return stderr;
    }

    FILE* file = std::fopen(path, "a");
    if (file == NULL) {
      return stderr;
    }
    return file;
  }();
  return stream;
}

std::atomic<bool>& render_profile_summary_flushed() {
  static std::atomic<bool>* flushed = new std::atomic<bool>(false);
  return *flushed;
}

void log_render_profile_summary() {
  flush_render_profile_summary();
}

}  // namespace

bool render_profiling_enabled() {
  static const bool enabled = []() -> bool {
    const char* value = std::getenv("PDFVIEW_PROFILE_RENDER");
    if (value != NULL && value[0] != '\0' && value[0] != '0') {
      std::atexit(log_render_profile_summary);
      return true;
    }
    return value != NULL && value[0] != '\0' && value[0] != '0';
  }();
  return enabled;
}

void render_log(const char* format, ...) {
  if (!render_profiling_enabled()) {
    return;
  }

  FILE* stream = render_log_stream();
  if (stream == NULL) {
    return;
  }

  va_list args;
  va_start(args, format);
  std::vfprintf(stream, format, args);
  va_end(args);
  std::fputc('\n', stream);
  std::fflush(stream);
}

void flush_render_profile_summary() {
  if (!render_profiling_enabled()) {
    return;
  }

  bool expected = false;
  if (!render_profile_summary_flushed().compare_exchange_strong(expected, true)) {
    return;
  }

  RenderProfileSummary snapshot;
  {
    std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
    snapshot = render_profile_summary();
  }

  render_log("[pdfview] session_summary "
             "render_tab_count=%lld render_tab_total_ms=%.2f render_tab_layout_ms=%.2f "
             "visible_update_count=%lld visible_update_skip_count=%lld "
             "visible_update_total_ms=%.2f visible_update_image_apply_ms=%.2f "
             "submitted_pages=%lld discarded_pages=%lld kept_pages=%lld submitted_pixels=%lld "
             "page_render_count=%lld page_render_pdf_ms=%.2f page_render_decode_ms=%.2f "
             "page_render_apply_ms=%.2f page_render_pixels=%lld "
             "page_skip_count=%lld page_submit_skip_count=%lld",
             snapshot.render_tab_count,
             snapshot.render_tab_total_ms,
             snapshot.render_tab_layout_ms,
             snapshot.visible_update_count,
             snapshot.visible_update_skip_count,
             snapshot.visible_update_total_ms,
             snapshot.visible_update_image_apply_ms,
             snapshot.visible_update_submitted_pages,
             snapshot.visible_update_discarded_pages,
             snapshot.visible_update_kept_pages,
             snapshot.visible_update_submitted_pixels,
             snapshot.page_render_count,
             snapshot.page_render_pdf_ms,
             snapshot.page_render_decode_ms,
             snapshot.page_render_apply_ms,
             snapshot.page_render_pixels,
             snapshot.page_skip_count,
             snapshot.page_submit_skip_count);
}

void record_render_tab_sample(double total_ms, double layout_ms) {
  if (!render_profiling_enabled()) {
    return;
  }

  std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
  RenderProfileSummary& summary = render_profile_summary();
  summary.render_tab_count += 1;
  summary.render_tab_total_ms += total_ms;
  summary.render_tab_layout_ms += layout_ms;
}

void record_visible_update_sample(double total_ms,
                                  double image_apply_ms,
                                  int submitted_pages,
                                  int discarded_pages,
                                  int kept_pages,
                                  long long submitted_pixels) {
  if (!render_profiling_enabled()) {
    return;
  }

  std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
  RenderProfileSummary& summary = render_profile_summary();
  summary.visible_update_count += 1;
  summary.visible_update_total_ms += total_ms;
  summary.visible_update_image_apply_ms += image_apply_ms;
  summary.visible_update_submitted_pages += submitted_pages;
  summary.visible_update_discarded_pages += discarded_pages;
  summary.visible_update_kept_pages += kept_pages;
  summary.visible_update_submitted_pixels += submitted_pixels;
}

void record_visible_update_skip() {
  if (!render_profiling_enabled()) {
    return;
  }

  std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
  render_profile_summary().visible_update_skip_count += 1;
}

void record_page_render_sample(double pdf_ms,
                               double decode_ms,
                               double apply_ms,
                               long long pixels) {
  if (!render_profiling_enabled()) {
    return;
  }

  std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
  RenderProfileSummary& summary = render_profile_summary();
  summary.page_render_count += 1;
  summary.page_render_pdf_ms += pdf_ms;
  summary.page_render_decode_ms += decode_ms;
  summary.page_render_apply_ms += apply_ms;
  summary.page_render_pixels += pixels;
}

void record_page_skip() {
  if (!render_profiling_enabled()) {
    return;
  }

  std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
  render_profile_summary().page_skip_count += 1;
}

void record_page_submit_skip() {
  if (!render_profiling_enabled()) {
    return;
  }

  std::lock_guard<std::mutex> lock(render_profile_summary_mutex());
  render_profile_summary().page_submit_skip_count += 1;
}

}  // namespace core
}  // namespace pdfview
