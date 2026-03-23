#pragma once

#include <memory>
#include <string>

namespace pdfview::core {

struct PageSize {
  float width = 0.0f;
  float height = 0.0f;
};

class Document {
 public:
  virtual ~Document() = default;

  virtual int page_count() const = 0;
  virtual PageSize page_size(int page_index) const = 0;
};

using DocumentPtr = std::shared_ptr<Document>;

}  // namespace pdfview::core
