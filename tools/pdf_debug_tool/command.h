#pragma once

#include <string>
#include <vector>

namespace pdfview {
namespace tools {

struct DebugCommand {
  const char* name;
  const char* usage;
  int (*run)(const std::vector<std::string>& args);
};

}  // namespace tools
}  // namespace pdfview
