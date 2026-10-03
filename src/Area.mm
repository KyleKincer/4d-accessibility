#import <Foundation/Foundation.h>
#include "Area.h"
#include <vector>

@interface AXBAreaLifetime : NSObject
@property(nonatomic, strong) NSString *identifier;
@property(nonatomic, strong) NSString *objectName;
@property(nonatomic) BOOL attached;
@end
@implementation AXBAreaLifetime
@end

// Area references are opaque keys. A host callback can close its own window
// and reenter DeinitArea, so no callback holds a raw lifetime pointer.
static NSMutableDictionary<NSNumber *, AXBAreaLifetime *> *areas;
static uintptr_t nextArea;

static void SetText(PA_Variable *variable, NSString *text) {
    std::vector<PA_Unichar> characters(text.length + 1, 0);
    [text getCharacters:characters.data() range:NSMakeRange(0, text.length)];
    PA_Unistring value = PA_CreateUnistring(characters.data());
    // PA_SetStringVariable transfers this allocation, it does not copy it.
    // The argument owns it until PA_ClearVariable after the host call.
    PA_SetStringVariable(variable, &value);
}

static void NotifyHost(AXBAreaLifetime *area, NSString *operation) {
    // A fixed, installed host method keeps application pointers and formulas
    // in their owning host, including interpreted hosts with our component.
    PA_Unichar name[] = {'A', 'X', 'B', '_', 'A', 'r', 'e', 'a', 0};
    PA_long32 method = PA_GetMethodID(name);
    if (!method || PA_GetLastError() != eER_NoErr) return;
    PA_Variable arguments[3];
    for (auto &argument : arguments) argument = PA_CreateVariable(eVK_Undefined);
    SetText(&arguments[0], operation);
    SetText(&arguments[1], area.identifier);
    SetText(&arguments[2], area.objectName);
    PA_Variable result = PA_ExecuteMethodByID(method, arguments, 3);
    PA_ClearVariable(&result);
    for (auto &argument : arguments) PA_ClearVariable(&argument);
}

void AXBArea(PA_PluginParameters parameters) {
    const PA_AreaEvent event = PA_GetAreaEvent(parameters);
    if (event == eAE_IsFocusable) {
        PA_SetAreaFocusable(parameters, false);
        return;
    }
    if (event == eAE_Select) {
        PA_AcceptSelect(parameters, true);
        return;
    }
    if (event == eAE_Deselect) {
        PA_AcceptDeselect(parameters, true);
        return;
    }
    if (event == eAE_DesignUpdate) {
        PA_PluginProperties properties = {};
        PA_GetPluginProperties(parameters, &properties);
        return;
    }
    if (event == eAE_InitArea) {
        PA_PluginProperties properties = {};
        PA_GetPluginProperties(parameters, &properties);
        if (properties.fPrintingMode != 0) {
            PA_SetAreaReference(parameters, nullptr);
            return;
        }
        if (!areas) areas = [NSMutableDictionary new];
        AXBAreaLifetime *area = [AXBAreaLifetime new];
        area.identifier = NSUUID.UUID.UUIDString;
        PA_Unistring *name = PA_GetAreaObjectName(parameters);
        area.objectName = name ? [[NSString alloc] initWithCharacters:PA_GetUnistring(name)
            length:PA_GetUnistringLength(name)] : @"";
        uintptr_t key = ++nextArea;
        areas[@(key)] = area;
        PA_SetAreaReference(parameters, reinterpret_cast<void *>(key));
        // Reserve the lifetime before form load can emit its initial focus.
        // Registration still waits for the first ordinary idle callback.
        NotifyHost(area, @"reserve");
        return;
    }
    uintptr_t key = reinterpret_cast<uintptr_t>(PA_GetAreaReference(parameters));
    AXBAreaLifetime *area = areas[@(key)];
    if (!area) return;
    if (event == eAE_Deinit) {
        // Retire before entering 4D. Queued startup and reentrant callbacks
        // cannot acquire this lifetime again.
        [areas removeObjectForKey:@(key)];
        PA_SetAreaReference(parameters, nullptr);
        NotifyHost(area, @"stop");
    } else if (event == eAE_Idle && !area.attached) {
        area.attached = YES;
        NotifyHost(area, @"attach");
    } else if (event == eAE_MouseDown || event == eAE_KeyDown) {
        PA_DontTakeEvent(parameters);
    }
    // This area draws nothing and never takes keyboard focus. All published
    // controls and actions use the existing bridge implementation.
}

void AXBAreaShutdown() {
    [areas removeAllObjects];
}
