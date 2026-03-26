#include "core/viewer_layout.h"

namespace pdfview {
namespace core {

const ViewerLayoutMetrics& default_viewer_layout_metrics() {
  static const ViewerLayoutMetrics metrics;
  return metrics;
}

}  // namespace core
}  // namespace pdfview
