#include "core/pdfium_document.h"

#include <codecvt>
#include <cmath>
#include <locale>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "fpdf_doc.h"
#include "core/text_selection.h"
#include "fpdf_edit.h"
#include "fpdf_text.h"
#include "fpdfview.h"

namespace pdfview {
namespace core {

namespace {

class PdfiumLibrary {
 public:
  PdfiumLibrary() {
    FPDF_LIBRARY_CONFIG config{};
    config.version = 2;
    FPDF_InitLibraryWithConfig(&config);
  }

  ~PdfiumLibrary() { FPDF_DestroyLibrary(); }
};

PdfiumLibrary& pdfium_library() {
  static PdfiumLibrary library;
  return library;
}

std::string Utf16ToUtf8(const std::vector<unsigned short>& text);

std::string ReadMetaText(FPDF_DOCUMENT document, const char* tag) {
  const unsigned long byte_count = FPDF_GetMetaText(document, tag, NULL, 0);
  if (byte_count < 2) {
    return std::string();
  }

  std::vector<unsigned short> buffer(byte_count / 2, 0);
  if (FPDF_GetMetaText(document, tag, &buffer[0], byte_count) != byte_count) {
    return std::string();
  }
  return Utf16ToUtf8(buffer);
}

std::string FormatPdfVersion(int version) {
  if (version < 10) {
    return std::string();
  }
  return std::to_string(version / 10) + "." + std::to_string(version % 10);
}

bool IsPermissionBitEnabled(unsigned long permissions, int bit_position) {
  if (bit_position <= 0 || bit_position > 32) {
    return false;
  }
  return (permissions & (1UL << (bit_position - 1))) != 0;
}

DocumentPermissionsInfo DecodePermissions(unsigned long permissions, int revision) {
  DocumentPermissionsInfo decoded;
  decoded.can_print = IsPermissionBitEnabled(permissions, 3);
  decoded.can_modify = IsPermissionBitEnabled(permissions, 4);
  decoded.can_copy = IsPermissionBitEnabled(permissions, 5);
  decoded.can_annotate = IsPermissionBitEnabled(permissions, 6);

  if (revision >= 3) {
    decoded.can_fill_forms = IsPermissionBitEnabled(permissions, 9);
    decoded.can_copy_for_accessibility = IsPermissionBitEnabled(permissions, 10);
    decoded.can_assemble = IsPermissionBitEnabled(permissions, 11);
    decoded.can_print_high_quality =
        decoded.can_print && IsPermissionBitEnabled(permissions, 12);
  } else {
    decoded.can_fill_forms = decoded.can_annotate;
    decoded.can_copy_for_accessibility = decoded.can_copy;
    decoded.can_assemble = decoded.can_modify;
    decoded.can_print_high_quality = decoded.can_print;
  }

  return decoded;
}

class ScopedPdfPage {
 public:
  ScopedPdfPage(FPDF_DOCUMENT document, int page_index)
      : handle_(document != NULL ? FPDF_LoadPage(document, page_index) : NULL) {}

  ~ScopedPdfPage() {
    if (handle_ != NULL) {
      FPDF_ClosePage(handle_);
    }
  }

  FPDF_PAGE get() const { return handle_; }

 private:
  FPDF_PAGE handle_ = NULL;
};

class ScopedPdfTextPage {
 public:
  explicit ScopedPdfTextPage(FPDF_PAGE page)
      : handle_(page != NULL ? FPDFText_LoadPage(page) : NULL) {}

  ~ScopedPdfTextPage() {
    if (handle_ != NULL) {
      FPDFText_ClosePage(handle_);
    }
  }

  FPDF_TEXTPAGE get() const { return handle_; }

