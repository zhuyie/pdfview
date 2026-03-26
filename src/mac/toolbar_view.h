#pragma once

#import <AppKit/AppKit.h>

@protocol PDFToolbarViewDelegate <NSObject>

- (void)toolbarViewDidRequestZoomOut;
- (void)toolbarViewDidRequestZoomIn;
- (void)toolbarViewDidRequestZoomActual;
- (void)toolbarViewDidRequestFitWidth;
- (void)toolbarViewDidRequestFitPage;
- (void)toolbarViewDidSubmitZoomString:(NSString*)zoomString;

@end

@interface PDFToolbarView : NSView

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFToolbarViewDelegate>)delegate;
- (void)showEmptyState;
- (void)updateWithCurrentScale:(float)currentScale
                  minimumScale:(float)minimumScale
                  maximumScale:(float)maximumScale
                fitWidthActive:(BOOL)fitWidthActive
                 fitPageActive:(BOOL)fitPageActive;
- (BOOL)isEditingZoomField;
- (BOOL)ownsFirstResponder:(NSResponder*)responder;

@end
