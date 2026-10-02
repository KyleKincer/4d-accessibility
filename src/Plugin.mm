#import <Foundation/Foundation.h>
#include "4DPluginAPI.h"
#import "Bridge.h"
#include "Area.h"
#include "Limits.h"
#import "NativeLayout.h"
#include <vector>

static NSString *TextParameter(PA_PluginParameters parameters, short index, NSUInteger limit) {
    PA_Unistring *raw = PA_GetStringParameter(parameters, index);
    if (!raw) return @"";
    PA_long32 length = PA_GetUnistringLength(raw);
    if (length < 0 || static_cast<NSUInteger>(length) > limit) return @"";
    return [[NSString alloc] initWithCharacters:PA_GetUnistring(raw) length:length];
}
static void ReturnText(PA_PluginParameters parameters, NSString *value) {
    std::vector<PA_Unichar> chars(value.length + 1, 0);
    [value getCharacters:chars.data() range:NSMakeRange(0, value.length)];
    PA_ReturnString(parameters, chars.data());
}
@interface AXBFocusRequest : NSObject
@property(nonatomic) void *nativeWindow;
@property(atomic, strong) NSString *result;
@property(nonatomic, copy) NSString *layout;
@end
@implementation AXBFocusRequest
@end
static NSMutableDictionary<NSNumber *, AXBFocusRequest *> *focusRequests;
static NSObject *focusRequestLock;
static uintptr_t nextFocusRequest;
static void ReadNativeFocus(void *parameter) {
    @autoreleasepool {
        AXBFocusRequest *request;
        @synchronized(focusRequestLock) { request = focusRequests[@(reinterpret_cast<uintptr_t>(parameter))]; }
        if (request) request.result = request.layout ? AXBReadNativeLayout(request.nativeWindow, request.layout) : AXBNativeFocus(request.nativeWindow);
    }
}
extern "C" void PluginMain(PA_long32 selector, PA_PluginParameters parameters) {
    @autoreleasepool {
        switch (selector) {
            case kInitPlugin:
            case kServerInitPlugin: AXBInitialize(); break;
            case kDeinitPlugin:
            case kServerDeinitPlugin: AXBAreaShutdown();
                AXBShutdown(); break;
            case 1: {
                PA_long32 windowID = PA_GetLongParameter(parameters, 1);
                NSInteger processID = PA_GetCurrentProcessNumber();
                NSString *sessionID = TextParameter(parameters, 2, 128);
                NSString *json = TextParameter(parameters, 3, AXBLimits::payload);
                sLONG_PTR native = PA_GetWindowPtr(reinterpret_cast<PA_WindowRef>(static_cast<intptr_t>(windowID)));
                if (PA_GetLastError() != eER_NoErr) native = 0;
                ReturnText(parameters, AXBExchange(windowID, processID, reinterpret_cast<void *>(native), sessionID, json));
                break;
            }
            case 2: AXBDetach(TextParameter(parameters, 1, 128), PA_GetCurrentProcessNumber()); break;
            case 3: ReturnText(parameters, [NSString stringWithFormat:@"Accessibility Bridge %s; protocol 1; controls 1; focus 1; grids 1; rowStates 1; gridControls 1; cellFocus 1; gridHeaders 1; input 2; semantics 1; combos 1; checkboxes 1; adjustables 2; sessions 2; scrolling 1; areaLifecycle 1; buttonInput 1; tabs 1; stableIdentifiers 1; macOS", AXB_VERSION]); break;
            case 4:
            case 7: {
                PA_long32 windowID = PA_GetLongParameter(parameters, 1);
                sLONG_PTR native = PA_GetWindowPtr(reinterpret_cast<PA_WindowRef>(static_cast<intptr_t>(windowID)));
                if (PA_GetLastError() != eER_NoErr) native = 0;
                static dispatch_once_t once;
                dispatch_once(&once, ^{ focusRequests = [NSMutableDictionary new]; focusRequestLock = [NSObject new]; });
                AXBFocusRequest *request = [AXBFocusRequest new];
                request.nativeWindow = reinterpret_cast<void *>(native);
                if (selector == 7) {
                    request.layout = TextParameter(parameters, 2, 4096);
                    if (!request.layout) { ReturnText(parameters, @"{\"ok\":false,\"error\":\"invalidLayoutRequest\"}"); break; }
                }
                uintptr_t identifier;
                @synchronized(focusRequestLock) { identifier = ++nextFocusRequest; focusRequests[@(identifier)] = request; }
                // SDK callback context is an opaque lookup key, never a stack
                // address. A delayed callback safely finds no pending request.
                // Hold no native lock while entering 4D's main-process bridge.
                PA_RunInMainProcess(ReadNativeFocus, reinterpret_cast<void *>(identifier));
                bool succeeded = PA_GetLastError() == eER_NoErr;
                @synchronized(focusRequestLock) { [focusRequests removeObjectForKey:@(identifier)]; }
                NSString *failure = selector == 7 ? @"{\"ok\":false,\"error\":\"nativeTabLayoutUnavailable\"}" : @"{\"ok\":false,\"error\":\"noNativeFocus\"}";
                ReturnText(parameters, succeeded && request.result ? request.result : failure);
                break;
            }
            case 5: {
                PA_long32 windowID = PA_GetLongParameter(parameters, 1);
                sLONG_PTR native = PA_GetWindowPtr(reinterpret_cast<PA_WindowRef>(static_cast<intptr_t>(windowID)));
                if (PA_GetLastError() != eER_NoErr) native = 0;
                ReturnText(parameters, AXBOpen(windowID, PA_GetCurrentProcessNumber(), reinterpret_cast<void *>(native)));
                break;
            }
            case 6: AXBArea(parameters); break;
            default: break;
        }
    }
}
