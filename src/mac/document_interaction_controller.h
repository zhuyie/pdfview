#pragma once

#import <AppKit/AppKit.h>

#include "mac/tab_context.h"

@protocol PDFDocumentInteractionControllerDelegate <NSObject>

- (BOOL)documentInteractionControllerIsContextActive:(PDFTabContext*)context;
- (void)documentInteractionControllerUpdateVisiblePagesForContext:(PDFTabContext*)context;
- (void)documentInteractionControllerUpdateCurrentPageFromScrollForContext:(PDFTabContext*)context;
- (BOOL)documentInteractionControllerPerformSelectionAutoScrollForContext:(PDFTabContext*)context
                                                                   deltaY:(CGFloat)deltaY;
- (void)documentInteractionControllerUpdateTextSelectionAtDocumentLocation:(NSPoint)documentLocation
                                                                   context:(PDFTabContext*)context;

@end

@interface PDFDocumentInteractionController : NSObject

- (instancetype)initWithDelegate:(id<PDFDocumentInteractionControllerDelegate>)delegate;
- (BOOL)shouldReduceInteractiveScaleForContext:(PDFTabContext*)context
                                   deviceScale:(CGFloat)deviceScale;
- (void)beginInteractiveRenderingForContext:(PDFTabContext*)context;
- (void)cancelInteractiveRendering;
- (void)showPageIndicatorForContext:(PDFTabContext*)context;
- (void)hidePageIndicator;
- (void)handleClipViewDidScrollForContext:(PDFTabContext*)context
                    suppressScrollTracking:(BOOL)suppressScrollTracking;
- (void)stopSelectionAutoScroll;
- (void)updateSelectionAutoScrollForDocumentLocation:(NSPoint)documentLocation
                                             context:(PDFTabContext*)context;

@end
