#include "core/recent_documents.h"

#include <cerrno>
#include <cstdlib>
#include <fstream>
#include <sys/stat.h>

#if defined(_WIN32)
#include <direct.h>
#endif

namespace pdfview {
namespace core {

namespace {

std::string EscapeLine(const std::string& input) {
  std::string output;
  output.reserve(input.size());
  for (size_t index = 0; index < input.size(); ++index) {
    const char ch = input[index];
    switch (ch) {
      case '\\':
        output += "\\\\";
        break;
      case '\n':
        output += "\\n";
        break;
      case '\r':
        output += "\\r";
        break;
      default:
        output += ch;
        break;
    }
  }
  return output;
}

std::string UnescapeLine(const std::string& input) {
  std::string output;
  output.reserve(input.size());
  for (size_t index = 0; index < input.size(); ++index) {
    const char ch = input[index];
    if (ch != '\\' || index + 1 >= input.size()) {
      output += ch;
      continue;
    }

    const char next = input[index + 1];
    switch (next) {
      case '\\':
        output += '\\';
        ++index;
        break;
      case 'n':
        output += '\n';
        ++index;
        break;
      case 'r':
        output += '\r';
        ++index;
        break;
      default:
        output += ch;
        break;
    }
  }
  return output;
}

char PathSeparator() {
#if defined(_WIN32)
  return '\\';
#else
  return '/';
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

std::string ConfigDirectoryPath() {
  const char* override_dir = std::getenv("PDFVIEW_CONFIG_DIR");
  if (override_dir != NULL && override_dir[0] != '\0') {
    return override_dir;
  }

#if defined(_WIN32)
  const char* appdata = std::getenv("APPDATA");
  if (appdata != NULL && appdata[0] != '\0') {
    return JoinPath(appdata, "pdfview");
  }

  const char* user_profile = std::getenv("USERPROFILE");
  if (user_profile != NULL && user_profile[0] != '\0') {
    return JoinPath(JoinPath(user_profile, "AppData\\Roaming"), "pdfview");
  }

  return "pdfview";
#elif defined(__APPLE__)
  const char* home = std::getenv("HOME");
  if (home != NULL && home[0] != '\0') {
    return JoinPath(JoinPath(JoinPath(home, "Library"), "Application Support"), "pdfview");
  }
  return JoinPath(".", "pdfview");
#else
  const char* home = std::getenv("HOME");
  if (home != NULL && home[0] != '\0') {
    return JoinPath(JoinPath(home, ".config"), "pdfview");
  }
  return JoinPath(".", "pdfview");
#endif
}

std::string RecentDocumentsFilePath() {
  return JoinPath(ConfigDirectoryPath(), "recent_documents.txt");
}

bool DirectoryExists(const std::string& path) {
  struct stat path_stat;
  return stat(path.c_str(), &path_stat) == 0 && (path_stat.st_mode & S_IFDIR) != 0;
}

bool CreateSingleDirectory(const std::string& path) {
  if (path.empty() || DirectoryExists(path)) {
    return true;
  }

#if defined(_WIN32)
  return _mkdir(path.c_str()) == 0 || errno == EEXIST;
#else
  return mkdir(path.c_str(), 0755) == 0 || errno == EEXIST;
#endif
}

bool EnsureDirectoryExists(const std::string& path) {
  if (path.empty()) {
    return false;
  }

  std::string current;
  const char separator = PathSeparator();

#if defined(_WIN32)
  if (path.size() >= 2 && path[1] == ':') {
    current = path.substr(0, 2);
  }
#endif

  for (size_t index = 0; index < path.size(); ++index) {
    const char ch = path[index];
    const bool is_separator = ch == '/' || ch == '\\';
    if (is_separator) {
      if (!current.empty() && !CreateSingleDirectory(current)) {
        return false;
      }
      if (current.empty() || current[current.size() - 1] != separator) {
        current += separator;
      }
      continue;
    }
    current += ch;
  }

  return CreateSingleDirectory(current);
}

}  // namespace

std::vector<std::string> load_recent_documents() {
  std::vector<std::string> document_paths;
  std::ifstream input(RecentDocumentsFilePath().c_str());
  if (!input.is_open()) {
    return document_paths;
  }

  std::string line;
  while (std::getline(input, line)) {
    if (line.empty()) {
      continue;
    }
    document_paths.push_back(UnescapeLine(line));
  }

  return document_paths;
}

bool save_recent_documents(const std::vector<std::string>& document_paths) {
  const std::string directory_path = ConfigDirectoryPath();
  if (!EnsureDirectoryExists(directory_path)) {
    return false;
  }

  std::ofstream output(RecentDocumentsFilePath().c_str(), std::ios::out | std::ios::trunc);
  if (!output.is_open()) {
    return false;
  }

  for (size_t index = 0; index < document_paths.size(); ++index) {
    output << EscapeLine(document_paths[index]) << '\n';
  }

  return output.good();
}

std::vector<std::string> note_recent_document(const std::vector<std::string>& current_paths,
                                              const std::string& path,
                                              size_t max_count) {
  std::vector<std::string> updated_paths;
  if (!path.empty()) {
    updated_paths.push_back(path);
  }

  for (size_t index = 0; index < current_paths.size(); ++index) {
    if (current_paths[index].empty() || current_paths[index] == path) {
      continue;
    }
    updated_paths.push_back(current_paths[index]);
    if (updated_paths.size() >= max_count) {
      break;
    }
  }

  return updated_paths;
}

}  // namespace core
}  // namespace pdfview
