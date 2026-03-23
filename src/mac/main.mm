#import <AppKit/AppKit.h>

#include <string>

#include "core/document.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSTextField* statusLabel_;
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

  NSRect frame = NSMakeRect(0, 0, 720, 480);
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

  statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 220, 672, 40)];
  [statusLabel_ setBezeled:NO];
  [statusLabel_ setDrawsBackground:NO];
  [statusLabel_ setEditable:NO];
  [statusLabel_ setSelectable:NO];
  [statusLabel_ setFont:[NSFont systemFontOfSize:18 weight:NSFontWeightMedium]];
  [statusLabel_ setAlignment:NSTextAlignmentCenter];
  [contentView addSubview:statusLabel_];

  if (argc_ > 1) {
    const auto result = pdfview::core::open_document(argv_[1]);
    if (result.ok()) {
      const int pageCount = result.document->page_count();
      const auto firstPageSize = pageCount > 0 ? result.document->page_size(0) : pdfview::core::PageSize{};
      NSString* text = [NSString stringWithFormat:@"Loaded %@ (%d pages, first page %.0f x %.0f)",
                                                  [NSString stringWithUTF8String:argv_[1]],
                                                  pageCount,
                                                  firstPageSize.width,
                                                  firstPageSize.height];
      [statusLabel_ setStringValue:text];
      [window_ setTitle:[NSString stringWithFormat:@"pdfview - %@", [NSString stringWithUTF8String:argv_[1]]]];
    } else {
      NSString* text = [NSString stringWithFormat:@"Failed to open PDF: %s", result.error.c_str()];
      [statusLabel_ setStringValue:text];
    }
  } else {
#if defined(PDFVIEW_HAS_PDFIUM)
    [statusLabel_ setStringValue:@"PDFium is enabled. Launch with a PDF path to test document loading."];
#else
    [statusLabel_ setStringValue:@"PDFium is not enabled. Reconfigure with -DPDFVIEW_ENABLE_PDFIUM=ON and PDFIUM_ROOT."];
#endif
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
