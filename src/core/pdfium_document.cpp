#include "core/pdfium_document.h"

#include <memory>
#include <string>

#if defined(PDFVIEW_HAS_PDFIUM)
#include "fpdfview.h"
#endif

namespace pdfview {
namespace core {

#if defined(PDFVIEW_HAS_PDFIUM)

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

#else

OpenDocumentResult open_pdfium_document(const std::string&) {
  OpenDocumentResult result;
  result.document.reset();
  result.error = "PDFium support is not enabled. Configure with -DPDFVIEW_ENABLE_PDFIUM=ON and set PDFIUM_ROOT.";
  return result;
}

#endif

}  // namespace core
}  // namespace pdfview
