#import <AppKit/AppKit.h>

#include <CoreGraphics/CoreGraphics.h>

#include <algorithm>
#include <string>
#include <vector>

#include "core/document.h"

@interface FlippedDocumentView : NSView
@end

@implementation FlippedDocumentView

- (BOOL)isFlipped {
  return YES;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv;
- (void)showStatus;
- (NSImage*)imageFromBitmap:(const pdfview::core::Bitmap&)bitmap;
- (void)loadInitialDocument;
- (void)renderDocument;
- (float)fitScaleForDocument;
- (float)currentScale;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoomToFit;
- (void)goToNextPage;
- (void)goToPreviousPage;
- (void)scrollToCurrentPage;
- (void)updateCurrentPageFromScroll;
- (void)installKeyMonitor;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSScrollView* scrollView_;
  NSView* documentView_;
  NSTextField* statusLabel_;
  NSMutableArray* pageImageViews_;
  std::vector<NSRect> pageFrames_;
  pdfview::core::DocumentPtr document_;
  std::string documentPath_;
  int currentPage_;
  float manualScale_;
  BOOL useFitScale_;
  id keyMonitor_;
  int argc_;
  const char** argv_;
}

- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv {
  self = [super init];
  if (self != nil) {
    argc_ = argc;
    argv_ = argv;
    currentPage_ = 0;
    manualScale_ = 1.0f;
    useFitScale_ = YES;
    keyMonitor_ = nil;
    pageImageViews_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  NSRect frame = NSMakeRect(0, 0, 960, 760);
  window_ = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSWindowStyleMaskTitled |
                                                  NSWindowStyleMaskClosable |
                                                  NSWindowStyleMaskMiniaturizable |
                                                  NSWindowStyleMaskResizable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

  [window_ center];
  [window_ setTitle:@"pdfview"];
  [window_ setDelegate:self];
  [window_ makeKeyAndOrderFront:nil];

  NSView* contentView = [window_ contentView];

  scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 52, 920, 688)];
  [scrollView_ setHasVerticalScroller:YES];
  [scrollView_ setHasHorizontalScroller:YES];
  [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [scrollView_ setBorderType:NSNoBorder];
  [scrollView_ setBackgroundColor:[NSColor colorWithCalibratedWhite:0.92 alpha:1.0]];
  [[scrollView_ contentView] setPostsBoundsChangedNotifications:YES];
  [contentView addSubview:scrollView_];

  documentView_ = [[FlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
  [documentView_ setWantsLayer:YES];
  [[documentView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
  [scrollView_ setDocumentView:documentView_];

  statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 18, 920, 20)];
  [statusLabel_ setBezeled:NO];
  [statusLabel_ setDrawsBackground:NO];
  [statusLabel_ setEditable:NO];
  [statusLabel_ setSelectable:NO];
  [statusLabel_ setFont:[NSFont systemFontOfSize:13]];
  [statusLabel_ setAlignment:NSTextAlignmentLeft];
  [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [contentView addSubview:statusLabel_];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(updateCurrentPageFromScroll)
                                               name:NSViewBoundsDidChangeNotification
                                             object:[scrollView_ contentView]];

  [self installKeyMonitor];
  [self loadInitialDocument];
}

- (void)loadInitialDocument {
  if (argc_ <= 1) {
#if defined(PDFVIEW_HAS_PDFIUM)
    [statusLabel_ setStringValue:@"PDFium is enabled. Launch with a PDF path to render the document."];
#else
    [statusLabel_ setStringValue:@"PDFium is not enabled. Reconfigure with -DPDFVIEW_ENABLE_PDFIUM=ON and PDFIUM_ROOT."];
#endif
    return;
  }

  documentPath_ = argv_[1];
  const pdfview::core::OpenDocumentResult result = pdfview::core::open_document(documentPath_);
  if (!result.ok()) {
    [statusLabel_ setStringValue:[NSString stringWithFormat:@"Failed to open PDF: %s", result.error.c_str()]];
    return;
  }

  document_ = result.document;
  currentPage_ = 0;
  useFitScale_ = YES;
  [window_ setTitle:[NSString stringWithFormat:@"pdfview - %s", documentPath_.c_str()]];
  [self renderDocument];
  [self scrollToCurrentPage];
}

- (void)renderDocument {
  if (!document_) {
    return;
  }

  for (NSView* view in pageImageViews_) {
    [view removeFromSuperview];
  }
  [pageImageViews_ removeAllObjects];
  pageFrames_.clear();

  const float scale = [self currentScale];
  const CGFloat pageGap = 24.0f;
  const CGFloat topMargin = 20.0f;
  const CGFloat sideMargin = 16.0f;
  const NSSize clipSize = [[scrollView_ contentView] bounds].size;

  CGFloat documentWidth = clipSize.width;
  CGFloat maxPageWidth = 0.0f;
  CGFloat cursorY = topMargin;

  const int pageCount = document_->page_count();
  for (int pageIndex = 0; pageIndex < pageCount; ++pageIndex) {
    const pdfview::core::RenderPageResult renderResult =
        document_->render_page(pageIndex, scale);
    if (!renderResult.ok()) {
      [statusLabel_ setStringValue:[NSString stringWithFormat:@"Failed to render page %d: %s",
                                                              pageIndex + 1,
                                                              renderResult.error.c_str()]];
      continue;
    }

    NSImage* image = [self imageFromBitmap:renderResult.bitmap];
    NSImageView* imageView = [[NSImageView alloc]
        initWithFrame:NSMakeRect(0, 0, renderResult.bitmap.width, renderResult.bitmap.height)];
    [imageView setImage:image];
    [imageView setImageAlignment:NSImageAlignCenter];
    [imageView setImageScaling:NSImageScaleNone];

    const CGFloat pageX = std::max((clipSize.width - renderResult.bitmap.width) * 0.5, sideMargin);
    const NSRect pageFrame = NSMakeRect(pageX, cursorY, renderResult.bitmap.width, renderResult.bitmap.height);
    [imageView setFrame:pageFrame];
    [documentView_ addSubview:imageView];
    [pageImageViews_ addObject:imageView];
    pageFrames_.push_back(pageFrame);

    cursorY += renderResult.bitmap.height + pageGap;
    documentWidth = std::max(documentWidth, pageFrame.origin.x + pageFrame.size.width + sideMargin);
    maxPageWidth = std::max(maxPageWidth, static_cast<CGFloat>(renderResult.bitmap.width));
  }

  const CGFloat documentHeight = std::max(cursorY, clipSize.height);
  [documentView_ setFrame:NSMakeRect(0, 0, std::max(documentWidth, maxPageWidth + sideMargin * 2.0f), documentHeight)];
  [self showStatus];
}

- (float)fitScaleForDocument {
  if (!document_ || document_->page_count() <= 0) {
    return 1.0f;
  }

  float maxPageWidth = 0.0f;
  for (int pageIndex = 0; pageIndex < document_->page_count(); ++pageIndex) {
    const pdfview::core::PageSize pageSize = document_->page_size(pageIndex);
    maxPageWidth = std::max(maxPageWidth, pageSize.width);
  }

  if (maxPageWidth <= 0.0f) {
    return 1.0f;
  }

  const NSSize clipSize = [[scrollView_ contentView] bounds].size;
  const float horizontalPadding = 48.0f;
  const float targetWidth = std::max(clipSize.width - horizontalPadding, 120.0);
  const float scale = targetWidth / maxPageWidth;
  return std::max(0.25f, scale);
}

- (float)currentScale {
  if (useFitScale_) {
    return [self fitScaleForDocument];
  }
  return std::max(0.1f, manualScale_);
}

- (void)zoomIn {
  if (!document_) {
    return;
  }

  manualScale_ = std::min([self currentScale] * 1.25f, 5.0f);
  useFitScale_ = NO;
  [self renderDocument];
  [self scrollToCurrentPage];
}

- (void)zoomOut {
  if (!document_) {
    return;
  }

  manualScale_ = std::max([self currentScale] / 1.25f, 0.1f);
  useFitScale_ = NO;
  [self renderDocument];
  [self scrollToCurrentPage];
}

- (void)resetZoomToFit {
  if (!document_) {
    return;
  }

  useFitScale_ = YES;
  [self renderDocument];
  [self scrollToCurrentPage];
}

- (void)goToNextPage {
  if (!document_ || currentPage_ + 1 >= document_->page_count()) {
    return;
  }

  currentPage_ += 1;
  [self scrollToCurrentPage];
  [self showStatus];
}

- (void)goToPreviousPage {
  if (!document_ || currentPage_ <= 0) {
    return;
  }

  currentPage_ -= 1;
  [self scrollToCurrentPage];
  [self showStatus];
}

- (void)scrollToCurrentPage {
  if (currentPage_ < 0 || currentPage_ >= static_cast<int>(pageFrames_.size())) {
    return;
  }

  const NSRect pageFrame = pageFrames_[currentPage_];
  [[scrollView_ documentView] scrollRectToVisible:pageFrame];
}

- (void)updateCurrentPageFromScroll {
  if (!document_ || pageFrames_.empty()) {
    return;
  }

  const NSRect visibleRect = [[scrollView_ contentView] bounds];
  const CGFloat visibleCenterY = visibleRect.origin.y + visibleRect.size.height * 0.5;

  int nearestPage = 0;
  CGFloat nearestDistance = CGFLOAT_MAX;
  for (int pageIndex = 0; pageIndex < static_cast<int>(pageFrames_.size()); ++pageIndex) {
    const NSRect pageFrame = pageFrames_[pageIndex];
    const CGFloat pageCenterY = pageFrame.origin.y + pageFrame.size.height * 0.5;
    const CGFloat distance = std::abs(pageCenterY - visibleCenterY);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestPage = pageIndex;
    }
  }

  if (nearestPage != currentPage_) {
    currentPage_ = nearestPage;
    [self showStatus];
  }
}

- (void)installKeyMonitor {
  keyMonitor_ = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                      handler:^NSEvent*(NSEvent* event) {
    if (!document_) {
      return event;
    }

    NSString* characters = [event charactersIgnoringModifiers];
    if ([characters length] == 0) {
      return event;
    }

    const unichar key = [characters characterAtIndex:0];
    if (key == '+' || key == '=') {
      [self zoomIn];
      return nil;
    }
    if (key == '-') {
      [self zoomOut];
      return nil;
    }
    if (key == '0') {
      [self resetZoomToFit];
      return nil;
    }
    if (key == NSRightArrowFunctionKey || key == NSDownArrowFunctionKey ||
        key == 'j' || key == 'n') {
      [self goToNextPage];
      return nil;
    }
    if (key == NSLeftArrowFunctionKey || key == NSUpArrowFunctionKey ||
        key == 'k' || key == 'p') {
      [self goToPreviousPage];
      return nil;
    }

    return event;
  }];
}

