#import "mac/document_drop_view.h"

#import "mac/drag_drop_utils.h"

@interface PDFDocumentDropView () <NSDraggingDestination>

- (void)setDropHighlighted:(BOOL)highlighted;

@end

@implementation PDFDocumentDropView {
  id<PDFDocumentDropViewDelegate> delegate_;
  NSView* highlightOverlayView_;
}

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFDocumentDropViewDelegate>)delegate {
  self = [super initWithFrame:frame];
  if (self != nil) {
    delegate_ = delegate;
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self setWantsLayer:YES];
    [[self layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor]];
    [self registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeFileURL]];

    highlightOverlayView_ = [[NSView alloc] initWithFrame:[self bounds]];
    [highlightOverlayView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [highlightOverlayView_ setWantsLayer:YES];
    [[highlightOverlayView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedRed:0.82 green:0.89 blue:1.0 alpha:0.22] CGColor]];
    [[highlightOverlayView_ layer] setBorderColor:[[NSColor colorWithCalibratedRed:0.35 green:0.55 blue:0.92 alpha:0.95] CGColor]];
    [[highlightOverlayView_ layer] setBorderWidth:2.0f];
    [[highlightOverlayView_ layer] setCornerRadius:8.0f];
    [highlightOverlayView_ setHidden:YES];
    [self addSubview:highlightOverlayView_ positioned:NSWindowAbove relativeTo:nil];
  }
  return self;
}

- (void)setDropHighlighted:(BOOL)highlighted {
  if (highlightOverlayView_ == nil) {
    return;
  }

  [highlightOverlayView_ setHidden:!highlighted];
  if (highlighted) {
    [self addSubview:highlightOverlayView_ positioned:NSWindowAbove relativeTo:nil];
  }
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  const BOOL acceptsDrop = [PDFViewPDFPathsFromDraggingInfo(sender) count] > 0;
  [self setDropHighlighted:acceptsDrop];
  return acceptsDrop ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
  const BOOL acceptsDrop = [PDFViewPDFPathsFromDraggingInfo(sender) count] > 0;
  [self setDropHighlighted:acceptsDrop];
  return acceptsDrop ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  (void)sender;
  [self setDropHighlighted:NO];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  return [PDFViewPDFPathsFromDraggingInfo(sender) count] > 0;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  NSArray<NSString*>* paths = PDFViewPDFPathsFromDraggingInfo(sender);
  [self setDropHighlighted:NO];
  if ([paths count] == 0 || delegate_ == nil) {
    return NO;
  }

  [delegate_ documentDropViewDidReceiveDocumentPaths:paths];
  return YES;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
  (void)sender;
  [self setDropHighlighted:NO];
}

@end
