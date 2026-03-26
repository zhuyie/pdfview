#pragma once

#import <AppKit/AppKit.h>

#include "mac/tab_context.h"

@interface PDFTextSelectionController : NSObject

- (int)textIndexForPageSelectionAtPageIndex:(int)pageIndex
                                   location:(NSPoint)location
                                    context:(PDFTabContext*)context;
- (void)updateTextSelectionAtPageIndex:(int)pageIndex
                              location:(NSPoint)location
                               context:(PDFTabContext*)context;
- (void)refreshTextSelectionAtDocumentLocation:(NSPoint)documentLocation
                                       context:(PDFTabContext*)context;
- (void)selectWordAtPageIndex:(int)pageIndex
                     location:(NSPoint)location
                      context:(PDFTabContext*)context;
- (BOOL)selectAllTextInContext:(PDFTabContext*)context;

@end
