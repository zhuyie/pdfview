#include "render_page_command.h"

#include <iostream>
#include <string>
#include <vector>

#include "core/document.h"
#include "args.h"
#include "bitmap_writer.h"

namespace pdfview {
namespace tools {

namespace {

int RunRenderPage(const std::vector<std::string>& args) {
  std::string input_path;
  std::string output_path;
  int page_index = -1;
  float scale = 1.0f;

  for (size_t i = 0; i < args.size(); ++i) {
    const std::string& argument = args[i];
    if ((argument == "--input" || argument == "-i") && i + 1 < args.size()) {
      input_path = args[++i];
      continue;
    }
    if ((argument == "--output" || argument == "-o") && i + 1 < args.size()) {
      output_path = args[++i];
      continue;
    }
    if ((argument == "--page" || argument == "-p") && i + 1 < args.size()) {
      if (!parse_int_arg(args[++i], &page_index)) {
        std::cerr << "invalid page index\n";
        return 2;
      }
      continue;
    }
    if ((argument == "--scale" || argument == "-s") && i + 1 < args.size()) {
      if (!parse_float_arg(args[++i], &scale)) {
        std::cerr << "invalid scale\n";
        return 2;
      }
      continue;
    }

    std::cerr << "unknown argument: " << argument << "\n";
    return 2;
  }

  if (input_path.empty() || output_path.empty() || page_index < 0) {
    return 2;
  }

  if (scale <= 0.0f) {
    std::cerr << "scale must be > 0\n";
    return 2;
  }

  const pdfview::core::OpenDocumentResult open_result =
      pdfview::core::open_document(input_path);
  if (!open_result.ok()) {
    std::cerr << "open failed: " << open_result.error << "\n";
    return 1;
  }

  const int page_count = open_result.document->page_count();
  if (page_index >= page_count) {
    std::cerr << "page index out of range: " << page_index
              << " (page_count=" << page_count << ")\n";
    return 1;
  }

  const pdfview::core::RenderPageResult render_result =
      open_result.document->render_page(page_index, scale);
  if (!render_result.ok()) {
    std::cerr << "render failed: " << render_result.error << "\n";
    return 1;
  }

  if (!write_bitmap_as_bmp(output_path, render_result.bitmap)) {
    std::cerr << "failed to write bmp: " << output_path << "\n";
    return 1;
  }

  std::cout << "rendered " << input_path
            << " page=" << page_index
            << " scale=" << scale
            << " size=" << render_result.bitmap.width << "x" << render_result.bitmap.height
            << " output=" << output_path << "\n";
  return 0;
}

}  // namespace

const DebugCommand& render_page_command() {
  static const DebugCommand command = {
      "render-page",
      "render-page --input <pdf> --page <index> [--scale <factor>] --output <bmp>",
      &RunRenderPage,
  };
  return command;
}

}  // namespace tools
}  // namespace pdfview
