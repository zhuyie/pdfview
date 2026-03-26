#include "core/viewer_layout.h"

namespace pdfview {
namespace core {

const ViewerLayoutMetrics& default_viewer_layout_metrics() {
  static const ViewerLayoutMetrics metrics;
  return metrics;
}

const ViewerBehaviorMetrics& default_viewer_behavior_metrics() {
  static const ViewerBehaviorMetrics metrics;
  return metrics;
}

}  // namespace core
}  // namespace pdfview
