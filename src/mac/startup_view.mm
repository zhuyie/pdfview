#import "mac/startup_view.h"

namespace {

constexpr NSInteger kRecentsTitleTag = 1001;
constexpr CGFloat kContentWidth = 560.0f;
constexpr CGFloat kOpenPanelHeight = 132.0f;
constexpr CGFloat kOpenHeaderHeight = 28.0f;
constexpr CGFloat kRecentsHeaderHeight = 32.0f;
constexpr CGFloat kOpenHeaderSpacing = 8.0f;
constexpr CGFloat kSectionSpacing = 26.0f;
constexpr CGFloat kRecentsHeaderSpacing = 8.0f;
constexpr CGFloat kRowHeight = 44.0f;
constexpr CGFloat kRowGap = 10.0f;
constexpr CGFloat kListTopInset = 18.0f;
constexpr CGFloat kListBottomInset = 18.0f;
constexpr CGFloat kMaxVisibleRows = 5.0f;

}  // namespace

@interface PDFStartupView ()

- (void)layoutStartupView;
- (void)rebuildRecentsList;
- (IBAction)openSelectedRecentDocument:(id)sender;
- (IBAction)openDocument:(id)sender;
- (IBAction)clearRecents:(id)sender;

@end

@implementation PDFStartupView {
  id<PDFStartupViewDelegate> delegate_;
  NSView* openPanelView_;
  NSView* recentsListView_;
  NSButton* clearButton_;
  std::vector<std::string> recentDocumentPaths_;
}

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<PDFStartupViewDelegate>)delegate {
  self = [super initWithFrame:frame];
  if (self != nil) {
    delegate_ = delegate;
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self setWantsLayer:YES];
    [[self layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.96 alpha:1.0] CGColor]];

    NSTextField* openTitleLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    [openTitleLabel setEditable:NO];
    [openTitleLabel setBezeled:NO];
    [openTitleLabel setBordered:NO];
    [openTitleLabel setDrawsBackground:NO];
    [openTitleLabel setSelectable:NO];
    [openTitleLabel setStringValue:@"Open new document"];
    [openTitleLabel setFont:[NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold]];
    [openTitleLabel setTextColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
    [openTitleLabel setTag:1002];
    [self addSubview:openTitleLabel];

    openPanelView_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kContentWidth, kOpenPanelHeight)];
    [openPanelView_ setWantsLayer:YES];
    [[openPanelView_ layer] setCornerRadius:16.0f];
    [[openPanelView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] CGColor]];
    [[openPanelView_ layer] setBorderWidth:1.0f];
    [[openPanelView_ layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] CGColor]];
    [self addSubview:openPanelView_];

    NSButton* selectFileButton = [[NSButton alloc] initWithFrame:NSMakeRect(24, 48, 108, 30)];
    [selectFileButton setTitle:@"Select File"];
    [selectFileButton setBezelStyle:NSBezelStyleRounded];
    [selectFileButton setTarget:self];
    [selectFileButton setAction:@selector(openDocument:)];
    [openPanelView_ addSubview:selectFileButton];

    NSTextField* openHintLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 84, 220, 16)];
    [openHintLabel setEditable:NO];
    [openHintLabel setBezeled:NO];
    [openHintLabel setBordered:NO];
    [openHintLabel setDrawsBackground:NO];
    [openHintLabel setSelectable:NO];
    [openHintLabel setStringValue:@"Choose a PDF from disk, or drag one here."];
    [openHintLabel setFont:[NSFont systemFontOfSize:12.0]];
    [openHintLabel setTextColor:[NSColor colorWithCalibratedWhite:0.46 alpha:1.0]];
    [openPanelView_ addSubview:openHintLabel];

    NSImageView* openIconView = [[NSImageView alloc] initWithFrame:NSMakeRect(442, 18, 92, 92)];
    if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
      NSImage* icon = [NSImage imageWithSystemSymbolName:@"doc.text.image"
                               accessibilityDescription:@"Document"];
      if (icon != nil && [NSImageSymbolConfiguration class] != Nil) {
        icon = [icon imageWithSymbolConfiguration:
                    [NSImageSymbolConfiguration configurationWithPointSize:56.0
                                                                    weight:NSFontWeightLight]];
      }
      [openIconView setImage:icon];
      [openIconView setContentTintColor:[NSColor colorWithCalibratedWhite:0.65 alpha:1.0]];
    }
    [openIconView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [openPanelView_ addSubview:openIconView];

    NSTextField* recentsTitleLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
    [recentsTitleLabel setEditable:NO];
    [recentsTitleLabel setBezeled:NO];
    [recentsTitleLabel setBordered:NO];
    [recentsTitleLabel setDrawsBackground:NO];
    [recentsTitleLabel setSelectable:NO];
    [recentsTitleLabel setStringValue:@"Recents"];
    [recentsTitleLabel setFont:[NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold]];
    [recentsTitleLabel setTextColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
    [recentsTitleLabel setTag:kRecentsTitleTag];
    [self addSubview:recentsTitleLabel];

    clearButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 116, 28)];
    [clearButton_ setTitle:@"Clear Recents"];
    [clearButton_ setBezelStyle:NSBezelStyleRounded];
    [clearButton_ setTarget:self];
    [clearButton_ setAction:@selector(clearRecents:)];
    [self addSubview:clearButton_];

    recentsListView_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kContentWidth, 300)];
    [recentsListView_ setWantsLayer:YES];
    [[recentsListView_ layer] setCornerRadius:14.0f];
    [[recentsListView_ layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] CGColor]];
    [[recentsListView_ layer] setBorderWidth:1.0f];
    [[recentsListView_ layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] CGColor]];
    [self addSubview:recentsListView_];

    [self layoutStartupView];
    [self rebuildRecentsList];
  }
  return self;
}

