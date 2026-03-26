#pragma once

#import <AppKit/AppKit.h>

#include <string>
#include <vector>

@protocol PDFStartupViewDelegate <NSObject>

- (void)startupViewDidRequestOpenDocument;
- (void)startupViewDidRequestOpenDocumentAtPaths:(NSArray<NSString*>*)paths;
- (void)startupViewDidRequestOpenRecentDocumentAtIndex:(NSInteger)index;
- (void)startupViewDidRequestClearRecents;

@end

@interface PDFStartupView : NSView

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFStartupViewDelegate>)delegate;
- (void)setRecentDocumentPaths:(const std::vector<std::string>&)documentPaths;

@end
