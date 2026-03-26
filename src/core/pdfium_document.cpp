#include "core/pdfium_document.h"

#include <codecvt>
#include <locale>
#include <memory>
#include <string>
#include <vector>

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

class PdfiumDocument final : public Document {
 public:
  explicit PdfiumDocument(FPDF_DOCUMENT handle) : handle_(handle) {}

  ~PdfiumDocument() override {
    if (handle_ != nullptr) {
      FPDF_CloseDocument(handle_);
    }
  }

  int page_count() const override {
    return FPDF_GetPageCount(handle_);
  }

  PageSize page_size(int page_index) const override {
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
    if (page_index < 0 || page_index >= page_count()) {
      RenderPageResult result;
      result.error = "Page index out of range";
      return result;
    }

    const PageSize size = page_size(page_index);
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
    if (page_index < 0 || page_index >= page_count()) {
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

  PageTextSelection text_selection_for_range(int page_index,
                                             int start_index,
                                             int count) const override {
    PageTextSelection selection;
    if (page_index < 0 || page_index >= page_count() || start_index < 0 || count <= 0) {
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

  PageTextSelection word_selection_at_index(int page_index, int char_index) const override {
    PageTextSelection selection;
    if (page_index < 0 || page_index >= page_count() || char_index < 0) {
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

    return text_selection_for_range(page_index, range.start_index, range.count);
  }

 private:
  FPDF_DOCUMENT handle_ = nullptr;
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
  result.document = std::make_shared<PdfiumDocument>(document);
  return result;
}

}  // namespace core
}  // namespace pdfview
