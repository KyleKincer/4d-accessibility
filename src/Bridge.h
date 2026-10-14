#import <Foundation/Foundation.h>
NSString *AXBOpen(NSInteger windowID, NSInteger processID, void *nativeWindow);
NSString *AXBExchange(NSInteger windowID, NSInteger processID, void *nativeWindow, NSString *sessionID, NSString *json);
NSString *AXBNativeFocus(void *nativeWindow);
void AXBDetach(NSString *sessionID, NSInteger processID = 0);
// Whether the session's form should be described again now (AXBSession claimRefresh…). An
// unknown session answers yes, so that its exchange reports the error.
BOOL AXBRefreshDue(NSString *sessionID);
// The form objects whose layers changed since the session's host last asked, as JSON:
// {"whole": true} when the form must be described whole (its first description, a new page or
// record, the idle backstop, too many changes, or drawing not observed), else
// {"whole": false, "names": [...]}.
NSString *AXBTakeChanges(NSString *sessionID);
// Whether a bridge session is open for this native window, before or after its view attaches.
BOOL AXBWindowHasSession(void *nativeWindow);
void AXBInitialize(void);
void AXBShutdown(void);
