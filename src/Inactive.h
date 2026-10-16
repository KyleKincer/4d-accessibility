#import <Cocoa/Cocoa.h>

// 4D acts only as the active application: its editors and the input that drives them need its key
// window. While another application is in front, an action or a value written through
// accessibility is refused at once, rather than accepted and then dropped. Reading is unaffected.
static inline BOOL AXBActionWhileInactive(SEL selector) {
    if (NSApp.isActive) return NO;
    NSString *name = NSStringFromSelector(selector);
    return [name hasPrefix:@"set"] || [name hasPrefix:@"accessibilityPerform"];
}
