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

struct PageTextSelectionSpan {
  int page_index = -1;
  std::vector<PageTextRect> rects;
};

struct DocumentSummaryInfo {
  std::string title;
  std::string author;
  std::string subject;
  std::string keywords;
  std::string creator;
  std::string producer;
  std::string creation_date;
  std::string mod_date;
};

struct DocumentPermissionsInfo {
  bool can_print = false;
  bool can_print_high_quality = false;
  bool can_modify = false;
  bool can_copy = false;
  bool can_annotate = false;
  bool can_fill_forms = false;
  bool can_copy_for_accessibility = false;
  bool can_assemble = false;
};

struct DocumentInfo {
  std::string pdf_version;
  unsigned long permissions = 0;
  unsigned long user_permissions = 0;
  int security_handler_revision = -1;
  DocumentPermissionsInfo permissions_info;
  DocumentPermissionsInfo user_permissions_info;
  DocumentSummaryInfo summary_info;
};

class Document {
 public:
  virtual ~Document() = default;

  virtual DocumentInfo info() const = 0;
  virtual int page_count() const = 0;
  virtual PageSize page_size(int page_index) const = 0;
  virtual RenderPageResult render_page(int page_index, float scale) const = 0;
  virtual int text_index_at_point(int page_index,
                                  float page_x,
                                  float page_y,
                                  float x_tolerance,
                                  float y_tolerance) const = 0;
  virtual int nearest_text_index_at_point(int page_index, float page_x, float page_y) const = 0;
  virtual int page_text_char_count(int page_index) const = 0;
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
