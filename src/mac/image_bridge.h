#pragma once

#import <AppKit/AppKit.h>

#include "core/document.h"

NSImage* PDFViewImageFromBitmap(const pdfview::core::Bitmap& bitmap, NSSize displaySize);
