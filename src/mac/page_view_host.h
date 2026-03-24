#pragma once

#import <AppKit/AppKit.h>

#include <vector>

#include "core/viewport.h"

@interface PDFPageViewHost : NSObject

- (instancetype)initWithDocumentView:(NSView*)documentView
                      pageImageViews:(std::vector<NSImageView*>*)pageImageViews;
- (void)syncPageFrames:(const std::vector<pdfview::core::ViewRect>&)pageFrames;
- (void)clearPageImageAtIndex:(int)pageIndex;
- (void)applyPageImage:(NSImage*)image atIndex:(int)pageIndex;

@end
