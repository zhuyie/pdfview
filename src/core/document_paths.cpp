#include "core/document_paths.h"

#include <cstdlib>

#if defined(_WIN32)
#include <windows.h>
#else
#include <limits.h>
#include <unistd.h>
#endif

namespace pdfview {
namespace core {

namespace {

std::string fallback_normalize_document_path(const std::string& path) {
  return path;
}

}  // namespace

std::string normalize_document_path(const std::string& path) {
  if (path.empty()) {
    return path;
  }

#if defined(_WIN32)
  char buffer[MAX_PATH];
  DWORD length = GetFullPathNameA(path.c_str(), MAX_PATH, buffer, NULL);
  if (length == 0 || length >= MAX_PATH) {
    return fallback_normalize_document_path(path);
  }
  return std::string(buffer, length);
#else
  char buffer[PATH_MAX];
  if (realpath(path.c_str(), buffer) == NULL) {
    return fallback_normalize_document_path(path);
  }
  return std::string(buffer);
#endif
}

bool same_document_path(const std::string& lhs, const std::string& rhs) {
  return normalize_document_path(lhs) == normalize_document_path(rhs);
}

}  // namespace core
}  // namespace pdfview
