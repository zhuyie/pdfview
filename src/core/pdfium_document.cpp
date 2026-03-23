#include "core/pdfium_document.h"

#include <memory>
#include <string>

#include "fpdf_edit.h"
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

    FPDF_PAGE page = FPDF_LoadPage(handle_, page_index);
    if (page == NULL) {
      RenderPageResult result;
      result.error = "FPDF_LoadPage failed";
      return result;
    }

    FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 1);
    if (bitmap == NULL) {
      FPDF_ClosePage(page);
      RenderPageResult result;
      result.error = "FPDFBitmap_Create failed";
      return result;
    }

    FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
    FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, FPDF_ANNOT);

    const int stride = FPDFBitmap_GetStride(bitmap);
    const unsigned char* buffer =
        static_cast<const unsigned char*>(FPDFBitmap_GetBuffer(bitmap));

    RenderPageResult result;
    result.bitmap.width = width;
    result.bitmap.height = height;
    result.bitmap.stride = stride;
    result.bitmap.pixels.assign(buffer, buffer + (stride * height));

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);
    return result;
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
