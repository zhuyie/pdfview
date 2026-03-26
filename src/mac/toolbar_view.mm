#import "mac/toolbar_view.h"

#include <cmath>

namespace {

NSButton* MakeToolbarSymbolButton(NSRect frame,
                                  NSString* symbolName,
                                  NSString* fallbackTitle,
                                  id target,
                                  SEL action,
                                  NSString* toolTip) {
  NSButton* button = [[NSButton alloc] initWithFrame:frame];
  [button setBezelStyle:NSBezelStyleTexturedRounded];
  [button setTarget:target];
  [button setAction:action];
  [button setToolTip:toolTip];

  NSImage* symbolImage = nil;
  if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
    symbolImage = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:toolTip];
  }

  if (symbolImage != nil) {
    if ([NSImageSymbolConfiguration class] != Nil) {
      NSImageSymbolConfiguration* configuration =
          [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightSemibold];
      symbolImage = [symbolImage imageWithSymbolConfiguration:configuration];
    }
    [button setImage:symbolImage];
    [button setImagePosition:NSImageOnly];
  } else {
    [button setTitle:fallbackTitle];
  }

  return button;
}

}  // namespace

@interface PDFToolbarView () <NSComboBoxDelegate, NSTextFieldDelegate>

- (IBAction)zoomComboBoxChanged:(id)sender;
- (BOOL)applyPendingZoomString;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomActual:(id)sender;
- (IBAction)fitWidth:(id)sender;
- (IBAction)fitPage:(id)sender;

@end

@implementation PDFToolbarView {
  id<PDFToolbarViewDelegate> delegate_;
  NSComboBox* zoomComboBox_;
  NSButton* zoomOutButton_;
  NSButton* zoomInButton_;
  NSButton* zoomActualButton_;
  NSButton* fitWidthButton_;
  NSButton* fitPageButton_;
  BOOL zoomComboBoxEditing_;
}

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFToolbarViewDelegate>)delegate {
  self = [super initWithFrame:frame];
  if (self != nil) {
    delegate_ = delegate;
    zoomComboBoxEditing_ = NO;

    [self setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self setWantsLayer:YES];
    [[self layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.965 alpha:1.0] CGColor]];

    NSBox* divider = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
    [divider setBoxType:NSBoxSeparator];
    [divider setAutoresizingMask:NSViewWidthSizable];
    [self addSubview:divider];

    zoomOutButton_ = MakeToolbarSymbolButton(NSMakeRect(14, 4, 32, 22),
                                             @"minus",
                                             @"-",
                                             self,
                                             @selector(zoomOut:),
                                             @"Zoom Out");
    [self addSubview:zoomOutButton_];

    zoomComboBox_ = [[NSComboBox alloc] initWithFrame:NSMakeRect(54, 4, 74, 24)];
    [zoomComboBox_ addItemsWithObjectValues:[NSArray arrayWithObjects:@"50%", @"75%", @"100%", @"125%", @"150%", @"200%", nil]];
    [zoomComboBox_ setUsesDataSource:NO];
    [zoomComboBox_ setCompletes:NO];
    [zoomComboBox_ setEditable:YES];
    [zoomComboBox_ setDelegate:self];
    [zoomComboBox_ setTarget:self];
    [zoomComboBox_ setAction:@selector(zoomComboBoxChanged:)];
    [[zoomComboBox_ cell] setLineBreakMode:NSLineBreakByClipping];
    [self addSubview:zoomComboBox_];

    zoomInButton_ = MakeToolbarSymbolButton(NSMakeRect(136, 4, 32, 22),
                                            @"plus",
                                            @"+",
                                            self,
                                            @selector(zoomIn:),
                                            @"Zoom In");
    [self addSubview:zoomInButton_];

    zoomActualButton_ = MakeToolbarSymbolButton(NSMakeRect(182, 4, 32, 22),
                                                @"1.circle",
                                                @"100%",
                                                self,
                                                @selector(zoomActual:),
                                                @"Zoom to 100%");
    [self addSubview:zoomActualButton_];

    fitWidthButton_ = MakeToolbarSymbolButton(NSMakeRect(226, 4, 32, 22),
                                              @"arrow.left.and.right.righttriangle.left.righttriangle.right",
                                              @"Width",
                                              self,
                                              @selector(fitWidth:),
                                              @"Fit Width");
    [self addSubview:fitWidthButton_];

    fitPageButton_ = MakeToolbarSymbolButton(NSMakeRect(270, 4, 32, 22),
                                             @"document",
                                             @"Page",
                                             self,
                                             @selector(fitPage:),
                                             @"Fit Page");
    [self addSubview:fitPageButton_];

    [self showEmptyState];
  }
  return self;
}

