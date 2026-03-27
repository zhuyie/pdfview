#include "doc_info_command.h"

#include <iostream>
#include <string>
#include <vector>

#include "core/document.h"

namespace pdfview {
namespace tools {

namespace {

void PrintPermissionField(const char* label, bool value) {
  std::cout << "  " << label << "=" << (value ? "true" : "false") << "\n";
}

void PrintPermissionsBlock(const char* label,
                           unsigned long raw_value,
                           const pdfview::core::DocumentPermissionsInfo& permissions) {
  std::cout << label << "=" << raw_value << "\n";
  PrintPermissionField("can_print", permissions.can_print);
  PrintPermissionField("can_print_high_quality", permissions.can_print_high_quality);
  PrintPermissionField("can_modify", permissions.can_modify);
  PrintPermissionField("can_copy", permissions.can_copy);
  PrintPermissionField("can_annotate", permissions.can_annotate);
  PrintPermissionField("can_fill_forms", permissions.can_fill_forms);
  PrintPermissionField("can_copy_for_accessibility",
                       permissions.can_copy_for_accessibility);
  PrintPermissionField("can_assemble", permissions.can_assemble);
}

void PrintSummaryField(const char* label, const std::string& value) {
  if (!value.empty()) {
    std::cout << "  " << label << "=" << value << "\n";
  }
}

void PrintSummaryInfoBlock(const pdfview::core::DocumentSummaryInfo& summary_info) {
  std::cout << "summary_info\n";
  PrintSummaryField("title", summary_info.title);
  PrintSummaryField("author", summary_info.author);
  PrintSummaryField("subject", summary_info.subject);
  PrintSummaryField("keywords", summary_info.keywords);
  PrintSummaryField("creator", summary_info.creator);
  PrintSummaryField("producer", summary_info.producer);
  PrintSummaryField("creation_date", summary_info.creation_date);
  PrintSummaryField("mod_date", summary_info.mod_date);
}

int RunDocInfo(const std::vector<std::string>& args) {
  std::string input_path;

  for (size_t i = 0; i < args.size(); ++i) {
    const std::string& argument = args[i];
    if ((argument == "--input" || argument == "-i") && i + 1 < args.size()) {
      input_path = args[++i];
      continue;
    }

    std::cerr << "unknown argument: " << argument << "\n";
    return 2;
  }

  if (input_path.empty()) {
    return 2;
  }

  const pdfview::core::OpenDocumentResult open_result =
      pdfview::core::open_document(input_path);
  if (!open_result.ok()) {
    std::cerr << "open failed: " << open_result.error << "\n";
    return 1;
  }

  const pdfview::core::DocumentInfo info = open_result.document->info();
  const int page_count = open_result.document->page_count();

  std::cout << "input=" << input_path << "\n";
  std::cout << "pdf_version=" << (info.pdf_version.empty() ? "unknown" : info.pdf_version)
            << "\n";
  std::cout << "security_handler_revision=" << info.security_handler_revision << "\n";
  PrintPermissionsBlock("permissions", info.permissions, info.permissions_info);
  PrintPermissionsBlock("user_permissions",
                        info.user_permissions,
                        info.user_permissions_info);
  PrintSummaryInfoBlock(info.summary_info);
  std::cout << "pages\n";
  std::cout << "  count=" << page_count << "\n";
  for (int page_index = 0; page_index < page_count; ++page_index) {
    const pdfview::core::PageSize page_size = open_result.document->page_size(page_index);
    std::cout << "  page[" << page_index << "]"
              << " width=" << page_size.width
              << " height=" << page_size.height << "\n";
  }

  return 0;
}

}  // namespace

const DebugCommand& doc_info_command() {
  static const DebugCommand command = {
      "doc-info",
      "doc-info --input <pdf>",
      &RunDocInfo,
  };
  return command;
}

}  // namespace tools
}  // namespace pdfview
