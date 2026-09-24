#import <Foundation/Foundation.h>
NSString *AXBOpen(NSInteger windowID, NSInteger processID, void *nativeWindow);
NSString *AXBExchange(NSInteger windowID, NSInteger processID, void *nativeWindow, NSString *sessionID, NSString *json);
NSString *AXBNativeFocus(void *nativeWindow);
void AXBDetach(NSString *sessionID, NSInteger processID = 0);
void AXBShutdown(void);