- (void)showEmptyState {
  zoomComboBoxEditing_ = NO;
  [zoomComboBox_ setStringValue:@""];
  [zoomComboBox_ setEnabled:NO];
  [zoomOutButton_ setEnabled:NO];
  [zoomInButton_ setEnabled:NO];
  [zoomActualButton_ setEnabled:NO];
  [fitWidthButton_ setEnabled:NO];
  [fitPageButton_ setEnabled:NO];
  [fitWidthButton_ setState:NSControlStateValueOff];
  [fitPageButton_ setState:NSControlStateValueOff];
}

- (void)updateWithCurrentScale:(float)currentScale
                  minimumScale:(float)minimumScale
                  maximumScale:(float)maximumScale
                fitWidthActive:(BOOL)fitWidthActive
                 fitPageActive:(BOOL)fitPageActive {
  if (!zoomComboBoxEditing_) {
    [zoomComboBox_ setStringValue:[NSString stringWithFormat:@"%.0f%%", currentScale * 100.0f]];
  }
  [zoomComboBox_ setEnabled:YES];
  [zoomOutButton_ setEnabled:currentScale > minimumScale + 0.001f];
  [zoomInButton_ setEnabled:currentScale < maximumScale - 0.001f];
  [zoomActualButton_ setEnabled:std::abs(currentScale - 1.0f) > 0.001f];
  [fitWidthButton_ setEnabled:YES];
  [fitPageButton_ setEnabled:YES];
  [fitWidthButton_ setState:fitWidthActive ? NSControlStateValueOn : NSControlStateValueOff];
  [fitPageButton_ setState:fitPageActive ? NSControlStateValueOn : NSControlStateValueOff];
}

- (BOOL)isEditingZoomField {
  return zoomComboBoxEditing_;
}

- (BOOL)ownsFirstResponder:(NSResponder*)responder {
  if ([responder isKindOfClass:[NSTextView class]]) {
    NSTextView* textView = (NSTextView*)responder;
    return [textView delegate] == (id)zoomComboBox_;
  }
  return responder == zoomComboBox_;
}

- (IBAction)zoomComboBoxChanged:(id)sender {
  (void)sender;
}

- (void)comboBoxSelectionDidChange:(NSNotification*)notification {
  if ([notification object] != zoomComboBox_) {
    return;
  }

  zoomComboBoxEditing_ = NO;
  const NSInteger selectedIndex = [zoomComboBox_ indexOfSelectedItem];
  if (selectedIndex >= 0) {
    id value = [zoomComboBox_ objectValueOfSelectedItem];
    if ([value isKindOfClass:[NSString class]] && delegate_ != nil) {
      [delegate_ toolbarViewDidSubmitZoomString:(NSString*)value];
    }
  }
}

- (void)controlTextDidBeginEditing:(NSNotification*)notification {
  if ([notification object] == zoomComboBox_) {
    zoomComboBoxEditing_ = YES;
  }
}

- (void)controlTextDidEndEditing:(NSNotification*)notification {
  if ([notification object] == zoomComboBox_) {
    zoomComboBoxEditing_ = NO;
  }
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
  (void)textView;
  if (control != zoomComboBox_) {
    return NO;
  }

  if (commandSelector == @selector(insertNewline:)) {
    zoomComboBoxEditing_ = NO;
    return [self applyPendingZoomString];
  }

  if (commandSelector == @selector(cancelOperation:)) {
    zoomComboBoxEditing_ = NO;
    return YES;
  }

  return NO;
}

- (BOOL)applyPendingZoomString {
  if (delegate_ == nil) {
    return NO;
  }

  [delegate_ toolbarViewDidSubmitZoomString:[zoomComboBox_ stringValue]];
  [[self window] makeFirstResponder:nil];
  return YES;
}

- (IBAction)zoomOut:(id)sender {
  (void)sender;
  if (delegate_ != nil) {
    [delegate_ toolbarViewDidRequestZoomOut];
  }
}

- (IBAction)zoomIn:(id)sender {
  (void)sender;
  if (delegate_ != nil) {
    [delegate_ toolbarViewDidRequestZoomIn];
  }
}

- (IBAction)zoomActual:(id)sender {
  (void)sender;
  if (delegate_ != nil) {
    [delegate_ toolbarViewDidRequestZoomActual];
  }
}

- (IBAction)fitWidth:(id)sender {
  (void)sender;
  if (delegate_ != nil) {
    [delegate_ toolbarViewDidRequestFitWidth];
  }
}

- (IBAction)fitPage:(id)sender {
  (void)sender;
  if (delegate_ != nil) {
    [delegate_ toolbarViewDidRequestFitPage];
  }
}

@end
