#include <vector>

#include "command_registry.h"

int main(int argc, char** argv) {
  const std::vector<pdfview::tools::DebugCommand> commands =
      pdfview::tools::build_debug_commands();

  if (argc < 2) {
    pdfview::tools::print_debug_tool_usage(argv[0], commands);
    return 2;
  }

  const pdfview::tools::DebugCommand* command =
      pdfview::tools::find_debug_command(argv[1], commands);
  if (command == NULL) {
    pdfview::tools::print_debug_tool_usage(argv[0], commands);
    return 2;
  }

  std::vector<std::string> args;
  for (int i = 2; i < argc; ++i) {
    args.push_back(argv[i]);
  }

  const int exit_code = command->run(args);
  if (exit_code == 2) {
    pdfview::tools::print_command_usage(argv[0], *command);
  }
  return exit_code;
}
