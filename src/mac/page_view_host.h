#pragma once

#import <AppKit/AppKit.h>

#include <vector>

#include "core/viewport.h"

@protocol PDFPageViewHostDelegate <NSObject>

- (void)pageViewHostDidBeginTextSelectionAtPageIndex:(int)pageIndex
                                            location:(NSPoint)location;
- (void)pageViewHostDidDoubleClickTextAtPageIndex:(int)pageIndex
                                         location:(NSPoint)location;
- (void)pageViewHostDidUpdateTextSelectionAtPageIndex:(int)pageIndex
                                             location:(NSPoint)location;
- (void)pageViewHostDidEndTextSelectionAtPageIndex:(int)pageIndex
                                          location:(NSPoint)location;

@end

@interface PDFPageViewHost : NSObject

- (instancetype)initWithDocumentView:(NSView*)documentView
                      pageImageViews:(std::vector<NSImageView*>*)pageImageViews
                            delegate:(id<PDFPageViewHostDelegate>)delegate;
- (void)syncPageFrames:(const std::vector<pdfview::core::ViewRect>&)pageFrames;
- (void)clearPageImageAtIndex:(int)pageIndex;
- (void)applyPageImage:(NSImage*)image atIndex:(int)pageIndex;
- (void)setSelectionRects:(const std::vector<pdfview::core::ViewRect>&)selectionRects
                  atIndex:(int)pageIndex;
- (void)clearSelectionAtIndex:(int)pageIndex;

@end
