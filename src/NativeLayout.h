#import <Cocoa/Cocoa.h>

// Publish captured geometry only to windows that own an active bridge. Reads
// use immutable cached data without drawing or entering the native event loop.
void AXBLayoutInitialize(void);
void AXBLayoutObserve(NSWindow *window);
void AXBLayoutForget(NSWindow *window);
void AXBLayoutShutdown(void);
NSString *AXBReadNativeLayout(void *nativeWindow, NSString *request);
