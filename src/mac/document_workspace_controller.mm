#import "mac/document_workspace_controller.h"

#include <algorithm>

#include "core/document_paths.h"

@implementation PDFDocumentWorkspaceController {
  NSView* hostView_;
  id<PDFDocumentWorkspaceControllerDelegate> delegate_;
  NSMutableArray* tabContexts_;
  PDFTabContext* selectedTabContext_;
}

- (instancetype)initWithHostView:(NSView*)hostView
                        delegate:(id<PDFDocumentWorkspaceControllerDelegate>)delegate {
  self = [super init];
  if (self != nil) {
    hostView_ = hostView;
    delegate_ = delegate;
    tabContexts_ = [[NSMutableArray alloc] init];
    selectedTabContext_ = nil;
  }
  return self;
}

- (NSArray<PDFTabContext*>*)tabContexts {
  return tabContexts_;
}

- (NSUInteger)tabCount {
  return [tabContexts_ count];
}

- (PDFTabContext*)activeContext {
  return selectedTabContext_;
}

- (PDFTabContext*)contextForDocumentPath:(const std::string&)path {
  for (PDFTabContext* context in tabContexts_) {
    if (pdfview::core::same_document_path(context->documentPath_, path)) {
      return context;
    }
  }
  return nil;
}

- (PDFTabContext*)contextForClipView:(NSClipView*)clipView {
  for (PDFTabContext* context in tabContexts_) {
    if ([context->scrollView_ contentView] == clipView) {
      return context;
    }
  }
  return nil;
}

- (void)addContext:(PDFTabContext*)context makeActive:(BOOL)makeActive {
  if (context == nil) {
    return;
  }

  [tabContexts_ addObject:context];
  [hostView_ addSubview:context->containerView_];
  [context->containerView_ setHidden:YES];
  if (delegate_ != nil) {
    [delegate_ workspaceControllerDidAddContext:context];
  }

  if (makeActive || [tabContexts_ count] == 1) {
    [self selectContext:context];
  }
}

- (void)selectContextAtIndex:(NSInteger)index {
  if (index < 0 || index >= [tabContexts_ count]) {
    return;
  }
  [self selectContext:[tabContexts_ objectAtIndex:index]];
}

- (void)selectContext:(PDFTabContext*)context {
  selectedTabContext_ = context;
  for (PDFTabContext* tabContext in tabContexts_) {
    [tabContext->containerView_ setHidden:tabContext != selectedTabContext_];
  }
  if (delegate_ != nil) {
    [delegate_ workspaceControllerSelectionDidChange:context];
  }
}

- (void)closeContext:(PDFTabContext*)context {
  if (context == nil) {
    return;
  }

  const NSUInteger closingIndex = [tabContexts_ indexOfObjectIdenticalTo:context];
  if (closingIndex == NSNotFound) {
    return;
  }

  if (delegate_ != nil) {
    [delegate_ workspaceControllerWillRemoveContext:context];
  }

  const BOOL wasSelected = selectedTabContext_ == context;
  [context->containerView_ removeFromSuperview];
  [tabContexts_ removeObjectAtIndex:closingIndex];

  if ([tabContexts_ count] == 0) {
    [self selectContext:nil];
    return;
  }

  if (wasSelected) {
    const NSUInteger fallbackIndex = std::min(closingIndex, [tabContexts_ count] - 1);
    [self selectContext:[tabContexts_ objectAtIndex:fallbackIndex]];
    return;
  }

  if (delegate_ != nil) {
    [delegate_ workspaceControllerSelectionDidChange:selectedTabContext_];
  }
}

@end
