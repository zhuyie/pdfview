#include "command_registry.h"

#include <iostream>

#include "render_page_command.h"

namespace pdfview {
namespace tools {

std::vector<DebugCommand> build_debug_commands() {
  std::vector<DebugCommand> commands;
  commands.push_back(render_page_command());
  return commands;
}

const DebugCommand* find_debug_command(const std::string& name,
                                       const std::vector<DebugCommand>& commands) {
  for (size_t i = 0; i < commands.size(); ++i) {
    if (name == commands[i].name) {
      return &commands[i];
    }
  }
  return NULL;
}

void print_debug_tool_usage(const char* program_name,
                            const std::vector<DebugCommand>& commands) {
  std::cerr << "usage:\n";
  for (size_t i = 0; i < commands.size(); ++i) {
    std::cerr << "  " << program_name << " " << commands[i].usage << "\n";
  }
}

void print_command_usage(const char* program_name, const DebugCommand& command) {
  std::cerr << "usage:\n";
  std::cerr << "  " << program_name << " " << command.usage << "\n";
}

}  // namespace tools
}  // namespace pdfview
