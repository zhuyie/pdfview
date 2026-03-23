#include "core/document.h"

#include "core/pdfium_document.h"

namespace pdfview {
namespace core {

OpenDocumentResult open_document(const std::string& path) {
  return open_pdfium_document(path);
}

}  // namespace core
}  // namespace pdfview
