#pragma once

#include <string>

namespace pdfview {
namespace tools {

bool parse_int_arg(const std::string& value, int* output);
bool parse_float_arg(const std::string& value, float* output);

}  // namespace tools
}  // namespace pdfview