- (void)setFrame:(NSRect)frame {
  [super setFrame:frame];
  [self layoutStartupView];
}

- (void)setRecentDocumentPaths:(const std::vector<std::string>&)documentPaths {
  recentDocumentPaths_ = documentPaths;
  [self rebuildRecentsList];
}

- (void)layoutStartupView {
  NSTextField* recentsTitleLabel = (NSTextField*)[self viewWithTag:kRecentsTitleTag];
  NSTextField* openTitleLabel = (NSTextField*)[self viewWithTag:1002];
  if (recentsTitleLabel == nil || openTitleLabel == nil) {
    return;
  }

  const NSRect bounds = [self bounds];
  const size_t visibleRowCount =
      std::min<size_t>(recentDocumentPaths_.empty() ? 1 : recentDocumentPaths_.size(),
                       static_cast<size_t>(kMaxVisibleRows));
  const CGFloat listHeight =
      recentDocumentPaths_.empty()
          ? 76.0f
          : kListTopInset + kListBottomInset +
                visibleRowCount * kRowHeight +
                std::max<CGFloat>(0.0f, static_cast<CGFloat>(visibleRowCount - 1)) * kRowGap;
  const CGFloat totalHeight =
      kOpenHeaderHeight + kOpenHeaderSpacing + kOpenPanelHeight +
      kSectionSpacing + kRecentsHeaderHeight + kRecentsHeaderSpacing + listHeight;
  const CGFloat originX = std::floor((NSWidth(bounds) - kContentWidth) * 0.5f);
  const CGFloat originY = std::floor((NSHeight(bounds) - totalHeight) * 0.5f);

  [openTitleLabel setFrame:NSMakeRect(originX,
                                      originY + listHeight + kRecentsHeaderHeight +
                                          kRecentsHeaderSpacing + kSectionSpacing +
                                          kOpenPanelHeight + kOpenHeaderSpacing + 2.0f,
                                      260.0f,
                                      24.0f)];
  [openPanelView_ setFrame:NSMakeRect(originX,
                                      originY + listHeight + kRecentsHeaderHeight +
                                          kRecentsHeaderSpacing + kSectionSpacing,
                                      kContentWidth,
                                      kOpenPanelHeight)];
  [recentsTitleLabel setFrame:NSMakeRect(originX,
                                         originY + listHeight + kRecentsHeaderSpacing + 2.0f,
                                         200.0f,
                                         28.0f)];
  [clearButton_ setFrame:NSMakeRect(originX + kContentWidth - 116.0f,
                                    originY + listHeight + kRecentsHeaderSpacing,
                                    116.0f,
                                    28.0f)];
  [recentsListView_ setFrame:NSMakeRect(originX, originY, kContentWidth, listHeight)];
}

