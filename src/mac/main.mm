#import <AppKit/AppKit.h>

#include <CoreGraphics/CoreGraphics.h>

#include <string>

#include "core/document.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv;
- (void)showStatus:(NSString*)text;
- (NSImage*)imageFromBitmap:(const pdfview::core::Bitmap&)bitmap;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSTextField* statusLabel_;
  NSImageView* imageView_;
  int argc_;
  const char** argv_;
}

- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv {
  self = [super init];
  if (self != nil) {
    argc_ = argc;
    argv_ = argv;
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  NSRect frame = NSMakeRect(0, 0, 900, 720);
  window_ = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSWindowStyleMaskTitled |
                                                  NSWindowStyleMaskClosable |
                                                  NSWindowStyleMaskMiniaturizable |
                                                  NSWindowStyleMaskResizable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

  [window_ center];
  [window_ setTitle:@"pdfview"];
  [window_ makeKeyAndOrderFront:nil];

  NSView* contentView = [window_ contentView];

  imageView_ = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 60, 852, 636)];
  [imageView_ setImageAlignment:NSImageAlignCenter];
  [imageView_ setImageScaling:NSImageScaleProportionallyUpOrDown];
  [imageView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [contentView addSubview:imageView_];

  statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 20, 852, 24)];
  [statusLabel_ setBezeled:NO];
  [statusLabel_ setDrawsBackground:NO];
  [statusLabel_ setEditable:NO];
  [statusLabel_ setSelectable:NO];
  [statusLabel_ setFont:[NSFont systemFontOfSize:13]];
  [statusLabel_ setAlignment:NSTextAlignmentLeft];
  [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [contentView addSubview:statusLabel_];

  if (argc_ > 1) {
    const std::string path(argv_[1]);
    const pdfview::core::OpenDocumentResult result = pdfview::core::open_document(path);
    if (result.ok()) {
      const int pageCount = result.document->page_count();
      const pdfview::core::PageSize firstPageSize =
          pageCount > 0 ? result.document->page_size(0) : pdfview::core::PageSize();
      const pdfview::core::RenderPageResult renderResult =
          pageCount > 0 ? result.document->render_page(0, 1.5f)
                        : pdfview::core::RenderPageResult();

      if (renderResult.ok()) {
        NSImage* image = [self imageFromBitmap:renderResult.bitmap];
        [imageView_ setImage:image];
        [self showStatus:[NSString stringWithFormat:@"Loaded %@, page 1 of %d, %.0f x %.0f pt",
                                                    [NSString stringWithUTF8String:argv_[1]],
                                                    pageCount,
                                                    firstPageSize.width,
                                                    firstPageSize.height]];
      } else {
        [self showStatus:[NSString stringWithFormat:@"Failed to render page 1: %s",
                                                    renderResult.error.c_str()]];
      }

      [window_ setTitle:[NSString stringWithFormat:@"pdfview - %@",
                                                   [NSString stringWithUTF8String:argv_[1]]]];
    } else {
      [self showStatus:[NSString stringWithFormat:@"Failed to open PDF: %s",
                                                  result.error.c_str()]];
    }
  } else {
#if defined(PDFVIEW_HAS_PDFIUM)
    [self showStatus:@"PDFium is enabled. Launch with a PDF path to render the first page."];
#else
    [self showStatus:@"PDFium is not enabled. Reconfigure with -DPDFVIEW_ENABLE_PDFIUM=ON and PDFIUM_ROOT."];
#endif
  }
}

- (void)showStatus:(NSString*)text {
  [statusLabel_ setStringValue:text];
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
