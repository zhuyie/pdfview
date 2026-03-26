#pragma once

#import <AppKit/AppKit.h>

@protocol PDFTabStripViewDelegate <NSObject>

- (void)tabStripViewDidSelectTabAtIndex:(NSInteger)index;
- (void)tabStripViewDidCloseTabAtIndex:(NSInteger)index;

@end

@interface PDFTabStripView : NSView

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFTabStripViewDelegate>)delegate;
- (void)setTabTitles:(NSArray<NSString*>*)tabTitles selectedIndex:(NSInteger)selectedIndex;
- (void)ensureSelectedTabVisibleOnNextLayout;

@end