 private:
  FPDF_TEXTPAGE handle_ = NULL;
};

std::string Utf16ToUtf8(const std::vector<unsigned short>& text) {
  std::u16string utf16;
  for (size_t index = 0; index < text.size() && text[index] != 0; ++index) {
    utf16.push_back(static_cast<char16_t>(text[index]));
  }

  std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
  return converter.to_bytes(utf16);
}

std::vector<unsigned int> LoadPageCodepoints(FPDF_TEXTPAGE text_page, int char_count) {
  std::vector<unsigned int> codepoints;
  if (char_count <= 0) {
    return codepoints;
  }

  codepoints.resize(static_cast<size_t>(char_count), 0);
  for (int index = 0; index < char_count; ++index) {
    codepoints[index] = FPDFText_GetUnicode(text_page, index);
  }
  return codepoints;
}

struct TextCharBox {
  int index = -1;
  double left = 0.0;
  double right = 0.0;
  double bottom = 0.0;
  double top = 0.0;
};

struct TextLineSpan {
  int start_index = -1;
  int end_index = -1;
  double left = 0.0;
  double right = 0.0;
  double bottom = 0.0;
  double top = 0.0;
};

bool CharBoxesBelongToSameLine(const TextCharBox& lhs, const TextCharBox& rhs) {
  const double overlap = std::min(lhs.top, rhs.top) - std::max(lhs.bottom, rhs.bottom);
  const double lhs_height = std::max(lhs.top - lhs.bottom, 0.0);
  const double rhs_height = std::max(rhs.top - rhs.bottom, 0.0);
  const double min_height = std::min(lhs_height, rhs_height);
  if (min_height > 0.0 && overlap >= min_height * 0.5) {
    return true;
  }

  const double lhs_center_y = (lhs.top + lhs.bottom) * 0.5;
  const double rhs_center_y = (rhs.top + rhs.bottom) * 0.5;
  const double avg_height = (lhs_height + rhs_height) * 0.5;
  return avg_height > 0.0 && std::fabs(lhs_center_y - rhs_center_y) <= avg_height * 0.6;
}

std::vector<TextCharBox> LoadPageCharBoxes(FPDF_TEXTPAGE text_page, int char_count) {
  std::vector<TextCharBox> char_boxes;
  if (char_count <= 0) {
    return char_boxes;
  }

  char_boxes.reserve(static_cast<size_t>(char_count));
  for (int index = 0; index < char_count; ++index) {
    TextCharBox char_box;
    char_box.index = index;
    if (!FPDFText_GetCharBox(text_page,
                             index,
                             &char_box.left,
                             &char_box.right,
                             &char_box.bottom,
                             &char_box.top)) {
      continue;
    }
    if (char_box.right < char_box.left) {
      std::swap(char_box.left, char_box.right);
    }
    if (char_box.top < char_box.bottom) {
      std::swap(char_box.top, char_box.bottom);
    }
    char_boxes.push_back(char_box);
  }

  return char_boxes;
}

std::vector<TextLineSpan> BuildTextLineSpans(const std::vector<TextCharBox>& char_boxes) {
  std::vector<TextLineSpan> line_spans;
  for (size_t index = 0; index < char_boxes.size(); ++index) {
    const TextCharBox& char_box = char_boxes[index];
    if (line_spans.empty() ||
        !CharBoxesBelongToSameLine(char_boxes[index - 1], char_box)) {
      TextLineSpan line_span;
      line_span.start_index = char_box.index;
      line_span.end_index = char_box.index;
      line_span.left = char_box.left;
      line_span.right = char_box.right;
      line_span.bottom = char_box.bottom;
      line_span.top = char_box.top;
      line_spans.push_back(line_span);
      continue;
    }

    TextLineSpan& line_span = line_spans.back();
    line_span.end_index = char_box.index;
    line_span.left = std::min(line_span.left, char_box.left);
    line_span.right = std::max(line_span.right, char_box.right);
    line_span.bottom = std::min(line_span.bottom, char_box.bottom);
    line_span.top = std::max(line_span.top, char_box.top);
  }

  return line_spans;
}

double VerticalDistanceToLine(const TextLineSpan& line_span, double page_y) {
  if (page_y >= line_span.bottom && page_y <= line_span.top) {
    return 0.0;
  }
  if (page_y > line_span.top) {
    return page_y - line_span.top;
  }
  return line_span.bottom - page_y;
}

class PdfiumDocument final : public Document {
 public:
  PdfiumDocument(const std::string& path, FPDF_DOCUMENT handle) : path_(path), handle_(handle) {}