- (void)rebuildRecentsList {
  [self layoutStartupView];
  [clearButton_ setEnabled:!recentDocumentPaths_.empty()];

  NSArray<NSView*>* subviews = [[recentsListView_ subviews] copy];
  for (NSView* subview in subviews) {
    [subview removeFromSuperview];
  }

  if (recentDocumentPaths_.empty()) {
    NSTextField* emptyLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(24, 26, 360, 22)];
    [emptyLabel setEditable:NO];
    [emptyLabel setBezeled:NO];
    [emptyLabel setBordered:NO];
    [emptyLabel setDrawsBackground:NO];
    [emptyLabel setSelectable:NO];
    [emptyLabel setStringValue:@"No recent documents yet."];
    [emptyLabel setFont:[NSFont systemFontOfSize:14.0]];
    [emptyLabel setTextColor:[NSColor colorWithCalibratedWhite:0.46 alpha:1.0]];
    [recentsListView_ addSubview:emptyLabel];
    return;
  }

  const CGFloat maxWidth = NSWidth([recentsListView_ bounds]) - 36.0f;
  for (size_t index = 0; index < recentDocumentPaths_.size(); ++index) {
    NSString* path = [NSString stringWithUTF8String:recentDocumentPaths_[index].c_str()];
    if (path == nil || [path length] == 0) {
      continue;
    }

    const CGFloat y = NSHeight([recentsListView_ bounds]) - kListTopInset - kRowHeight -
                      index * (kRowHeight + kRowGap);
    if (y < 16.0f) {
      break;
    }

    NSButton* rowButton =
        [[NSButton alloc] initWithFrame:NSMakeRect(18.0f, y, maxWidth, kRowHeight)];
    [rowButton setBezelStyle:NSBezelStyleRegularSquare];
    [rowButton setBordered:NO];
    [rowButton setButtonType:NSButtonTypeMomentaryPushIn];
    [rowButton setTarget:self];
    [rowButton setAction:@selector(openSelectedRecentDocument:)];
    [rowButton setTag:static_cast<NSInteger>(index)];
    [rowButton setTitle:@""];
    [rowButton setToolTip:path];
    [rowButton setWantsLayer:YES];
    [[rowButton layer] setCornerRadius:10.0f];
    [[rowButton layer] setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.97 alpha:1.0] CGColor]];
    [[rowButton layer] setBorderWidth:1.0f];
    [[rowButton layer] setBorderColor:[[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] CGColor]];
    [recentsListView_ addSubview:rowButton];

    NSTextField* nameLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(14.0f, 20.0f, maxWidth - 28.0f, 18.0f)];
    [nameLabel setEditable:NO];
    [nameLabel setBezeled:NO];
    [nameLabel setBordered:NO];
    [nameLabel setDrawsBackground:NO];
    [nameLabel setSelectable:NO];
    [nameLabel setStringValue:[path lastPathComponent]];
    [nameLabel setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium]];
    [nameLabel setTextColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
    [nameLabel setUsesSingleLineMode:YES];
    [[nameLabel cell] setWraps:NO];
    [[nameLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [rowButton addSubview:nameLabel];

    NSTextField* pathLabel =
        [[NSTextField alloc] initWithFrame:NSMakeRect(14.0f, 6.0f, maxWidth - 28.0f, 14.0f)];
    [pathLabel setEditable:NO];
    [pathLabel setBezeled:NO];
    [pathLabel setBordered:NO];
    [pathLabel setDrawsBackground:NO];
    [pathLabel setSelectable:NO];
    [pathLabel setStringValue:[path stringByDeletingLastPathComponent]];
    [pathLabel setFont:[NSFont systemFontOfSize:11.0]];
    [pathLabel setTextColor:[NSColor colorWithCalibratedWhite:0.47 alpha:1.0]];
    [pathLabel setUsesSingleLineMode:YES];
    [[pathLabel cell] setWraps:NO];
    [[pathLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [rowButton addSubview:pathLabel];
  }
}

- (IBAction)openSelectedRecentDocument:(id)sender {
  if (![sender isKindOfClass:[NSButton class]] || delegate_ == nil) {
    return;
  }

  [delegate_ startupViewDidRequestOpenRecentDocumentAtIndex:[(NSButton*)sender tag]];
}

- (IBAction)openDocument:(id)sender {
  (void)sender;
  [delegate_ startupViewDidRequestOpenDocument];
}

- (IBAction)clearRecents:(id)sender {
  (void)sender;
  [delegate_ startupViewDidRequestClearRecents];
}

@end
