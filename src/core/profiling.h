#pragma once

namespace pdfview {
namespace core {

bool render_profiling_enabled();

void render_log(const char* format, ...);
void flush_render_profile_summary();
void record_render_tab_sample(double total_ms, double layout_ms);
void record_visible_update_sample(double total_ms,
                                  double image_apply_ms,
                                  int submitted_pages,
                                  int discarded_pages,
                                  int kept_pages,
                                  long long submitted_pixels);
void record_visible_update_skip();
void record_page_render_sample(double pdf_ms,
                               double decode_ms,
                               double apply_ms,
                               long long pixels);
void record_page_skip();
void record_page_submit_skip();

}  // namespace core
}  // namespace pdfview
