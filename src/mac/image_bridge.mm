#import "mac/image_bridge.h"

#include <CoreGraphics/CoreGraphics.h>

NSImage* PDFViewImageFromBitmap(const pdfview::core::Bitmap& bitmap, NSSize displaySize) {
  NSData* bitmapData =
      [NSData dataWithBytes:bitmap.pixels.data() length:bitmap.pixels.size()];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)bitmapData);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGImageRef cgImage = CGImageCreate(bitmap.width,
                                     bitmap.height,
                                     8,
                                     32,
                                     bitmap.stride,
                                     colorSpace,
                                     kCGBitmapByteOrder32Little |
                                         kCGImageAlphaPremultipliedFirst,
                                     provider,
                                     NULL,
                                     false,
                                     kCGRenderingIntentDefault);
  NSImage* image = [[NSImage alloc] initWithCGImage:cgImage size:displaySize];
  CGImageRelease(cgImage);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}
