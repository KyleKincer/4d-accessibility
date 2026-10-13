#import <Foundation/Foundation.h>
NSString *AXBOpen(NSInteger windowID, NSInteger processID, void *nativeWindow);
NSString *AXBExchange(NSInteger windowID, NSInteger processID, void *nativeWindow, NSString *sessionID, NSString *json);
NSString *AXBNativeFocus(void *nativeWindow);
void AXBDetach(NSString *sessionID, NSInteger processID = 0);
// Whether a bridge session is open for this native window, before or after its view attaches.
BOOL AXBWindowHasSession(void *nativeWindow);
void AXBInitialize(void);
void AXBShutdown(void);
