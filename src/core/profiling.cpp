#include "core/profiling.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>

namespace pdfview {
namespace core {

namespace {

FILE* render_log_stream() {
  static FILE* stream = []() -> FILE* {
    const char* path = std::getenv("PDFVIEW_PROFILE_RENDER_FILE");
    if (path == NULL || path[0] == '\0') {
      return stderr;
    }

    FILE* file = std::fopen(path, "a");
    if (file == NULL) {
      return stderr;
    }
    return file;
  }();
  return stream;
}

}  // namespace

bool render_profiling_enabled() {
  static const bool enabled = []() -> bool {
    const char* value = std::getenv("PDFVIEW_PROFILE_RENDER");
    return value != NULL && value[0] != '\0' && value[0] != '0';
  }();
  return enabled;
}

void render_log(const char* format, ...) {
  if (!render_profiling_enabled()) {
    return;
  }

  FILE* stream = render_log_stream();
  if (stream == NULL) {
    return;
  }

  va_list args;
  va_start(args, format);
  std::vfprintf(stream, format, args);
  va_end(args);
  std::fputc('\n', stream);
  std::fflush(stream);
}

}  // namespace core
}  // namespace pdfview