  ~PdfiumDocument() override {
    if (handle_ != nullptr) {
      FPDF_CloseDocument(handle_);
    }
  }

  DocumentInfo info() const override {
    std::lock_guard<std::mutex> lock(mutex_);

    DocumentInfo info;
    info.permissions = FPDF_GetDocPermissions(handle_);
    info.user_permissions = FPDF_GetDocUserPermissions(handle_);
    info.security_handler_revision = FPDF_GetSecurityHandlerRevision(handle_);
    info.permissions_info = DecodePermissions(info.permissions, info.security_handler_revision);
    info.user_permissions_info =
        DecodePermissions(info.user_permissions, info.security_handler_revision);

    int file_version = 0;
    if (FPDF_GetFileVersion(handle_, &file_version)) {
      info.pdf_version = FormatPdfVersion(file_version);
    }

    info.summary_info.title = ReadMetaText(handle_, "Title");
    info.summary_info.author = ReadMetaText(handle_, "Author");
    info.summary_info.subject = ReadMetaText(handle_, "Subject");
    info.summary_info.keywords = ReadMetaText(handle_, "Keywords");
    info.summary_info.creator = ReadMetaText(handle_, "Creator");
    info.summary_info.producer = ReadMetaText(handle_, "Producer");
    info.summary_info.creation_date = ReadMetaText(handle_, "CreationDate");
    info.summary_info.mod_date = ReadMetaText(handle_, "ModDate");
    return info;
  }

  int page_count() const override {
    std::lock_guard<std::mutex> lock(mutex_);
    return FPDF_GetPageCount(handle_);
  }

  PageSize page_size(int page_index) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    FS_SIZEF size{};
    if (!FPDF_GetPageSizeByIndexF(handle_, page_index, &size)) {
      return PageSize();
    }

    PageSize page_size;
    page_size.width = size.width;
    page_size.height = size.height;
    return page_size;
  }

  RenderPageResult render_page(int page_index, float scale) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    const int document_page_count = FPDF_GetPageCount(handle_);
    if (page_index < 0 || page_index >= document_page_count) {
      RenderPageResult result;
      result.error = "Page index out of range";
      return result;
    }

    FS_SIZEF raw_size{};
    if (!FPDF_GetPageSizeByIndexF(handle_, page_index, &raw_size)) {
      RenderPageResult result;
      result.error = "Invalid page size";
      return result;
    }

    PageSize size;
    size.width = raw_size.width;
    size.height = raw_size.height;
    const int width = size.width > 0.0f ? static_cast<int>(size.width * scale) : 0;
    const int height = size.height > 0.0f ? static_cast<int>(size.height * scale) : 0;
    if (width <= 0 || height <= 0) {
      RenderPageResult result;
      result.error = "Invalid page size";
      return result;
    }

    ScopedPdfPage page(handle_, page_index);
    if (page.get() == NULL) {
      RenderPageResult result;
      result.error = "FPDF_LoadPage failed";
      return result;
    }

    FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 1);
    if (bitmap == NULL) {
      RenderPageResult result;
      result.error = "FPDFBitmap_Create failed";
      return result;
    }

    FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
    FPDF_RenderPageBitmap(bitmap, page.get(), 0, 0, width, height, 0, FPDF_ANNOT);

    const int stride = FPDFBitmap_GetStride(bitmap);
    const unsigned char* buffer =
        static_cast<const unsigned char*>(FPDFBitmap_GetBuffer(bitmap));

    RenderPageResult result;
    result.bitmap.width = width;
    result.bitmap.height = height;
    result.bitmap.stride = stride;
    result.bitmap.pixels.assign(buffer, buffer + (stride * height));

