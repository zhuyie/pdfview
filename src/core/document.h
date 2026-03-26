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

struct PageTextRect {
  float left = 0.0f;
  float top = 0.0f;
  float right = 0.0f;
  float bottom = 0.0f;
};

struct PageTextSelection {
  int page_index = -1;
  int start_index = -1;
  int count = 0;
  std::string text;
  std::vector<PageTextRect> rects;

  bool ok() const { return page_index >= 0 && start_index >= 0 && count > 0; }
};

class Document {
 public:
  virtual ~Document() = default;

  virtual int page_count() const = 0;
  virtual PageSize page_size(int page_index) const = 0;
  virtual RenderPageResult render_page(int page_index, float scale) const = 0;
  virtual int text_index_at_point(int page_index,
                                  float page_x,
                                  float page_y,
                                  float x_tolerance,
                                  float y_tolerance) const = 0;
  virtual PageTextSelection text_selection_for_range(int page_index,
                                                     int start_index,
                                                     int count) const = 0;
  virtual PageTextSelection word_selection_at_index(int page_index, int char_index) const = 0;
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
