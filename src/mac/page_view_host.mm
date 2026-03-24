#import "mac/page_view_host.h"

namespace {

NSRect NSRectFromViewRect(const pdfview::core::ViewRect& rect) {
  return NSMakeRect(rect.x, rect.y, rect.width, rect.height);
}

}  // namespace

@implementation PDFPageViewHost {
  NSView* documentView_;
  std::vector<NSImageView*>* pageImageViews_;
}

- (instancetype)initWithDocumentView:(NSView*)documentView
                      pageImageViews:(std::vector<NSImageView*>*)pageImageViews {
  self = [super init];
  if (self != nil) {
    documentView_ = documentView;
    pageImageViews_ = pageImageViews;
  }
  return self;
}

- (void)syncPageFrames:(const std::vector<pdfview::core::ViewRect>&)pageFrames {
  if (pageImageViews_ == nullptr) {
    return;
  }

  const int pageCount = static_cast<int>(pageFrames.size());
  for (int pageIndex = 0; pageIndex < pageCount; ++pageIndex) {
    NSImageView* imageView = (*pageImageViews_)[pageIndex];
    if (imageView == nil) {
      imageView = [[NSImageView alloc] initWithFrame:NSRectFromViewRect(pageFrames[pageIndex])];
      [imageView setImageAlignment:NSImageAlignCenter];
      [imageView setImageScaling:NSImageScaleNone];
      [imageView setWantsLayer:YES];
      [[imageView layer] setBackgroundColor:[[NSColor whiteColor] CGColor]];
      (*pageImageViews_)[pageIndex] = imageView;
      [documentView_ addSubview:imageView];
    }

    [imageView setFrame:NSRectFromViewRect(pageFrames[pageIndex])];
  }
}

- (void)clearPageImageAtIndex:(int)pageIndex {
  if (pageImageViews_ == nullptr ||
      pageIndex < 0 ||
      pageIndex >= static_cast<int>(pageImageViews_->size())) {
    return;
  }

  NSImageView* imageView = (*pageImageViews_)[pageIndex];
  if (imageView != nil) {
    [imageView setImage:nil];
  }
}

- (void)applyPageImage:(NSImage*)image atIndex:(int)pageIndex {
  if (pageImageViews_ == nullptr ||
      pageIndex < 0 ||
      pageIndex >= static_cast<int>(pageImageViews_->size())) {
    return;
  }

  NSImageView* imageView = (*pageImageViews_)[pageIndex];
  if (imageView != nil) {
    [imageView setImage:image];
  }
}

@end
