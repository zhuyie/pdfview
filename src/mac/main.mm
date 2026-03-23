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

@interface PDFTabContext : NSObject {
 @public
  pdfview::core::DocumentPtr document_;
  std::string documentPath_;
  NSScrollView* scrollView_;
  FlippedDocumentView* documentView_;
  NSMutableArray* pageImageViews_;
  std::vector<NSRect> pageFrames_;
  int currentPage_;
  float manualScale_;
  BOOL useFitScale_;
}

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame;
- (NSString*)tabTitle;

@end

@implementation PDFTabContext

- (instancetype)initWithDocument:(const pdfview::core::DocumentPtr&)document
                            path:(const std::string&)path
                           frame:(NSRect)frame {
  self = [super init];
  if (self != nil) {
    document_ = document;
    documentPath_ = path;
    currentPage_ = 0;
    manualScale_ = 1.0f;
    useFitScale_ = YES;
    pageImageViews_ = [[NSMutableArray alloc] init];

    scrollView_ = [[NSScrollView alloc] initWithFrame:frame];
    [scrollView_ setHasVerticalScroller:YES];
    [scrollView_ setHasHorizontalScroller:YES];
    [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scrollView_ setBorderType:NSNoBorder];
    [scrollView_ setBackgroundColor:[NSColor colorWithCalibratedWhite:0.92 alpha:1.0]];
    [[scrollView_ contentView] setPostsBoundsChangedNotifications:YES];

    documentView_ = [[FlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [documentView_ setWantsLayer:YES];
    [[documentView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
    [scrollView_ setDocumentView:documentView_];
  }
  return self;
}

- (NSString*)tabTitle {
  NSString* path = [NSString stringWithUTF8String:documentPath_.c_str()];
  return [path lastPathComponent];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTabViewDelegate>
- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv;
- (void)installMainMenu;
- (void)presentError:(NSString*)message;
- (NSImage*)imageFromBitmap:(const pdfview::core::Bitmap&)bitmap;
- (void)loadInitialDocuments;
- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive;
- (void)renderTabContext:(PDFTabContext*)context;
- (float)fitScaleForContext:(PDFTabContext*)context;
- (float)currentScaleForContext:(PDFTabContext*)context;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoomToFit;
- (void)goToNextPage;
- (void)goToPreviousPage;
- (void)scrollToCurrentPageInContext:(PDFTabContext*)context;
- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context;
- (void)installKeyMonitor;
- (PDFTabContext*)activeTabContext;
- (PDFTabContext*)contextForClipView:(NSClipView*)clipView;
- (IBAction)openDocument:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
@end

@implementation AppDelegate {
  NSWindow* window_;
  NSTabView* tabView_;
  NSMutableArray* tabContexts_;
  id keyMonitor_;
  int argc_;
  const char** argv_;
}

- (instancetype)initWithArgc:(int)argc argv:(const char*[])argv {
  self = [super init];
  if (self != nil) {
    argc_ = argc;
    argv_ = argv;
    keyMonitor_ = nil;
    tabContexts_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  NSRect frame = NSMakeRect(0, 0, 1080, 800);
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

  [self installMainMenu];

  NSView* contentView = [window_ contentView];
  tabView_ = [[NSTabView alloc] initWithFrame:[contentView bounds]];
  [tabView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [tabView_ setTabViewType:NSTopTabsBezelBorder];
  [tabView_ setDelegate:self];
  [contentView addSubview:tabView_];

  [self installKeyMonitor];
  [self loadInitialDocuments];
}

- (void)installMainMenu {
  NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

  NSMenuItem* appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:appMenuItem];
  NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"pdfview"];
  NSMenuItem* quitItem =
      [[NSMenuItem alloc] initWithTitle:@"Quit pdfview"
                                 action:@selector(terminate:)
                          keyEquivalent:@"q"];
  [appMenu addItem:quitItem];
  [appMenuItem setSubmenu:appMenu];

  NSMenuItem* fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:fileMenuItem];
  NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  NSMenuItem* openItem = [[NSMenuItem alloc] initWithTitle:@"Open..."
                                                    action:@selector(openDocument:)
                                             keyEquivalent:@"o"];
  [openItem setTarget:self];
  [fileMenu addItem:openItem];

  NSMenuItem* closeTabItem = [[NSMenuItem alloc] initWithTitle:@"Close Tab"
                                                        action:@selector(closeCurrentTab:)
                                                 keyEquivalent:@"w"];
  [closeTabItem setTarget:self];
  [fileMenu addItem:closeTabItem];
  [fileMenuItem setSubmenu:fileMenu];

  [NSApp setMainMenu:mainMenu];
}

- (void)presentError:(NSString*)message {
  NSAlert* alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSAlertStyleCritical];
  [alert setMessageText:@"pdfview"];
  [alert setInformativeText:message];
  [alert runModal];
}

- (void)loadInitialDocuments {
  for (int index = 1; index < argc_; ++index) {
    [self openDocumentAtPath:argv_[index] makeActive:index == argc_ - 1];
  }
}

- (void)openDocumentAtPath:(const std::string&)path makeActive:(BOOL)makeActive {
  const pdfview::core::OpenDocumentResult result = pdfview::core::open_document(path);
  if (!result.ok()) {
    [self presentError:[NSString stringWithFormat:@"Failed to open PDF: %s", result.error.c_str()]];
    return;
  }

  PDFTabContext* context =
      [[PDFTabContext alloc] initWithDocument:result.document
                                         path:path
                                        frame:[tabView_ contentRect]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(tabClipViewDidScroll:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:[context->scrollView_ contentView]];

  NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:context];
  [item setLabel:[context tabTitle]];
  [item setView:context->scrollView_];
  [tabContexts_ addObject:context];
  [tabView_ addTabViewItem:item];

  [self renderTabContext:context];

  if (makeActive || [tabView_ numberOfTabViewItems] == 1) {
    [tabView_ selectTabViewItem:item];
  }
}

- (IBAction)openDocument:(id)sender {
  (void)sender;
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:YES];
  [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"pdf", nil]];

  if ([panel runModal] != NSModalResponseOK) {
    return;
  }

  for (NSURL* url in [panel URLs]) {
    [self openDocumentAtPath:[[url path] UTF8String] makeActive:YES];
  }
}

- (IBAction)closeCurrentTab:(id)sender {
  (void)sender;
  NSTabViewItem* selectedItem = [tabView_ selectedTabViewItem];
  if (selectedItem == nil) {
    return;
  }

  PDFTabContext* context = (PDFTabContext*)[selectedItem identifier];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:[context->scrollView_ contentView]];
  [tabContexts_ removeObject:context];
  [tabView_ removeTabViewItem:selectedItem];

  if ([tabView_ numberOfTabViewItems] == 0) {
    [window_ setTitle:@"pdfview"];
  }
}

