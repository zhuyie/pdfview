#pragma once

#import <AppKit/AppKit.h>

#include <string>

#include "mac/tab_context.h"

@protocol PDFDocumentWorkspaceControllerDelegate <NSObject>

- (void)workspaceControllerDidAddContext:(PDFTabContext*)context;
- (void)workspaceControllerWillRemoveContext:(PDFTabContext*)context;
- (void)workspaceControllerSelectionDidChange:(PDFTabContext*)context;

@end

@interface PDFDocumentWorkspaceController : NSObject

- (instancetype)initWithHostView:(NSView*)hostView
                        delegate:(id<PDFDocumentWorkspaceControllerDelegate>)delegate;
- (NSArray<PDFTabContext*>*)tabContexts;
- (NSUInteger)tabCount;
- (PDFTabContext*)activeContext;
- (PDFTabContext*)contextForDocumentPath:(const std::string&)path;
- (PDFTabContext*)contextForClipView:(NSClipView*)clipView;
- (void)addContext:(PDFTabContext*)context makeActive:(BOOL)makeActive;
- (void)selectContext:(PDFTabContext*)context;
- (void)selectContextAtIndex:(NSInteger)index;
- (void)closeContext:(PDFTabContext*)context;

@end
