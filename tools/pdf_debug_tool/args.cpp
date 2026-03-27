#include "args.h"

#include <cerrno>
#include <cstdlib>
#include <limits>

namespace pdfview {
namespace tools {

bool parse_int_arg(const std::string& value, int* output) {
  if (output == NULL) {
    return false;
  }

  char* end = NULL;
  errno = 0;
  const long parsed = std::strtol(value.c_str(), &end, 10);
  if (errno != 0 || end == value.c_str() || *end != '\0' ||
      parsed < std::numeric_limits<int>::min() ||
      parsed > std::numeric_limits<int>::max()) {
    return false;
  }

  *output = static_cast<int>(parsed);
  return true;
}

bool parse_float_arg(const std::string& value, float* output) {
  if (output == NULL) {
    return false;
  }

  char* end = NULL;
  errno = 0;
  const float parsed = std::strtof(value.c_str(), &end);
  if (errno != 0 || end == value.c_str() || *end != '\0') {
    return false;
  }

  *output = parsed;
  return true;
}

}  // namespace tools
}  // namespace pdfview
