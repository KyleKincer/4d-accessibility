// Integration test client. It uses only AX APIs, never mouse/keyboard injection.
// Its only writable target is the disposable "4D accessibility probe" fixture.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <cstdio>
#include <cstdlib>

static id Read(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = nullptr;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    printf("PASS: %s\n", message); fflush(stdout);
}
static id Find(AXUIElementRef root, NSString *suffix) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:(__bridge id)root];
    for (NSUInteger inspected = 0; pending.count && inspected < 2000; ++inspected) {
        id node = pending.lastObject; [pending removeLastObject];
        NSString *identifier = Read((__bridge AXUIElementRef)node, kAXIdentifierAttribute);
        if ([identifier hasPrefix:@"axb."] && [identifier hasSuffix:suffix]) return node;
        NSArray *children = Read((__bridge AXUIElementRef)node, kAXChildrenAttribute);
        if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
    }
    return nil;
}
static BOOL WaitValue(AXUIElementRef element, NSString *expected) {
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + 3;
    do {
        id value = Read(element, kAXValueAttribute);
        if ([value isKindOfClass:NSString.class] && [value containsString:expected]) return YES;
        [NSThread sleepForTimeInterval:0.02];
    } while (NSProcessInfo.processInfo.systemUptime < end);
    return NO;
}
static id WindowNamed(AXUIElementRef app, NSString *title) {
    id found = nil;
    for (id window in Read(app, kAXWindowsAttribute)) {
        if ([Read((__bridge AXUIElementRef)window, kAXTitleAttribute) isEqual:title]) {
            Check(found == nil, "fixture window title is unambiguous");
            found = window;
        }
    }
    return found;
}
static id WaitWindow(AXUIElementRef app, NSString *title) {
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + 3;
    do {
        id window = WindowNamed(app, title);
        if (window && Find((__bridge AXUIElementRef)window, @".name")) return window;
        [NSThread sleepForTimeInterval:0.02];
    } while (NSProcessInfo.processInfo.systemUptime < end);
    return nil;
}
static BOOL WaitEnabled(AXUIElementRef element) {
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + 3;
    do {
        if ([Read(element, kAXEnabledAttribute) boolValue]) return YES;
        [NSThread sleepForTimeInterval:0.02];
    } while (NSProcessInfo.processInfo.systemUptime < end);
    return NO;
}
static void CloseSecondWindow(AXUIElementRef app, AXUIElementRef window) {
    id close = Read(window, kAXCloseButtonAttribute);
    Check(close != nil, "second fixture window exposes its native close control");
    Check(AXUIElementPerformAction((__bridge AXUIElementRef)close, kAXPressAction) == kAXErrorSuccess,
          "second window close requested through AX");
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + 3;
    while (WindowNamed(app, @"4D accessibility probe 2") && NSProcessInfo.processInfo.systemUptime < end)
        [NSThread sleepForTimeInterval:0.02];
    Check(WindowNamed(app, @"4D accessibility probe 2") == nil, "4D completed second window closure");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 2 && strcmp(argv[1], "--exercise-fixture") == 0, "explicit fixture-test mode required");
        Check(AXIsProcessTrusted(), "test runner has existing accessibility permission");
        NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.4D.4D"];
        Check(apps.count == 1, "exactly one 4D host");
        AXUIElementRef app = AXUIElementCreateApplication([apps[0] processIdentifier]);
        AXUIElementSetMessagingTimeout(app, 2);
        id fixture = nil;
        for (id window in Read(app, kAXWindowsAttribute)) {
            if ([Read((__bridge AXUIElementRef)window, kAXTitleAttribute) isEqual:@"4D accessibility probe"]) {
                Check(fixture == nil, "fixture title is unambiguous"); fixture = window;
            }
        }
        Check(fixture != nil, "disposable fixture window found");
        AXUIElementRef window = (__bridge AXUIElementRef)fixture;
        id field = Find(window, @".name"), button = Find(window, @".submit"), checkbox = Find(window, @".allowed"), status = Find(window, @".status");
        Check(field && button && checkbox && status, "all registered native 4D controls exposed");
        AXUIElementRef f = (__bridge AXUIElementRef)field, b = (__bridge AXUIElementRef)button;
        AXUIElementRef c = (__bridge AXUIElementRef)checkbox, s = (__bridge AXUIElementRef)status;
        id diagnostics = Find(window, @".diagnostics");
        Check(diagnostics && WaitValue((__bridge AXUIElementRef)diagnostics, @"Host timer fired 1 time(s)"),
              "host timer fired once before timer-independent AX actions");
        printf("INFO: %s\n", [Read((__bridge AXUIElementRef)diagnostics, kAXValueAttribute) UTF8String]);
        Boolean writable = false;
        Check(AXUIElementIsAttributeSettable(f, kAXValueAttribute, &writable) == kAXErrorSuccess && writable, "text value writable");
        Check(AXUIElementIsAttributeSettable(b, kAXValueAttribute, &writable) == kAXErrorSuccess && !writable, "button value read-only");
        NSString *name = @"AX café 日本語 🎸";
        Check(AXUIElementSetAttributeValue(f, kAXValueAttribute, (__bridge CFStringRef)name) == kAXErrorSuccess, "AXValue edit submitted");
        Check(WaitValue(f, name) && WaitValue(s, @"Name accepted by 4D"), "Unicode edit accepted by 4D handler");
        Check(AXUIElementSetAttributeValue(f, kAXValueAttribute, CFSTR("")) == kAXErrorSuccess, "invalid edit submitted");
        Check(WaitValue(s, @"1 to 40") && [Read(f, kAXValueAttribute) isEqual:name], "4D rejects invalid edit and keeps accepted value");
        Check([Read(c, kAXValueAttribute) boolValue], "fixture initially allows submission");
        Check(AXUIElementPerformAction(c, kAXPressAction) == kAXErrorSuccess, "checkbox AXPress accepted");
        Check(WaitValue(s, @"Permission changed") && ![Read(c, kAXValueAttribute) boolValue] && ![Read(b, kAXEnabledAttribute) boolValue], "4D checkbox disables submit");
        // AppKit can acknowledge receipt even when the provider returns NO.
        // Check the application effect; a transport status is not completion.
        NSString *disabledStatus = Read(s, kAXValueAttribute);
        AXError disabledResult = AXUIElementPerformAction(b, kAXPressAction);
        printf("INFO: disabled AXPress transport result: %d\n", disabledResult);
        [NSThread sleepForTimeInterval:0.3];
        Check(![Read(b, kAXEnabledAttribute) boolValue] && [Read(s, kAXValueAttribute) isEqual:disabledStatus], "disabled AXPress leaves 4D state unchanged");
        Check(AXUIElementPerformAction(c, kAXPressAction) == kAXErrorSuccess, "checkbox can be re-enabled");
        NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + 3;
        while (![Read(b, kAXEnabledAttribute) boolValue] && NSProcessInfo.processInfo.systemUptime < end) [NSThread sleepForTimeInterval:0.02];
        Check([Read(b, kAXEnabledAttribute) boolValue], "button enabled after 4D receipt");
        Check(AXUIElementPerformAction(b, kAXPressAction) == kAXErrorSuccess, "submit AXPress accepted");
        Check(WaitValue(s, @"4D submissions: 1; tester: AX café 日本語 🎸"), "real 4D action completed exactly once");

        id table = Find(window, @".lines"), row = Find(window, @".lines.line-003");
        id reverse = Find(window, @".reverse"), remove = Find(window, @".remove");
        Check(table && row && reverse && remove, "grid and lifecycle controls exposed");
        AXUIElementRef r = (__bridge AXUIElementRef)row;
        Check(AXUIElementPerformAction(r, kAXPressAction) == kAXErrorSuccess, "duplicate SKU row selected by identity");
        Check(WaitValue(s, @"AreaList selection completed: 1 row(s) [accessibility]") && [Read(r, kAXSelectedAttribute) boolValue], "AreaList readback confirms intended stable row");
        Check(AXUIElementPerformAction((__bridge AXUIElementRef)reverse, kAXPressAction) == kAXErrorSuccess, "grid reordered");
        Check(WaitValue(s, @"Rows reordered"), "4D sort completed");
        Check(AXUIElementPerformAction(r, kAXPressAction) == kAXErrorSuccess, "retained row identity remains usable after sort");
        Check(WaitValue(s, @"AreaList selection completed: 1 row(s) [accessibility]") && [Read(r, kAXSelectedAttribute) boolValue], "selection follows stable key after reorder");
        NSArray *selected = Read((__bridge AXUIElementRef)table, kAXSelectedRowsAttribute);
        Check(selected.count == 1 && CFEqual((__bridge CFTypeRef)selected.firstObject, r), "native table selectedRows matches AreaList");
        Check(AXUIElementPerformAction((__bridge AXUIElementRef)remove, kAXPressAction) == kAXErrorSuccess, "row removal requested");
        Check(WaitValue(s, @"Line 003 removed"), "4D removed row");
        Check(Find(window, @".lines.line-003") == nil, "removed row absent from AX tree");
        NSString *removedStatus = Read(s, kAXValueAttribute);
        AXError removedResult = AXUIElementPerformAction(r, kAXPressAction);
        printf("INFO: removed row AXPress transport result: %d\n", removedResult);
        [NSThread sleepForTimeInterval:0.3];
        Check([Read(s, kAXValueAttribute) isEqual:removedStatus], "retained deleted row cannot change 4D state");

        id modalButton = Find(window, @".modal");
        Check(modalButton && AXUIElementPerformAction((__bridge AXUIElementRef)modalButton, kAXPressAction) == kAXErrorSuccess,
              "modal open requested through AX");
        id modal = nil, closeModal = nil;
        end = NSProcessInfo.processInfo.systemUptime + 3;
        do {
            modal = WindowNamed(app, @"Accessibility modal test");
            if (modal) closeModal = Find((__bridge AXUIElementRef)modal, @".close-modal");
            if (closeModal) break;
            [NSThread sleepForTimeInterval:0.02];
        } while (NSProcessInfo.processInfo.systemUptime < end);
        Check(closeModal != nil, "real 4D modal exposes its registered close action");
        Check(![Read(b, kAXEnabledAttribute) boolValue], "modal blocks the parent's accessible submit action");
        (void)AXUIElementPerformAction(b, kAXPressAction);
        Check(AXUIElementPerformAction((__bridge AXUIElementRef)closeModal, kAXPressAction) == kAXErrorSuccess,
              "modal close requested through AX");
        Check(WaitValue(s, @"Modal closed") && WaitEnabled(b), "4D closed modal and resumed parent actions");
        Check(AXUIElementPerformAction(b, kAXPressAction) == kAXErrorSuccess &&
              WaitValue(s, @"4D submissions: 2; tester: AX café 日本語 🎸"),
              "blocked modal press had no delayed submission");

        id secondButton = Find(window, @".second");
        Check(secondButton && AXUIElementPerformAction((__bridge AXUIElementRef)secondButton, kAXPressAction) == kAXErrorSuccess,
              "independent second window requested through AX");
        id second = WaitWindow(app, @"4D accessibility probe 2");
        Check(second != nil, "independent second window registered");
        id secondField = Find((__bridge AXUIElementRef)second, @".name");
        id secondSubmit = Find((__bridge AXUIElementRef)second, @".submit");
        NSString *oldIdentifier = Read((__bridge AXUIElementRef)secondField, kAXIdentifierAttribute);
        Check(oldIdentifier != nil && ![oldIdentifier isEqual:Read(f, kAXIdentifierAttribute)],
              "separate windows have separate session identities");
        Check(AXUIElementSetAttributeValue((__bridge AXUIElementRef)secondField, kAXValueAttribute, CFSTR("Second tester")) == kAXErrorSuccess &&
              WaitValue((__bridge AXUIElementRef)secondField, @"Second tester"), "second window edit completed");
        Check([Read(f, kAXValueAttribute) isEqual:name], "second window edit leaves parent data unchanged");
        CloseSecondWindow(app, (__bridge AXUIElementRef)second);
        Check(WaitEnabled(b), "parent resumed after independent window closure");
        Check(![Read((__bridge AXUIElementRef)secondSubmit, kAXEnabledAttribute) boolValue], "retained closed-window button is disabled or invalid");
        (void)AXUIElementPerformAction((__bridge AXUIElementRef)secondSubmit, kAXPressAction);
        (void)AXUIElementSetAttributeValue((__bridge AXUIElementRef)secondField, kAXValueAttribute, CFSTR("Stale edit"));
        Check(AXUIElementPerformAction((__bridge AXUIElementRef)secondButton, kAXPressAction) == kAXErrorSuccess,
              "second window reopened through ordinary 4D handler");
        id reopened = WaitWindow(app, @"4D accessibility probe 2");
        Check(reopened != nil, "reopened window registered");
        id reopenedField = Find((__bridge AXUIElementRef)reopened, @".name");
        Check(![oldIdentifier isEqual:Read((__bridge AXUIElementRef)reopenedField, kAXIdentifierAttribute)] &&
              [Read((__bridge AXUIElementRef)reopenedField, kAXValueAttribute) isEqual:@"QA Tester"],
              "reopened window has a fresh identity and rejects old-reference edits");
        CloseSecondWindow(app, (__bridge AXUIElementRef)reopened);
        Check(WaitEnabled(b) && [Read(f, kAXValueAttribute) isEqual:name], "parent state survives close/reopen lifecycle");
        CFRelease(app);
        puts("PASS: external AX integration, without coordinate input");
    }
}
