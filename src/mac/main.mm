#import <AppKit/AppKit.h>

#include "mac/app_delegate.h"

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    NSApplication* app = [NSApplication sharedApplication];
    AppDelegate* delegate = [[AppDelegate alloc] initWithArgc:argc argv:argv];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app setDelegate:delegate];
    [app activateIgnoringOtherApps:YES];
    [app run];
  }
  return 0;
}
