#include <cstdio>

#include "core/document.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <pdf>\n", argv[0]);
    return 2;
  }

  const pdfview::core::OpenDocumentResult open_result =
      pdfview::core::open_document(argv[1]);
  if (!open_result.ok()) {
    std::fprintf(stderr, "open failed: %s\n", open_result.error.c_str());
    return 1;
  }

  if (open_result.document->page_count() <= 0) {
    std::fprintf(stderr, "document has no pages\n");
    return 1;
  }

  const pdfview::core::RenderPageResult render_result =
      open_result.document->render_page(0, 1.0f);
  if (!render_result.ok()) {
    std::fprintf(stderr, "render failed: %s\n", render_result.error.c_str());
    return 1;
  }

  if (render_result.bitmap.width <= 0 ||
      render_result.bitmap.height <= 0 ||
      render_result.bitmap.pixels.empty()) {
    std::fprintf(stderr, "rendered bitmap is empty\n");
    return 1;
  }

  return 0;
}
