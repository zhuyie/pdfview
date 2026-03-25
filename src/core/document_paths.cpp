#include "core/document_paths.h"

#include <cstdlib>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <limits.h>
#include <unistd.h>
#endif

namespace pdfview {
namespace core {

namespace {

bool IsAbsolutePath(const std::string& path) {
  if (path.empty()) {
    return false;
  }

#if defined(_WIN32)
  return path.size() >= 2 && path[1] == ':';
#else
  return path[0] == '/';
#endif
}

char PathSeparator() {
#if defined(_WIN32)
  return '\\';
#else
  return '/';
#endif
}

std::string CurrentWorkingDirectory() {
#if defined(_WIN32)
  char buffer[MAX_PATH];
  DWORD length = GetCurrentDirectoryA(MAX_PATH, buffer);
  if (length == 0 || length >= MAX_PATH) {
    return std::string();
  }
  return std::string(buffer, length);
#else
  char buffer[PATH_MAX];
  if (getcwd(buffer, sizeof(buffer)) == NULL) {
    return std::string();
  }
  return std::string(buffer);
#endif
}

std::string JoinPath(const std::string& lhs, const std::string& rhs) {
  if (lhs.empty()) {
    return rhs;
  }
  if (rhs.empty()) {
    return lhs;
  }

  const char separator = PathSeparator();
  if (lhs[lhs.size() - 1] == separator) {
    return lhs + rhs;
  }
  return lhs + separator + rhs;
}

std::string lexical_normalize_document_path(const std::string& path) {
  const char separator = PathSeparator();
  std::string absolute_path = path;
  if (!IsAbsolutePath(absolute_path)) {
    const std::string cwd = CurrentWorkingDirectory();
    if (!cwd.empty()) {
      absolute_path = JoinPath(cwd, path);
    }
  }

  std::vector<std::string> parts;
  std::string current_part;
  for (size_t index = 0; index <= absolute_path.size(); ++index) {
    const char ch = index < absolute_path.size() ? absolute_path[index] : separator;
    const bool is_separator = ch == '/' || ch == '\\';
    if (!is_separator) {
      current_part += ch;
      continue;
    }

    if (current_part == "..") {
      if (!parts.empty()) {
        parts.pop_back();
      }
    } else if (!current_part.empty() && current_part != ".") {
      parts.push_back(current_part);
    }
    current_part.clear();
  }

  std::string normalized;
#if defined(_WIN32)
  if (absolute_path.size() >= 2 && absolute_path[1] == ':') {
    normalized = absolute_path.substr(0, 2);
  }
#else
  normalized = std::string(1, separator);
#endif

  for (size_t index = 0; index < parts.size(); ++index) {
    if (!normalized.empty() && normalized[normalized.size() - 1] != separator) {
      normalized += separator;
    }
    normalized += parts[index];
  }

  return normalized.empty() ? path : normalized;
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
    return lexical_normalize_document_path(path);
  }
  return std::string(buffer, length);
#else
  char buffer[PATH_MAX];
  if (realpath(path.c_str(), buffer) == NULL) {
    return lexical_normalize_document_path(path);
  }
  return std::string(buffer);
#endif
}

bool same_document_path(const std::string& lhs, const std::string& rhs) {
  return normalize_document_path(lhs) == normalize_document_path(rhs);
}

}  // namespace core
}  // namespace pdfview