- (PDFTabContext*)activeTabContext {
  NSTabViewItem* item = [tabView_ selectedTabViewItem];
  if (item == nil) {
    return nil;
  }
  return (PDFTabContext*)[item identifier];
}

- (PDFTabContext*)contextForClipView:(NSClipView*)clipView {
  for (PDFTabContext* context in tabContexts_) {
    if ([context->scrollView_ contentView] == clipView) {
      return context;
    }
  }
  return nil;
}

- (void)renderTabContext:(PDFTabContext*)context {
  if (context == nil || !context->document_) {
    return;
  }

  for (NSView* view in context->pageImageViews_) {
    [view removeFromSuperview];
  }
  [context->pageImageViews_ removeAllObjects];
  context->pageFrames_.clear();

  const float scale = [self currentScaleForContext:context];
  const CGFloat pageGap = 24.0f;
  const CGFloat topMargin = 20.0f;
  const CGFloat sideMargin = 16.0f;
  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;

  CGFloat documentWidth = clipSize.width;
  CGFloat maxPageWidth = 0.0f;
  CGFloat cursorY = topMargin;

  const int pageCount = context->document_->page_count();
  for (int pageIndex = 0; pageIndex < pageCount; ++pageIndex) {
    const pdfview::core::RenderPageResult renderResult =
        context->document_->render_page(pageIndex, scale);
    if (!renderResult.ok()) {
      [self presentError:[NSString stringWithFormat:@"Failed to render page %d: %s",
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

    const CGFloat pageX =
        std::max((clipSize.width - renderResult.bitmap.width) * 0.5, sideMargin);
    const NSRect pageFrame =
        NSMakeRect(pageX, cursorY, renderResult.bitmap.width, renderResult.bitmap.height);
    [imageView setFrame:pageFrame];
    [context->documentView_ addSubview:imageView];
    [context->pageImageViews_ addObject:imageView];
    context->pageFrames_.push_back(pageFrame);

    cursorY += renderResult.bitmap.height + pageGap;
    documentWidth =
        std::max(documentWidth, pageFrame.origin.x + pageFrame.size.width + sideMargin);
    maxPageWidth = std::max(maxPageWidth, static_cast<CGFloat>(renderResult.bitmap.width));
  }

  const CGFloat documentHeight = std::max(cursorY, clipSize.height);
  [context->documentView_
      setFrame:NSMakeRect(0,
                          0,
                          std::max(documentWidth, maxPageWidth + sideMargin * 2.0f),
                          documentHeight)];
}

- (float)fitScaleForContext:(PDFTabContext*)context {
  if (context == nil || !context->document_ || context->document_->page_count() <= 0) {
    return 1.0f;
  }

  float maxPageWidth = 0.0f;
  for (int pageIndex = 0; pageIndex < context->document_->page_count(); ++pageIndex) {
    const pdfview::core::PageSize pageSize = context->document_->page_size(pageIndex);
    maxPageWidth = std::max(maxPageWidth, pageSize.width);
  }

  if (maxPageWidth <= 0.0f) {
    return 1.0f;
  }

  const NSSize clipSize = [[context->scrollView_ contentView] bounds].size;
  const float horizontalPadding = 48.0f;
  const float targetWidth = std::max(clipSize.width - horizontalPadding, 120.0);
  const float scale = targetWidth / maxPageWidth;
  return std::max(0.25f, scale);
}

- (float)currentScaleForContext:(PDFTabContext*)context {
  if (context->useFitScale_) {
    return [self fitScaleForContext:context];
  }
  return std::max(0.1f, context->manualScale_);
}

- (void)zoomIn {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  context->manualScale_ = std::min([self currentScaleForContext:context] * 1.25f, 5.0f);
  context->useFitScale_ = NO;
  [self renderTabContext:context];
  [self scrollToCurrentPageInContext:context];
}

- (void)zoomOut {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  context->manualScale_ = std::max([self currentScaleForContext:context] / 1.25f, 0.1f);
  context->useFitScale_ = NO;
  [self renderTabContext:context];
  [self scrollToCurrentPageInContext:context];
}

- (void)resetZoomToFit {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil) {
    return;
  }

  context->useFitScale_ = YES;
  [self renderTabContext:context];
  [self scrollToCurrentPageInContext:context];
}

- (void)goToNextPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil || context->currentPage_ + 1 >= context->document_->page_count()) {
    return;
  }

  context->currentPage_ += 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)goToPreviousPage {
  PDFTabContext* context = [self activeTabContext];
  if (context == nil || context->currentPage_ <= 0) {
    return;
  }

  context->currentPage_ -= 1;
  [self scrollToCurrentPageInContext:context];
}

