#import "mac/drag_drop_utils.h"

NSArray<NSString*>* PDFViewPDFPathsFromDraggingInfo(id<NSDraggingInfo> draggingInfo) {
  NSPasteboard* pasteboard = [draggingInfo draggingPasteboard];
  NSArray<NSURL*>* urls =
      [pasteboard readObjectsForClasses:[NSArray arrayWithObject:[NSURL class]]
                                options:@{
                                  NSPasteboardURLReadingFileURLsOnlyKey : @YES
                                }];
  if (urls == nil || [urls count] == 0) {
    return [NSArray array];
  }

  NSMutableArray<NSString*>* pdfPaths = [NSMutableArray array];
  for (NSURL* url in urls) {
    if (![url isFileURL]) {
      continue;
    }

    NSString* path = [url path];
    if (path == nil) {
      continue;
    }

    NSString* pathExtension = [[path pathExtension] lowercaseString];
    if ([pathExtension isEqualToString:@"pdf"]) {
      [pdfPaths addObject:path];
    }
  }

  return pdfPaths;
}
