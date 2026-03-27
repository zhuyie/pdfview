#pragma once

#include <string>

#include "core/document.h"

namespace pdfview {
namespace tools {

bool write_bitmap_as_bmp(const std::string& output_path, const pdfview::core::Bitmap& bitmap);

}  // namespace tools
}  // namespace pdfview
