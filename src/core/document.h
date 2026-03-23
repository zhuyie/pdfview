#pragma once

#include <memory>
#include <string>
#include <vector>

namespace pdfview {
namespace core {

struct PageSize {
  float width = 0.0f;
  float height = 0.0f;
};

struct Bitmap {
  int width = 0;
  int height = 0;
  int stride = 0;
  std::vector<unsigned char> pixels;
};

struct RenderPageResult {
  Bitmap bitmap;
  std::string error;

  bool ok() const { return !bitmap.pixels.empty(); }
};

class Document {
 public:
  virtual ~Document() = default;

  virtual int page_count() const = 0;
  virtual PageSize page_size(int page_index) const = 0;
  virtual RenderPageResult render_page(int page_index, float scale) const = 0;
};

using DocumentPtr = std::shared_ptr<Document>;

struct OpenDocumentResult {
  DocumentPtr document;
  std::string error;

  bool ok() const { return static_cast<bool>(document); }
};

OpenDocumentResult open_document(const std::string& path);

}  // namespace core
}  // namespace pdfview
