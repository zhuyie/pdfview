#pragma once

#import <AppKit/AppKit.h>

@protocol PDFZoomToolbarViewDelegate <NSObject>

- (void)zoomToolbarViewDidRequestZoomOut;
- (void)zoomToolbarViewDidRequestZoomIn;
- (void)zoomToolbarViewDidRequestZoomActual;
- (void)zoomToolbarViewDidRequestFitWidth;
- (void)zoomToolbarViewDidRequestFitPage;
- (void)zoomToolbarViewDidSubmitZoomString:(NSString*)zoomString;

@end

@interface PDFZoomToolbarView : NSView

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFZoomToolbarViewDelegate>)delegate;
- (void)showEmptyState;
- (void)updateWithCurrentScale:(float)currentScale
                  minimumScale:(float)minimumScale
                  maximumScale:(float)maximumScale
                fitWidthActive:(BOOL)fitWidthActive
                 fitPageActive:(BOOL)fitPageActive;
- (BOOL)isEditingZoomField;
- (BOOL)ownsFirstResponder:(NSResponder*)responder;

@end
