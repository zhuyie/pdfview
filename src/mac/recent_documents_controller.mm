#import "mac/recent_documents_controller.h"

#include "core/recent_documents.h"

@interface PDFRecentDocumentsController ()

- (void)rebuildMenu;
- (IBAction)openRecentDocument:(id)sender;
- (IBAction)clearMenu:(id)sender;

@end

@implementation PDFRecentDocumentsController {
  id<PDFRecentDocumentsControllerDelegate> delegate_;
  NSMenu* menu_;
  std::vector<std::string> recentDocumentPaths_;
}

- (instancetype)initWithDelegate:(id<PDFRecentDocumentsControllerDelegate>)delegate {
  self = [super init];
  if (self != nil) {
    delegate_ = delegate;
    menu_ = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    recentDocumentPaths_ = pdfview::core::load_recent_documents();
    [self rebuildMenu];
  }
  return self;
}

- (NSMenu*)menu {
  return menu_;
}

- (const std::vector<std::string>&)recentDocumentPaths {
  return recentDocumentPaths_;
}

- (void)noteOpenedDocumentPath:(const std::string&)path {
  recentDocumentPaths_ = pdfview::core::note_recent_document(recentDocumentPaths_, path);
  pdfview::core::save_recent_documents(recentDocumentPaths_);
  [self rebuildMenu];
}

- (void)clearRecentDocuments {
  recentDocumentPaths_.clear();
  pdfview::core::save_recent_documents(recentDocumentPaths_);
  [self rebuildMenu];
}

- (void)rebuildMenu {
  [menu_ removeAllItems];

  if (recentDocumentPaths_.empty()) {
    NSMenuItem* emptyItem =
        [[NSMenuItem alloc] initWithTitle:@"No Recent Documents" action:nil keyEquivalent:@""];
    [emptyItem setEnabled:NO];
    [menu_ addItem:emptyItem];
    return;
  }

  for (size_t index = 0; index < recentDocumentPaths_.size(); ++index) {
    NSString* path = [NSString stringWithUTF8String:recentDocumentPaths_[index].c_str()];
    if (path == nil || [path length] == 0) {
      continue;
    }
    NSMenuItem* item =
        [[NSMenuItem alloc] initWithTitle:[path lastPathComponent]
                                   action:@selector(openRecentDocument:)
                            keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:path];
    [item setToolTip:path];
    [menu_ addItem:item];
  }

  [menu_ addItem:[NSMenuItem separatorItem]];
  NSMenuItem* clearItem =
      [[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                 action:@selector(clearMenu:)
                          keyEquivalent:@""];
  [clearItem setTarget:self];
  [menu_ addItem:clearItem];
}

- (IBAction)openRecentDocument:(id)sender {
  if (![sender isKindOfClass:[NSMenuItem class]] || delegate_ == nil) {
    return;
  }

  NSString* path = [(NSMenuItem*)sender representedObject];
  if (path == nil || [path length] == 0) {
    return;
  }

  [delegate_ recentDocumentsControllerDidRequestOpenDocumentAtPath:path];
}

- (IBAction)clearMenu:(id)sender {
  (void)sender;
  [self clearRecentDocuments];
}

@end
