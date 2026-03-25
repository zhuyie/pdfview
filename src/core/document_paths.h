#pragma once

#include <string>

namespace pdfview {
namespace core {

std::string normalize_document_path(const std::string& path);

bool same_document_path(const std::string& lhs, const std::string& rhs);

}  // namespace core
}  // namespace pdfview
