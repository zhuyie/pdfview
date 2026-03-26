#pragma once

#import <AppKit/AppKit.h>

@protocol PDFDocumentDropViewDelegate <NSObject>

- (void)documentDropViewDidReceiveDocumentPaths:(NSArray<NSString*>*)paths;

@end

@interface PDFDocumentDropView : NSView

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFDocumentDropViewDelegate>)delegate;

@end
