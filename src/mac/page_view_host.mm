#import "mac/page_view_host.h"

namespace {

NSRect NSRectFromViewRect(const pdfview::core::ViewRect& rect) {
  return NSMakeRect(rect.x, rect.y, rect.width, rect.height);
}

}  // namespace

@interface PDFSelectablePageImageView : NSImageView

@property(nonatomic, assign) int pageIndex;
@property(nonatomic, assign) id<PDFPageViewHostDelegate> selectionDelegate;

- (void)setSelectionRects:(const std::vector<pdfview::core::ViewRect>&)selectionRects;

@end

@implementation PDFSelectablePageImageView {
  NSMutableArray<NSValue*>* selectionRects_;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    selectionRects_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (void)setSelectionRects:(const std::vector<pdfview::core::ViewRect>&)selectionRects {
  [selectionRects_ removeAllObjects];
  for (size_t index = 0; index < selectionRects.size(); ++index) {
    [selectionRects_ addObject:[NSValue valueWithRect:NSRectFromViewRect(selectionRects[index])]];
  }
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if ([selectionRects_ count] == 0) {
    return;
  }

  [[NSColor colorWithCalibratedRed:0.24 green:0.54 blue:0.98 alpha:0.26] setFill];
  for (NSValue* rectValue in selectionRects_) {
    const NSRect rect = [rectValue rectValue];
    if (!NSIntersectsRect(rect, dirtyRect)) {
      continue;
    }
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0] fill];
  }
}

- (void)mouseDown:(NSEvent*)event {
  if (self.selectionDelegate != nil) {
    [self.selectionDelegate pageViewHostDidBeginTextSelectionAtPageIndex:self.pageIndex
                                                                location:[self convertPoint:[event locationInWindow]
                                                                                     fromView:nil]];
  }
}

- (void)mouseDragged:(NSEvent*)event {
  if (self.selectionDelegate != nil) {
    [self.selectionDelegate pageViewHostDidUpdateTextSelectionAtPageIndex:self.pageIndex
                                                                 location:[self convertPoint:[event locationInWindow]
                                                                                      fromView:nil]];
  }
}

- (void)mouseUp:(NSEvent*)event {
  if (self.selectionDelegate != nil) {
    [self.selectionDelegate pageViewHostDidEndTextSelectionAtPageIndex:self.pageIndex
                                                              location:[self convertPoint:[event locationInWindow]
                                                                                   fromView:nil]];
  }
}

@end

@implementation PDFPageViewHost {
  NSView* documentView_;
  std::vector<NSImageView*>* pageImageViews_;
  id<PDFPageViewHostDelegate> delegate_;
}

- (instancetype)initWithDocumentView:(NSView*)documentView
                      pageImageViews:(std::vector<NSImageView*>*)pageImageViews
                            delegate:(id<PDFPageViewHostDelegate>)delegate {
  self = [super init];
  if (self != nil) {
    documentView_ = documentView;
    pageImageViews_ = pageImageViews;
    delegate_ = delegate;
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
      PDFSelectablePageImageView* selectableImageView =
          [[PDFSelectablePageImageView alloc] initWithFrame:NSRectFromViewRect(pageFrames[pageIndex])];
      selectableImageView.pageIndex = pageIndex;
      selectableImageView.selectionDelegate = delegate_;
      imageView = selectableImageView;
      [imageView setImageAlignment:NSImageAlignCenter];
      [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
      [imageView setWantsLayer:YES];
      [[imageView layer] setBackgroundColor:[[NSColor whiteColor] CGColor]];
      [[imageView layer] setMasksToBounds:YES];
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

- (void)setSelectionRects:(const std::vector<pdfview::core::ViewRect>&)selectionRects
                  atIndex:(int)pageIndex {
  if (pageImageViews_ == nullptr ||
      pageIndex < 0 ||
      pageIndex >= static_cast<int>(pageImageViews_->size())) {
    return;
  }

  PDFSelectablePageImageView* imageView =
      (PDFSelectablePageImageView*)(*pageImageViews_)[pageIndex];
  if (imageView != nil) {
    [imageView setSelectionRects:selectionRects];
  }
}

- (void)clearSelectionAtIndex:(int)pageIndex {
  std::vector<pdfview::core::ViewRect> selectionRects;
  [self setSelectionRects:selectionRects atIndex:pageIndex];
}

@end