    FPDFBitmap_Destroy(bitmap);
    return result;
  }

  int text_index_at_point(int page_index,
                          float page_x,
                          float page_y,
                          float x_tolerance,
                          float y_tolerance) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    const int document_page_count = FPDF_GetPageCount(handle_);
    if (page_index < 0 || page_index >= document_page_count) {
      return -1;
    }

    ScopedPdfPage page(handle_, page_index);
    if (page.get() == NULL) {
      return -1;
    }

    ScopedPdfTextPage text_page(page.get());
    if (text_page.get() == NULL) {
      return -1;
    }

    return FPDFText_GetCharIndexAtPos(text_page.get(),
                                      page_x,
                                      page_y,
                                      x_tolerance,
                                      y_tolerance);
  }

  int nearest_text_index_at_point(int page_index, float page_x, float page_y) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    const int document_page_count = FPDF_GetPageCount(handle_);
    if (page_index < 0 || page_index >= document_page_count) {
      return -1;
    }

    ScopedPdfPage page(handle_, page_index);
    if (page.get() == NULL) {
      return -1;
    }

    ScopedPdfTextPage text_page(page.get());
    if (text_page.get() == NULL) {
      return -1;
    }

    const int char_count = std::max(FPDFText_CountChars(text_page.get()), 0);
    if (char_count <= 0) {
      return -1;
    }

    const std::vector<TextCharBox> char_boxes = LoadPageCharBoxes(text_page.get(), char_count);
    if (char_boxes.empty()) {
      return -1;
    }
    const std::vector<TextLineSpan> line_spans = BuildTextLineSpans(char_boxes);
    if (line_spans.empty()) {
      return -1;
    }

    const double topmost_top = line_spans.front().top;
    const double bottommost_bottom = line_spans.back().bottom;
    if (static_cast<double>(page_y) > topmost_top) {
      return line_spans.front().start_index;
    }
    if (static_cast<double>(page_y) < bottommost_bottom) {
      return line_spans.back().end_index;
    }

    int best_line_index = -1;
    double best_vertical_distance = 0.0;
    for (size_t index = 0; index < line_spans.size(); ++index) {
      const double vertical_distance =
          VerticalDistanceToLine(line_spans[index], static_cast<double>(page_y));
      if (best_line_index < 0 || vertical_distance < best_vertical_distance) {
        best_line_index = static_cast<int>(index);
        best_vertical_distance = vertical_distance;
      }
    }
    if (best_line_index < 0) {
      return -1;
    }

    const TextLineSpan& line_span = line_spans[best_line_index];
    if (static_cast<double>(page_x) <= line_span.left) {
      return line_span.start_index;
    }
    if (static_cast<double>(page_x) >= line_span.right) {
      return line_span.end_index;
    }

    int nearest_index = line_span.start_index;
    double nearest_distance_x = 0.0;
    bool has_nearest = false;
    for (size_t index = 0; index < char_boxes.size(); ++index) {
      const TextCharBox& char_box = char_boxes[index];
      if (char_box.index < line_span.start_index || char_box.index > line_span.end_index) {
        continue;
      }

      const double clamped_x =
          std::max(std::min(static_cast<double>(page_x), char_box.right), char_box.left);
      const double distance_x = std::fabs(static_cast<double>(page_x) - clamped_x);
      if (!has_nearest || distance_x < nearest_distance_x) {
        nearest_index = char_box.index;
        nearest_distance_x = distance_x;
        has_nearest = true;
      }
    }

    return nearest_index;
  }

  int page_text_char_count(int page_index) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    const int document_page_count = FPDF_GetPageCount(handle_);
    if (page_index < 0 || page_index >= document_page_count) {
      return 0;
    }

    ScopedPdfPage page(handle_, page_index);
    if (page.get() == NULL) {
      return 0;
    }

    ScopedPdfTextPage text_page(page.get());
    if (text_page.get() == NULL) {
      return 0;
    }

    return std::max(FPDFText_CountChars(text_page.get()), 0);
  }

  PageTextSelection text_selection_for_range(int page_index,
                                             int start_index,
                                             int count) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    return text_selection_for_range_unlocked(page_index, start_index, count);
  }

  PageTextSelection word_selection_at_index(int page_index, int char_index) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    PageTextSelection selection;
    const int document_page_count = FPDF_GetPageCount(handle_);
    if (page_index < 0 || page_index >= document_page_count || char_index < 0) {
      return selection;
    }

    ScopedPdfPage page(handle_, page_index);
    if (page.get() == NULL) {
      return selection;
    }

    ScopedPdfTextPage text_page(page.get());
    if (text_page.get() == NULL) {
      return selection;
    }

    const int char_count = FPDFText_CountChars(text_page.get());
    if (char_count <= 0 || char_index >= char_count) {
      return selection;
    }

    const std::vector<unsigned int> codepoints = LoadPageCodepoints(text_page.get(), char_count);
    const TextCharRange range = word_char_range_from_text(codepoints, char_index);
    if (range.empty()) {
      return selection;
    }

    return text_selection_for_range_unlocked(page_index, range.start_index, range.count);
  }

 private:
  PageTextSelection text_selection_for_range_unlocked(int page_index,
                                                      int start_index,
                                                      int count) const {
    PageTextSelection selection;
    const int document_page_count = FPDF_GetPageCount(handle_);
    if (page_index < 0 || page_index >= document_page_count || start_index < 0 || count <= 0) {
      return selection;
    }

    ScopedPdfPage page(handle_, page_index);
    if (page.get() == NULL) {
      return selection;
    }

    ScopedPdfTextPage text_page(page.get());
    if (text_page.get() == NULL) {
      return selection;
    }

    const int char_count = FPDFText_CountChars(text_page.get());
    if (char_count <= 0 || start_index >= char_count) {
      return selection;
    }

    const int clamped_count = std::min(count, char_count - start_index);
    const int rect_count = FPDFText_CountRects(text_page.get(), start_index, clamped_count);
    if (rect_count < 0) {
      return selection;
    }

    selection.page_index = page_index;
    selection.start_index = start_index;
    selection.count = clamped_count;

    std::vector<unsigned short> text_buffer(static_cast<size_t>(clamped_count) + 1u, 0);
    const int written =
        FPDFText_GetText(text_page.get(), start_index, clamped_count, text_buffer.data());
    if (written > 0) {
      selection.text = Utf16ToUtf8(text_buffer);
    }

    for (int rect_index = 0; rect_index < rect_count; ++rect_index) {
      double left = 0.0;
      double top = 0.0;
      double right = 0.0;
      double bottom = 0.0;
      if (!FPDFText_GetRect(text_page.get(), rect_index, &left, &top, &right, &bottom)) {
        continue;
      }

      PageTextRect rect;
      rect.left = static_cast<float>(left);
      rect.top = static_cast<float>(top);
      rect.right = static_cast<float>(right);
      rect.bottom = static_cast<float>(bottom);
      selection.rects.push_back(rect);
    }

    return selection;
  }

  std::string path_;
  FPDF_DOCUMENT handle_ = nullptr;
  mutable std::mutex mutex_;
};

}  // namespace

OpenDocumentResult open_pdfium_document(const std::string& path) {
  pdfium_library();

  FPDF_DOCUMENT document = FPDF_LoadDocument(path.c_str(), NULL);
  if (document == nullptr) {
    const unsigned long error = FPDF_GetLastError();
    OpenDocumentResult result;
    result.document.reset();
    result.error = "FPDF_LoadDocument failed with error code " + std::to_string(error);
    return result;
  }

  OpenDocumentResult result;
  result.document = std::make_shared<PdfiumDocument>(path, document);
  return result;
}

}  // namespace core
}  // namespace pdfview
