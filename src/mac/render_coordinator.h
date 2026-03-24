#pragma once

#import <AppKit/AppKit.h>

#include "core/document.h"
#include "mac/tab_context.h"

@protocol PDFRenderCoordinatorDelegate <NSObject>
- (void)presentError:(NSString*)message;
@end

@interface PDFRenderCoordinator : NSObject

- (instancetype)initWithDelegate:(id<PDFRenderCoordinatorDelegate>)delegate;
- (void)updateVisiblePagesForContext:(PDFTabContext*)context
                            isActive:(BOOL)isActive
                         deviceScale:(CGFloat)deviceScale;

@end
