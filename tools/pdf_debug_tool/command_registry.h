#pragma once

#include <string>
#include <vector>

#include "command.h"

namespace pdfview {
namespace tools {

std::vector<DebugCommand> build_debug_commands();
const DebugCommand* find_debug_command(const std::string& name,
                                       const std::vector<DebugCommand>& commands);
void print_debug_tool_usage(const char* program_name,
                            const std::vector<DebugCommand>& commands);
void print_command_usage(const char* program_name, const DebugCommand& command);

}  // namespace tools
}  // namespace pdfview
