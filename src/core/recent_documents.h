#pragma once

#include <string>
#include <vector>

namespace pdfview {
namespace core {

std::vector<std::string> load_recent_documents();

bool save_recent_documents(const std::vector<std::string>& document_paths);

std::vector<std::string> note_recent_document(const std::vector<std::string>& current_paths,
                                              const std::string& path,
                                              size_t max_count = 10);

}  // namespace core
}  // namespace pdfview