- (void)scrollToCurrentPageInContext:(PDFTabContext*)context {
  if (context == nil ||
      context->currentPage_ < 0 ||
      context->currentPage_ >= static_cast<int>(context->pageFrames_.size())) {
    return;
  }

  const NSRect pageFrame = context->pageFrames_[context->currentPage_];
  [[context->scrollView_ documentView] scrollRectToVisible:pageFrame];
}

- (void)updateCurrentPageFromScrollForContext:(PDFTabContext*)context {
  if (context == nil || context->pageFrames_.empty()) {
    return;
  }

  const NSRect visibleRect = [[context->scrollView_ contentView] bounds];
  const CGFloat visibleCenterY = visibleRect.origin.y + visibleRect.size.height * 0.5f;

  int nearestPage = 0;
  CGFloat nearestDistance = CGFLOAT_MAX;
  for (int pageIndex = 0; pageIndex < static_cast<int>(context->pageFrames_.size()); ++pageIndex) {
    const NSRect pageFrame = context->pageFrames_[pageIndex];
    const CGFloat pageCenterY = pageFrame.origin.y + pageFrame.size.height * 0.5f;
    const CGFloat distance = std::abs(pageCenterY - visibleCenterY);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestPage = pageIndex;
    }
  }

  context->currentPage_ = nearestPage;
}

- (void)tabClipViewDidScroll:(NSNotification*)notification {
  PDFTabContext* context = [self contextForClipView:(NSClipView*)[notification object]];
  [self updateCurrentPageFromScrollForContext:context];
}

- (void)installKeyMonitor {
  keyMonitor_ = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                      handler:^NSEvent*(NSEvent* event) {
    PDFTabContext* context = [self activeTabContext];
    if (context == nil) {
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

- (void)tabView:(NSTabView*)tabView didSelectTabViewItem:(NSTabViewItem*)tabViewItem {
  (void)tabView;
  PDFTabContext* context = (PDFTabContext*)[tabViewItem identifier];
  if (context != nil) {
    [window_ setTitle:[NSString stringWithFormat:@"pdfview - %@", [context tabTitle]]];
  }
}

- (void)windowDidResize:(NSNotification*)notification {
  (void)notification;
  for (PDFTabContext* context in tabContexts_) {
    if (context->useFitScale_) {
      [self renderTabContext:context];
      [self scrollToCurrentPageInContext:context];
    }
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