- (void)showStatus {
  if (!document_ || currentPage_ < 0 || currentPage_ >= document_->page_count()) {
    return;
  }

  const pdfview::core::PageSize pageSize = document_->page_size(currentPage_);
  [statusLabel_ setStringValue:[NSString stringWithFormat:@"Page %d of %d, %.0f x %.0f pt, zoom %.0f%%",
                                                          currentPage_ + 1,
                                                          document_->page_count(),
                                                          pageSize.width,
                                                          pageSize.height,
                                                          [self currentScale] * 100.0f]];
}

- (NSImage*)imageFromBitmap:(const pdfview::core::Bitmap&)bitmap {
  NSData* bitmapData =
      [NSData dataWithBytes:bitmap.pixels.data() length:bitmap.pixels.size()];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)bitmapData);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGImageRef cgImage = CGImageCreate(bitmap.width,
                                     bitmap.height,
                                     8,
                                     32,
                                     bitmap.stride,
                                     colorSpace,
                                     kCGBitmapByteOrder32Little |
                                         kCGImageAlphaPremultipliedFirst,
                                     provider,
                                     NULL,
                                     false,
                                     kCGRenderingIntentDefault);
  NSImage* image = [[NSImage alloc] initWithCGImage:cgImage
                                               size:NSMakeSize(bitmap.width, bitmap.height)];
  CGImageRelease(cgImage);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}

- (void)windowDidResize:(NSNotification*)notification {
  (void)notification;
  if (useFitScale_) {
    [self renderDocument];
    [self scrollToCurrentPage];
  } else {
    [self updateCurrentPageFromScroll];
  }
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  (void)notification;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  if (keyMonitor_ != nil) {
    [NSEvent removeMonitor:keyMonitor_];
    keyMonitor_ = nil;
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    NSApplication* app = [NSApplication sharedApplication];
    AppDelegate* delegate = [[AppDelegate alloc] initWithArgc:argc argv:argv];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app setDelegate:delegate];
    [app activateIgnoringOtherApps:YES];
    [app run];
  }
  return 0;
}
