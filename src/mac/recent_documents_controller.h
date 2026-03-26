#pragma once

#import <AppKit/AppKit.h>

#include <string>
#include <vector>

@protocol PDFRecentDocumentsControllerDelegate <NSObject>

- (void)recentDocumentsControllerDidRequestOpenDocumentAtPath:(NSString*)path;

@end

@interface PDFRecentDocumentsController : NSObject

- (instancetype)initWithDelegate:(id<PDFRecentDocumentsControllerDelegate>)delegate;
- (NSMenu*)menu;
- (const std::vector<std::string>&)recentDocumentPaths;
- (void)noteOpenedDocumentPath:(const std::string&)path;
- (void)clearRecentDocuments;

@end
