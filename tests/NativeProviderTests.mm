// Tests this project's own AppKit windows. No external application is controlled.
// Requires an unlocked interactive desktop. This is not the external AX client.
#import <Cocoa/Cocoa.h>
#import "Bridge.h"
#import "BridgePrivate.h"
#include <cstdio>
#include <cstdlib>

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    printf("PASS: %s\n", message);
}
static void Pump(void) {
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES]))
        [NSApp sendEvent:event];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    [NSApp updateWindows];
}
static NSDictionary *Exchange(NSWindow *window, NSInteger windowID, NSInteger process, NSString *session, NSDictionary *snapshot, NSDictionary *receipt = nil, NSDictionary *input = nil, NSDictionary *controlInput = nil, NSArray *pages = nil) {
    NSMutableDictionary *envelope = [@{@"snapshot": snapshot} mutableCopy];
    if (receipt) envelope[@"receipt"] = receipt;
    if (input) envelope[@"editorInput"] = input;
    if (controlInput) envelope[@"controlInput"] = controlInput;
    if (pages) envelope[@"gridPages"] = pages;
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    NSString *reply = AXBExchange(windowID, process, (__bridge void *)window, session, [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]);
    return [NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}
static NSDictionary *OpenResult(NSWindow *window, NSInteger windowID, NSInteger process) {
    NSString *reply = AXBOpen(windowID, process, (__bridge void *)window);
    return [NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}
static NSString *Open(NSWindow *window, NSInteger windowID, NSInteger process = 1) {
    NSDictionary *result = OpenResult(window, windowID, process);
    if (![result[@"ok"] boolValue]) { fprintf(stderr, "Native session allocation failed: %s\n", result.description.UTF8String); exit(1); }
    return result[@"session"];
}
static NSWindow *Window(NSString *title) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(150, 200, 400, 200) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.title = title;
    [window orderFront:nil];
    return window;
}
static NSAccessibilityElement *Provider(NSWindow *window) {
    for (NSView *view in window.contentView.subviews) {
        id child = view.accessibilityChildren.firstObject;
        if ([[child accessibilityIdentifier] hasPrefix:@"axb.window."]) return child;
    }
    return nil;
}
static NSDictionary *Focus(void *window) {
    NSString *json = AXBNativeFocus(window);
    return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}
static void RefreshDelayTest(void) {
    NSWindow *window = Window(@"AXB delayed accessibility refresh");
    NSString *session = Open(window, 9001);
    NSMutableDictionary *button = [@{@"id": @"submit", @"role": @"button", @"label": @"Submit", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @120, @30]} mutableCopy];
    NSMutableDictionary *status = [button mutableCopy]; status[@"id"] = @"status"; status[@"role"] = @"text";
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Refresh test", @"enabled": @YES, @"nodes": @[button, status]} mutableCopy];
    Exchange(window, 9001, 1, session, snapshot); Pump();
    id element = Provider(window).accessibilityChildren.firstObject;
    status[@"value"] = @"Background update"; snapshot[@"revision"] = @2;
    Exchange(window, 9001, 1, session, snapshot);
    // Deliberately do not pump the queued AppKit refresh before the AX request.
    Check([element accessibilityPerformPress], "unchanged control accepts an action before an unrelated native refresh");
    NSDictionary *action = Exchange(window, 9001, 1, session, snapshot)[@"action"];
    Check([action[@"revision"] isEqual:@2], "delayed native element dispatches against the checked current snapshot");
    Exchange(window, 9001, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"}); Pump();
    button[@"label"] = @"Delete"; snapshot[@"revision"] = @3;
    Exchange(window, 9001, 1, session, snapshot);
    Check(![element accessibilityPerformPress], "changed control rejects an action before its native refresh");
    [window close]; Pump();
}
static void GridRefreshDelayTest(void) {
    NSWindow *window = Window(@"AXB delayed grid refresh");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9005);
    NSMutableDictionary *grid = [@{@"generation": @"first", @"order": @1,
        @"rows": @[@"first", @"last"], @"columns": @[@{@"id": @"name", @"label": @"Name", @"enabled": @YES, @"editable": @NO}],
        @"visible": @[], @"selected": @[@"last"], @"disabled": @[], @"unselectable": @[], @"uneditable": @[],
        @"actions": @{@"select": @YES, @"reveal": @YES}} mutableCopy];
    NSMutableDictionary *data = [@{@"id": @"items", @"role": @"table", @"label": @"Items", @"value": @"",
        @"visible": @YES, @"enabled": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Grid refresh", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Check([Exchange(window, 9005, 1, session, snapshot)[@"ok"] boolValue], "delayed grid snapshot accepted"); Pump();
    AXBGridNode *table = Provider(window).accessibilityChildren.firstObject;
    id first = table.accessibilityRows[0], last = table.accessibilityRows[1];
    id cell = [table accessibilityCellForColumn:0 row:0];
    grid[@"unselectable"] = @[@"last"]; snapshot[@"revision"] = @2;
    Exchange(window, 9005, 1, session, snapshot);
    // No run-loop pump: grid getters already see the new model, while the
    // AppKit tree has not published the matching form revision yet.
    [first setAccessibilitySelected:YES];
    NSDictionary *action = Exchange(window, 9005, 1, session, snapshot)[@"action"];
    Check([action[@"value"] isEqual:@[@"last", @"first"]] && [action[@"revision"] isEqual:@2], "row setter preserves restricted selection before the queued native refresh");
    Exchange(window, 9005, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"}); Pump();
    grid[@"selected"] = @[@"first"]; snapshot[@"revision"] = @3;
    Exchange(window, 9005, 1, session, snapshot);
    Check([cell accessibilityPerformPress], "cell activation accepts the current grid before its queued native refresh");
    action = Exchange(window, 9005, 1, session, snapshot)[@"action"];
    Check([action[@"value"] isEqual:@[@"first"]] && [action[@"revision"] isEqual:@3], "cell activation uses the synchronized revision");
    Exchange(window, 9005, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"}); Pump();
    grid[@"unselectable"] = @[]; snapshot[@"revision"] = @4;
    Exchange(window, 9005, 1, session, snapshot);
    [table setAccessibilitySelectedRows:@[last]];
    action = Exchange(window, 9005, 1, session, snapshot)[@"action"];
    Check([action[@"value"] isEqual:@[@"last"]] && [action[@"revision"] isEqual:@4], "table selection validates live row objects after synchronizing");
    Exchange(window, 9005, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"}); Pump();
    grid[@"generation"] = @"replacement"; snapshot[@"revision"] = @5;
    Exchange(window, 9005, 1, session, snapshot);
    [first setAccessibilitySelected:YES]; [table setAccessibilitySelectedRows:@[last]];
    Check(![first accessibilityPerformPress] && ![cell accessibilityPerformPress] && !Exchange(window, 9005, 1, session, snapshot)[@"action"], "synchronizing a replacement cannot revive retained rows or cells with reused keys");
    id replacement = table.accessibilityRows[0];
    grid[@"unselectable"] = @[@"first"]; grid[@"selected"] = @[]; snapshot[@"revision"] = @6;
    Exchange(window, 9005, 1, session, snapshot);
    Check(![replacement accessibilityPerformPress], "a restriction arriving before native refresh still prevents selection");
    [window close]; Pump();
}
@interface AXBStepperTestView : NSView
@property(nonatomic) NSUInteger presses;
@property(nonatomic) NSUInteger releases;
@property(nonatomic) NSPoint lastPoint;
@end
@implementation AXBStepperTestView
- (BOOL)isFlipped { return YES; }
- (void)mouseDown:(NSEvent *)event { self.presses++; self.lastPoint = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.menu) [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidBeginTrackingNotification object:self.menu]; }
- (void)mouseUp:(NSEvent *)event { (void)event; self.releases++; }
@end
static void GridControlsTest(void) {
    NSWindow *window = Window(@"AXB typed grid controls");
    AXBStepperTestView *canvas = [[AXBStepperTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9012);
    NSDictionary *grid = @{@"generation": @"controls", @"order": @1, @"rows": @[@"one"],
        @"columns": @[@{@"id": @"check", @"label": @"Approved", @"enabled": @YES, @"editable": @YES}],
        @"visible": @[@"one"], @"selected": @[], @"disabled": @[], @"uneditable": @[], @"unselectable": @[],
        @"frames": @{@"one": @{@"check": @[@10, @30, @200, @28]}},
        @"actions": @{@"select": @YES, @"reveal": @YES, @"edit": @YES}};
    NSDictionary *snapshot = @{@"version": @1, @"revision": @1, @"label": @"Typed controls", @"enabled": @YES,
        @"nodes": @[@{@"id": @"items", @"role": @"table", @"label": @"Items", @"value": @"", @"visible": @YES,
            @"enabled": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid}]};
    NSMutableDictionary *value = [@{@"column": @"check", @"value": @"2", @"role": @"checkbox", @"checked": @2,
        @"label": @"Approved", @"enabled": @YES, @"editable": @YES} mutableCopy];
    NSDictionary *page = @{@"node": @"items", @"generation": @"controls", @"order": @1, @"row": @0, @"column": @0,
        @"rows": @[@{@"id": @"one", @"cells": @[value]}]};
    Check([Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page])[@"ok"] boolValue], "typed grid snapshot and values accepted"); Pump();
    AXBGridNode *table = Provider(window).accessibilityChildren.firstObject;
    id cell = [table accessibilityCellForColumn:0 row:0];
    id checkbox = [cell accessibilityChildren][0];
    Check([[checkbox accessibilityRole] isEqual:NSAccessibilityCheckBoxRole] && [[checkbox accessibilityValue] isEqual:@2], "grid checkbox exposes its native role and mixed value");
    Check(!AXBAttributeIsSettable(checkbox, NSAccessibilityValueAttribute) && ![checkbox isKindOfClass:AXBTextNode.class], "grid checkbox cannot expose string assignment or text-range APIs");
    Check([checkbox accessibilityPerformPress], "grid checkbox dispatches an activation");
    NSDictionary *action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"gridPress"] && [action[@"value"][@"expectedCell"][@"checked"] isEqual:@2], "native checkbox activation preserves its observed value");
    NSDictionary *input = @{@"action": action[@"id"], @"point": @[@21, @44]};
    Exchange(window, 9012, 1, session, snapshot, nil, nil, input); Pump(); Pump();
    if (canvas.presses != 1 || canvas.releases != 1 || canvas.lastPoint.x != 21 || canvas.lastPoint.y != 44)
        fprintf(stderr, "Grid input diagnostic: active=%d key=%d presses=%lu releases=%lu point=%.1f,%.1f\n", NSApp.isActive, window.isKeyWindow, (unsigned long)canvas.presses, (unsigned long)canvas.releases, canvas.lastPoint.x, canvas.lastPoint.y);
    Check(canvas.presses == 1 && canvas.releases == 1 && canvas.lastPoint.x == 21 && canvas.lastPoint.y == 44, "grid control receives exactly one native mouse pair at its checked point");
    Check([Exchange(window, 9012, 1, session, snapshot, nil, nil, input)[@"controlInputResult"][@"accepted"] boolValue], "grid mouse delivery has an exact acknowledgement"); Pump();
    Check(canvas.presses == 1, "grid input replay cannot repeat the native click");
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    value[@"enabled"] = @NO; value[@"editable"] = @NO;
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    Check(![checkbox isAccessibilityEnabled] && ![checkbox accessibilityPerformPress] && [[checkbox accessibilityValue] isEqual:@2], "disabled cell retains readable mixed state without an activation");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (@available(macOS 26.0, *)) {
        Check([[checkbox accessibilityActionNames] containsObject:NSAccessibilityScrollToVisibleAction], "a disabled grid widget can still be revealed for reading");
        [checkbox accessibilityPerformAction:NSAccessibilityScrollToVisibleAction];
        NSDictionary *reveal = Exchange(window, 9012, 1, session, snapshot)[@"action"];
        Check([reveal[@"operation"] isEqual:@"gridReveal"] && [reveal[@"value"][@"row"] isEqual:@"one"], "widget reveal targets its cell without activation or editing");
        Exchange(window, 9012, 1, session, snapshot, @{@"id": reveal[@"id"], @"status": @"completed", @"message": @"revealed"}); Pump();
    }
#pragma clang diagnostic pop
    value[@"enabled"] = @YES; value[@"editable"] = @YES; value[@"role"] = @"popup"; value[@"value"] = @"Allowed"; [value removeObjectForKey:@"checked"];
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    id popup = [cell accessibilityChildren][0];
    Check(![checkbox isAccessibilityElement] && ![checkbox accessibilityPerformPress] && popup != checkbox, "a changed cell role retires its retained control child");
    Check([[popup accessibilityRole] isEqual:NSAccessibilityPopUpButtonRole] && [[popup accessibilityValue] isEqual:@"Allowed"] && [popup accessibilityPerformShowMenu], "grid popup exposes its displayed label and ShowMenu action");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    NSMenu *menu = [NSMenu new];
    menu.accessibilityParent = window; canvas.menu = menu;
    input = @{@"action": action[@"id"], @"point": @[@50, @44]};
    Exchange(window, 9012, 1, session, snapshot, nil, nil, input); Pump();
    Check(menu.accessibilityParent == popup && [popup accessibilityChildren][0] == menu, "native click adopts its menu beneath the exact popup without prior keyboard focus");
    Check([Exchange(window, 9012, 1, session, snapshot)[@"controlInputResult"][@"menuOpened"] boolValue], "popup completion proves that its native menu actually opened");
    [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidEndTrackingNotification object:menu];
    Check(menu.accessibilityParent == window && [[popup accessibilityChildren] count] == 0, "menu dismissal restores native ownership and removes the popup child");
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"requested"}); Pump();
    Check([popup accessibilityPerformShowMenu], "popup can reopen after dismissal");
    [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidBeginTrackingNotification object:menu];
    Check(menu.accessibilityParent == window, "an unrelated menu cannot be adopted before the popup action is delivered");
    [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidEndTrackingNotification object:menu];
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"cancelled"}); Pump();
    Check([popup accessibilityPerformShowMenu], "popup can request a subsequent native menu");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    NSButtonCell *nativeOwner = [NSButtonCell new]; menu.accessibilityParent = nativeOwner;
    input = @{@"action": action[@"id"], @"point": @[@50, @44]};
    Exchange(window, 9012, 1, session, snapshot, nil, nil, input); Pump();
    Check(menu.accessibilityParent == nativeOwner, "existing native popup ownership is preserved");
    [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidEndTrackingNotification object:menu];
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"cancelled"}); Pump();
    Check([popup accessibilityPerformShowMenu], "popup accepts a request before a later role replacement");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    menu.accessibilityParent = window; canvas.menu = menu;
    input = @{@"action": action[@"id"], @"point": @[@50, @44]};
    Exchange(window, 9012, 1, session, snapshot, nil, nil, input); Pump();
    Check(menu.accessibilityParent == popup, "second delivered popup request restores its menu relationship");
    value[@"role"] = @"text"; value[@"value"] = @"Editable text";
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    id text = [cell accessibilityChildren][0];
    Check(menu.accessibilityParent == window, "retiring a popup during menu tracking restores native ownership");
    [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidEndTrackingNotification object:menu];
    Check([text isKindOfClass:AXBTextNode.class] && ![popup isAccessibilityElement] && ![popup accessibilityPerformShowMenu], "native text behavior resumes only through a new child when the cell changes type");
    [window close]; Pump();
}
static void AdjustableTest(void) {
    NSWindow *window = Window(@"AXB guarded stepper delivery");
    AXBStepperTestView *canvas = [[AXBStepperTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9004);
    NSMutableDictionary *data = [@{@"id": @"stepper", @"role": @"stepper", @"label": @"Quantity", @"value": @4,
        @"min": @0, @"max": @10, @"step": @2, @"adjustable": @YES, @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @14, @22]} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Adjustable test", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Check([Exchange(window, 9004, 1, session, snapshot)[@"ok"] boolValue], "native stepper snapshot accepted"); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    Check([node.accessibilityRole isEqual:NSAccessibilityIncrementorRole] && [node.accessibilityValue isEqual:@4] && [node.accessibilityMaxValue isEqual:@10], "native stepper exposes role, numeric value and actual bounds");
    Check([node isAccessibilitySelectorAllowed:@selector(accessibilityPerformIncrement)] && !AXBAttributeIsSettable(node, NSAccessibilityValueAttribute), "stepper advertises normal increment without a data-assignment setter");
    Check([node accessibilityPerformIncrement], "native stepper accepts an increment request");
    NSDictionary *action = Exchange(window, 9004, 1, session, snapshot)[@"action"];
    NSDictionary *input = @{@"action": action[@"id"]};
    Exchange(window, 9004, 1, session, snapshot, nil, nil, input); Pump(); Pump();
    Check(canvas.presses == 1 && canvas.releases == 1 && canvas.lastPoint.x == 26 && canvas.lastPoint.y == 27, "stepper delivers one complete mouse pair inside its upper arrow");
    Check([Exchange(window, 9004, 1, session, snapshot, nil, nil, input)[@"controlInputResult"][@"accepted"] boolValue], "native pointer completion acknowledges the exact request"); Pump();
    Check(canvas.presses == 1, "replaying native input cannot repeat a stepper activation");
    Exchange(window, 9004, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check([node accessibilityPerformDecrement], "native stepper accepts an independent decrement");
    action = Exchange(window, 9004, 1, session, snapshot)[@"action"]; input = @{@"action": action[@"id"]};
    Exchange(window, 9004, 1, session, snapshot, nil, nil, input);
    data[@"value"] = @6; snapshot[@"revision"] = @2;
    Exchange(window, 9004, 1, session, snapshot); Pump();
    Check(canvas.presses == 1 && ![Exchange(window, 9004, 1, session, snapshot)[@"controlInputResult"][@"accepted"] boolValue], "changed stepper state before native dispatch prevents any mouse input");
    Exchange(window, 9004, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"changed"}); Pump();
    NSButton *covering = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 30, 22)];
    covering.title = @"Cover"; [canvas addSubview:covering];
    Check([node accessibilityPerformIncrement], "stepper request can be queued before checking native overlap");
    action = Exchange(window, 9004, 1, session, snapshot)[@"action"]; input = @{@"action": action[@"id"]};
    Exchange(window, 9004, 1, session, snapshot, nil, nil, input); Pump();
    Check(canvas.presses == 1 && ![Exchange(window, 9004, 1, session, snapshot)[@"controlInputResult"][@"accepted"] boolValue], "a native control covering the stepper prevents mouse delivery");
    Exchange(window, 9004, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"covered"});
    [covering removeFromSuperview]; Pump();
    data[@"role"] = @"slider"; snapshot[@"revision"] = @3;
    Exchange(window, 9004, 1, session, snapshot); Pump();
    AXBNode *slider = Provider(window).accessibilityChildren.firstObject;
    Check([slider.accessibilityRole isEqual:NSAccessibilitySliderRole] && [slider.accessibilityMinValue isEqual:@0] && ![node isAccessibilityElement], "slider has native range semantics and retires the prior role");
    Check([slider accessibilityPerformIncrement] && slider.owner.actionFeedback != nil, "slider retains feedback until its host confirms the adjustment");
    action = Exchange(window, 9004, 1, session, snapshot)[@"action"];
    data[@"value"] = @8; data[@"focused"] = @YES; snapshot[@"revision"] = @4;
    Exchange(window, 9004, 1, session, snapshot); Pump();
    Check(slider.owner.actionFeedback != nil, "an intermediate slider value cannot announce completion");
    Exchange(window, 9004, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(slider.owner.actionFeedback == nil, "focused slider consumes confirmed feedback exactly once");
    data[@"adjustable"] = @NO; snapshot[@"revision"] = @5;
    Exchange(window, 9004, 1, session, snapshot); Pump();
    Check(![slider accessibilityPerformIncrement] && ![slider isAccessibilitySelectorAllowed:@selector(accessibilityPerformDecrement)], "read-only slider rejects and hides adjustment actions");
    [window close]; Pump();
}
static void ProgressAdjustmentTest(void) {
    NSWindow *window = Window(@"AXB controller progress");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9005);
    NSMutableDictionary *data = [@{@"id": @"progress", @"role": @"slider", @"label": @"Temperature", @"value": @5,
        @"min": @0, @"max": @10, @"step": @1, @"adjustment": @"callback", @"vertical": @NO,
        @"adjustable": @YES, @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @100, @20]} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Progress test", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Exchange(window, 9005, 1, session, snapshot); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    Check(node.accessibilityOrientation == NSAccessibilityOrientationHorizontal, "interactive progress exposes horizontal orientation");
    Check([node accessibilityPerformIncrement], "controller progress queues increment");
    NSDictionary *action = Exchange(window, 9005, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"increment"], "controller receives the requested operation");
    Exchange(window, 9005, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    data[@"vertical"] = @YES; snapshot[@"revision"] = @2;
    Exchange(window, 9005, 1, session, snapshot); Pump();
    Check(node.accessibilityOrientation == NSAccessibilityOrientationVertical, "interactive progress exposes vertical orientation");
    [window close]; Pump();
}
static void CheckboxFeedbackTest(void) {
    NSWindow *window = Window(@"AXB asynchronous checkbox feedback");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9003);
    NSMutableDictionary *data = [@{@"id": @"mixed", @"role": @"checkbox", @"label": @"Selection", @"value": @2,
        @"focusable": @NO, @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @200, @24]} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Checkbox feedback", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Exchange(window, 9003, 1, session, snapshot); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    Check([node.accessibilityValue isEqual:@2], "native checkbox exposes mixed as AXValue 2");
    Check([node accessibilityPerformPress] && node.owner.actionFeedback != nil, "unfocusable checkbox retains feedback for its queued action");
    NSDictionary *action = Exchange(window, 9003, 1, session, snapshot)[@"action"];
    Check([node.owner.actionFeedback[@"id"] isEqual:action[@"id"]], "checkbox feedback identifies the exact delivered action");
    data[@"value"] = @NO; snapshot[@"revision"] = @2;
    Exchange(window, 9003, 1, session, snapshot); Pump();
    Check(node.owner.actionFeedback != nil, "value publication alone cannot announce a successful completion");
    NSDictionary *receipt = @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"};
    Exchange(window, 9003, 1, session, snapshot, receipt); Pump();
    Check(node.owner.actionFeedback == nil, "confirmed checkbox feedback is consumed once");
    Exchange(window, 9003, 1, session, snapshot, receipt); Pump();
    Check(node.owner.actionFeedback == nil, "replaying a receipt cannot recreate checkbox speech");
    Check([node accessibilityPerformPress], "checkbox accepts another independent activation");
    action = Exchange(window, 9003, 1, session, snapshot)[@"action"];
    Exchange(window, 9003, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"not changed"}); Pump();
    Check(node.owner.actionFeedback == nil, "a rejected action discards success feedback");
    data[@"focusable"] = @YES; snapshot[@"revision"] = @3;
    Exchange(window, 9003, 1, session, snapshot); Pump();
    Check([node accessibilityPerformPress] && node.owner.actionFeedback == nil, "focusable checkbox keeps standard focus and value notifications");
    [window close]; Pump();
}
static void ComboPopupTest(void) {
    NSWindow *window = Window(@"AXB native combo ownership");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9002);
    NSMutableDictionary *data = [@{@"id": @"choice", @"role": @"textfield", @"combo": @YES, @"editable": @YES, @"focusable": @YES, @"focused": @YES, @"label": @"Choice", @"value": @"First", @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @200, @28]} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Combo ownership", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Exchange(window, 9002, 1, session, snapshot); Pump();
    id combo = Provider(window).accessibilityChildren.firstObject;
    NSRect field = [combo accessibilityFrame];
    NSWindow *popup = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(field) + 400, NSMinY(field) - 80, NSWidth(field), 80) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    popup.releasedWhenClosed = NO;
    popup.level = NSFloatingWindowLevel;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:popup.contentView.bounds];
    NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"choice"]];
    scroll.documentView = table; popup.contentView = scroll;
    id nativeParent = table.accessibilityParent;
    NSArray *windowChildren = popup.accessibilityChildren;
    [popup orderFront:nil]; Pump();
    Check(![combo isAccessibilityExpanded], "unrelated floating table cannot expand a combo");
    [popup setFrameOrigin:NSMakePoint(NSMinX(field), NSMinY(field) - 80)]; Pump();
    Check([combo isAccessibilityExpanded] && [[combo accessibilityLinkedUIElements] isEqual:@[table]], "combo expansion links the uniquely anchored native choice table");
    Check(table.accessibilityParent == nativeParent && scroll.accessibilityParent == combo && !popup.isAccessibilityElement && popup.accessibilityChildren.count == 0,
        "combo adopts the native popup without replacing its table provider");
    [popup setFrameOrigin:NSMakePoint(NSMinX(field), NSMaxY(field))]; Pump();
    Check([combo isAccessibilityExpanded], "combo can expose a popup placed above the field");
    data[@"focused"] = @NO; snapshot[@"revision"] = @2;
    Exchange(window, 9002, 1, session, snapshot); Pump();
    Check(![combo isAccessibilityExpanded], "losing combo focus retires the native popup relationship");
    Check(scroll.accessibilityParent != combo && popup.isAccessibilityElement && [popup.accessibilityChildren isEqual:windowChildren], "popup adoption restores native parentage and window visibility");
    Check(![combo accessibilityPerformCancel] && ![combo accessibilityPerformConfirm], "closed combo cannot cancel or submit its containing form");
    [popup close]; [window close]; Pump();
}
static void LogicalFrameTest(void) {
    NSWindow *window = Window(@"AXB offscreen ordinary control");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9006);
    NSMutableDictionary *data = [@{@"id": @"offscreen", @"role": @"text", @"label": @"Last label", @"value": @"Last label",
        @"enabled": @YES, @"visible": @YES, @"revealable": @YES, @"frame": @[@10, @300, @120, @30], @"clip": @[@0, @0, @200, @100]} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Scrollable form", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Check([Exchange(window, 9006, 1, session, snapshot)[@"ok"] boolValue], "offscreen ordinary snapshot accepted"); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    Check(node.isAccessibilityElement && NSWidth(node.accessibilityFrame) == 120 && NSHeight(node.accessibilityFrame) == 30, "offscreen label retains logical size and navigation membership");
    Check(NSIsEmptyRect(node.hitFrame), "fully clipped label has no screen-position hit region");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (@available(macOS 26.0, *)) {
        Check([[node accessibilityActionNames] isEqual:@[NSAccessibilityScrollToVisibleAction]], "static label enumerates its standard reveal action without editor actions");
        [node accessibilityPerformAction:NSAccessibilityScrollToVisibleAction];
        NSDictionary *action = Exchange(window, 9006, 1, session, snapshot)[@"action"];
        Check([action[@"operation"] isEqual:@"reveal"], "standard native reveal delegates to its owning form");
        Exchange(window, 9006, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"revealed"}); Pump();
    }
#pragma clang diagnostic pop
    data[@"frame"] = @[@10, @80, @120, @30]; snapshot[@"revision"] = @2;
    Exchange(window, 9006, 1, session, snapshot); Pump();
    Check(NSHeight(node.accessibilityFrame) == 30 && NSHeight(node.hitFrame) == 20, "partly clipped control has separate logical and visible rectangles");
    data[@"enabled"] = @NO; snapshot[@"revision"] = @3;
    Exchange(window, 9006, 1, session, snapshot); Pump();
    Check(!node.isAccessibilityEnabled && [node queue:@"reveal" value:nil], "disabled control can be revealed without enabling input");
    NSDictionary *reveal = Exchange(window, 9006, 1, session, snapshot)[@"action"];
    Exchange(window, 9006, 1, session, snapshot, @{@"id": reveal[@"id"], @"status": @"completed", @"message": @"revealed"}); Pump();
    data[@"visible"] = @NO; snapshot[@"revision"] = @4;
    Exchange(window, 9006, 1, session, snapshot); Pump();
    Check(!node.isAccessibilityElement && ![node queue:@"reveal" value:nil], "hidden controls cannot be revealed through a retained reference");
    [window close]; Pump();
}
static void NavigationOrderTest(void) {
    NSWindow *window = Window(@"AXB stable form reading order");
    NSString *session = Open(window, 9007);
    NSMutableDictionary *child = [@{@"id": @"child", @"role": @"text", @"label": @"Child", @"value": @"Child",
        @"enabled": @YES, @"visible": @YES, @"revealable": @YES, @"frame": @[@10, @600, @120, @30], @"navigation": @[@20, @20, @600, @10]} mutableCopy];
    NSDictionary *button = @{@"id": @"button", @"role": @"button", @"label": @"After child", @"value": @"",
        @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @280, @120, @30], @"navigation": @[@280, @20]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Form", @"enabled": @YES, @"nodes": @[button, child]} mutableCopy];
    Exchange(window, 9007, 1, session, snapshot); Pump();
    id provider = Provider(window);
    NSArray *before = [provider accessibilityChildrenInNavigationOrder];
    Check(before.count == 2 && [[before.firstObject accessibilityLabel] isEqual:@"Child"], "linear reading order keeps an offscreen child before its following form control");
    child[@"frame"] = @[@10, @20, @120, @30]; snapshot[@"revision"] = @2;
    Exchange(window, 9007, 1, session, snapshot); Pump();
    Check([[provider accessibilityChildrenInNavigationOrder] isEqual:before], "revealing a child does not reorder linear navigation");
    Check([[NSSet setWithArray:[provider accessibilityChildrenInNavigationOrder]] isEqual:[NSSet setWithArray:[provider accessibilityChildren]]], "navigation order contains exactly the accessible children");
    [window close]; Pump();
}
static void SessionLifetimeTest(void) {
    for (NSUInteger i = 0; i < 100; i++) {
        @autoreleasepool {
            NSWindow *transient = Window(@"AXB closes during initialization");
            Open(transient, 9099);
            [transient close];
            Pump();
        }
    }
    Check(YES, "100 windows closing before the first main-thread attachment release their sessions");
    NSWindow *window = Window(@"AXB session lifetime");
    NSDictionary *snapshot = @{@"version": @1, @"revision": @1, @"label": @"Session lifetime", @"enabled": @YES, @"nodes": @[]};
    NSString *oldest = nil;
    for (NSUInteger i = 0; i < 9000; i++) {
        @autoreleasepool {
            NSString *identifier = Open(window, 9100);
            if (!oldest) oldest = identifier;
            NSDictionary *reply = Exchange(window, 9100, 1, identifier, snapshot);
            if (![reply[@"ok"] boolValue]) { fprintf(stderr, "FAIL: form opening %lu: %s\n", i+1, reply.description.UTF8String); exit(1); }
            AXBDetach(identifier, 1);
        }
        if (i % 128 == 0) Pump();
    }
    Pump();
    Check(YES, "9000 form lifetimes work without restarting or retaining closed identities");
    Check(![Exchange(window, 9100, 1, oldest, snapshot)[@"ok"] boolValue], "the oldest closed token still rejects replay after 9000 lifetimes");
    Check(![Exchange(window, 9100, 1, NSUUID.UUID.UUIDString, snapshot)[@"ok"] boolValue], "a caller-generated UUID cannot allocate a session through exchange");
    NSString *current = Open(window, 9100); Pump();
    Check(Provider(window).accessibilityChildren.count == 0, "allocation alone exposes no empty accessibility group");
    Check(![OpenResult(window, 9100, 2)[@"ok"] boolValue], "another process cannot allocate a second session for the same window");
    AXBDetach(current, 2);
    Check([Exchange(window, 9100, 1, current, snapshot)[@"ok"] boolValue], "another process cannot detach the current allocation");
    AXBDetach(oldest, 1);
    Check([Exchange(window, 9100, 1, current, snapshot)[@"ok"] boolValue], "a delayed old detach cannot remove the new window session");
    AXBDetach(current, 1); Pump();
    NSString *unpublished = Open(window, 9100); Pump();
    [window close]; Pump();
    Check(![Exchange(window, 9100, 1, unpublished, snapshot)[@"ok"] boolValue], "window closure retires an allocation that never published a snapshot");
}
static void GridHeaderTest(void) {
    NSWindow *window = Window(@"AXB native grid headers");
    AXBStepperTestView *canvas = [[AXBStepperTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9021);
    NSMutableDictionary *headerData = [@{@"visible": @YES, @"enabled": @YES, @"press": @YES, @"sortable": @YES, @"sort": @"none"} mutableCopy];
    NSDictionary *column = @{@"id": @"amount", @"label": @"Amount", @"enabled": @YES, @"editable": @NO, @"header": headerData};
    NSMutableDictionary *grid = [@{@"generation": @"header-test", @"order": @1, @"rows": @[], @"columns": @[column],
        @"selected": @[], @"visible": @[], @"frames": @{}, @"headers": @{@"amount": @[@10, @20, @200, @22]},
        @"headerHeight": @22, @"layout": @{@"rows": @[], @"columns": @[@[@10, @200]]},
        @"actions": @{@"select": @NO, @"edit": @NO, @"reveal": @YES}} mutableCopy];
    NSDictionary *node = @{@"id": @"items", @"role": @"table", @"label": @"Items", @"value": @"", @"enabled": @YES,
        @"visible": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Headers", @"enabled": @YES, @"nodes": @[node]} mutableCopy];
    Check([Exchange(window, 9021, 1, session, snapshot)[@"ok"] boolValue], "empty native grid retains header metadata"); Pump();
    AXBGridNode *table = Provider(window).accessibilityChildren.firstObject;
    id header = [table accessibilityColumnHeaderUIElements].firstObject;
    Check([[header accessibilityRole] isEqual:NSAccessibilityButtonRole] && [[header accessibilitySubrole] isEqual:NSAccessibilitySortButtonSubrole], "sortable headers expose native sort-button semantics");
    Check([header accessibilitySortDirection] == NSAccessibilitySortDirectionUnknown, "an unsorted header does not invent an order");
    Check([header accessibilityPerformPress], "headers activate without a data row or editable column");
    NSDictionary *action = Exchange(window, 9021, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"gridHeaderPress"] && [action[@"value"][@"column"] isEqual:@"amount"] && !action[@"value"][@"row"], "header requests carry column identity independently of rows");
    NSDictionary *input = @{@"action": action[@"id"], @"point": @[@50, @31]};
    Exchange(window, 9021, 1, session, snapshot, nil, nil, input); Pump(); Pump();
    Check(canvas.presses == 1 && canvas.releases == 1, "header dispatch produces exactly one native mouse pair");
    Check([Exchange(window, 9021, 1, session, snapshot, nil, nil, input)[@"controlInputResult"][@"accepted"] boolValue], "header mouse input confirms delivery"); Pump();
    Check(canvas.presses == 1, "replayed header input cannot activate twice");
    Exchange(window, 9021, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"activated"}); Pump();
    headerData[@"sort"] = @"ascending"; grid[@"order"] = @2; snapshot[@"revision"] = @2;
    Exchange(window, 9021, 1, session, snapshot); Pump();
    Check([table accessibilityColumnHeaderUIElements].firstObject == header && [header accessibilitySortDirection] == NSAccessibilitySortDirectionAscending, "sort indication changes without replacing the header");
    Check([header accessibilityPerformPress], "a sorted header accepts another activation");
    action = Exchange(window, 9021, 1, session, snapshot)[@"action"];
    input = @{@"action": action[@"id"], @"point": @[@50, @31]};
    headerData[@"enabled"] = @NO; grid[@"order"] = @3; snapshot[@"revision"] = @3;
    Exchange(window, 9021, 1, session, snapshot, nil, nil, input); Pump();
    Check(canvas.presses == 1 && ![header isAccessibilityEnabled] && ![header accessibilityPerformPress], "disabling a header cancels delayed input without clicking");
    Exchange(window, 9021, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"disabled"}); Pump();
    headerData[@"enabled"] = @YES; grid[@"headers"] = @{}; grid[@"layout"] = @{@"rows": @[], @"columns": @[@[@800, @200]]}; grid[@"order"] = @4; snapshot[@"revision"] = @4;
    Exchange(window, 9021, 1, session, snapshot); Pump();
    Check(!NSIsEmptyRect([header accessibilityFrame]), "offscreen empty-grid headers keep their logical bounds");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (@available(macOS 26.0, *)) {
        Check([[header accessibilityActionNames] containsObject:NSAccessibilityScrollToVisibleAction], "offscreen headers expose standard reveal");
        [header accessibilityPerformAction:NSAccessibilityScrollToVisibleAction];
        action = Exchange(window, 9021, 1, session, snapshot)[@"action"];
        Check([action[@"operation"] isEqual:@"gridHeaderReveal"] && !action[@"value"][@"row"], "header reveal does not require or select a row");
        Exchange(window, 9021, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"not visible"}); Pump();
    }
#pragma clang diagnostic pop
    headerData[@"visible"] = @NO; grid[@"headerHeight"] = @0; grid[@"order"] = @5; snapshot[@"revision"] = @5;
    Exchange(window, 9021, 1, session, snapshot); Pump();
    Check([[table accessibilityColumnHeaderUIElements] count] == 0 && ![header isAccessibilityElement] && ![header accessibilityPerformPress], "hidden headers retire their actions and relationships");
    [window close]; Pump();
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        SessionLifetimeTest();
        LogicalFrameTest();
        NavigationOrderTest();
        ProgressAdjustmentTest();
        RefreshDelayTest();
        GridRefreshDelayTest();
        GridControlsTest();
        GridHeaderTest();
        CheckboxFeedbackTest();
        AdjustableTest();
        ComboPopupTest();
        NSWindow *first = Window(@"AXB native test 1");
        NSString *session = Open(first, 101);
        unichar unmatchedSurrogate = 0xD83C;
        NSString *invalidUnicode = [[NSString alloc] initWithCharacters:&unmatchedSurrogate length:1];
        NSString *invalidReply = AXBExchange(101, 1, (__bridge void *)first, session, invalidUnicode);
        NSDictionary *invalidResult = [NSJSONSerialization JSONObjectWithData:[invalidReply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        Check(![invalidResult[@"ok"] boolValue], "unpaired UTF-16 input rejects without crashing the host");
        NSDictionary *button = @{@"id": @"submit", @"role": @"button", @"label": @"Submit", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @120, @30]};
        NSDictionary *snapshot = @{@"version": @1, @"revision": @1, @"label": @"Native test", @"enabled": @YES, @"nodes": @[button]};
        Check([Exchange(first, 101, 1, session, snapshot)[@"ok"] boolValue], "initial native binding accepted");
        Pump();
        Check([Exchange(first, 101, 1, session, snapshot)[@"binding"] isEqual:@"attached"], "known NSWindow attached");
        NSAccessibilityElement *provider = Provider(first);
        Check(provider != nil, "provider added without replacing existing content view");
        id retainedButton = provider.accessibilityChildren.firstObject;
        Check([retainedButton isAccessibilityEnabled], "front window action enabled");
        Check(!NSIsEmptyRect([retainedButton accessibilityFrame]), "native coordinate conversion gives nonempty frame");
        Check([retainedButton accessibilityPerformPress], "native AX press queues action");
        Check(![retainedButton accessibilityPerformPress], "native duplicate press rejected while busy");
        NSDictionary *action = Exchange(first, 101, 1, session, snapshot)[@"action"];
        Check([action[@"node"] isEqual:@"submit"], "owning form receives intended action");
        Check(![Exchange(first, 101, 2, session, snapshot)[@"ok"] boolValue], "another 4D process cannot take session");
        Check(![Exchange(first, 102, 1, session, snapshot)[@"ok"] boolValue], "window reference mismatch rejected");
        NSDictionary *receipt = @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"};
        Check([Exchange(first, 101, 1, session, snapshot, receipt)[@"ok"] boolValue], "application completion accepted");

        NSMutableDictionary *disabledButton = [button mutableCopy]; disabledButton[@"enabled"] = @NO;
        NSMutableDictionary *disabled = [snapshot mutableCopy]; disabled[@"revision"] = @2; disabled[@"nodes"] = @[disabledButton];
        Check([Exchange(first, 101, 1, session, disabled)[@"ok"] boolValue], "disabled control published"); Pump();
        Check(![retainedButton isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)], "disabled button does not advertise AXPress");
        Check(![retainedButton accessibilityPerformPress], "disabled button cannot queue an action");
        NSMutableDictionary *enabled = [snapshot mutableCopy]; enabled[@"revision"] = @3;
        snapshot = enabled;
        Check([Exchange(first, 101, 1, session, snapshot)[@"ok"] boolValue], "control re-enabled"); Pump();

        NSWindow *second = Window(@"AXB native test 2");
        NSString *secondSession = Open(second, 102, 2);
        Check([Exchange(second, 102, 2, secondSession, snapshot)[@"ok"] boolValue], "second process has independent session");
        Pump();
        Check(![retainedButton isAccessibilityEnabled], "background 4D window action blocked");
        Check(![retainedButton accessibilityPerformPress], "background action cannot queue");
        [second close]; Pump(); [first orderFront:nil]; Pump();
        Check([retainedButton isAccessibilityEnabled], "parent re-enabled when covering window closes");

        NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [first beginSheet:sheet completionHandler:nil]; Pump();
        Check(![retainedButton isAccessibilityEnabled] && ![retainedButton accessibilityPerformPress], "sheet blocks parent actions");
        [first endSheet:sheet]; [sheet orderOut:nil]; Pump();

        NSMutableDictionary *removed = [snapshot mutableCopy]; removed[@"revision"] = @4; removed[@"nodes"] = @[];
        Check([Exchange(first, 101, 1, session, removed)[@"ok"] boolValue], "control removal published"); Pump();
        Check(provider.accessibilityChildren.count == 0 && ![retainedButton accessibilityPerformPress], "retained removed control cannot act");
        NSDictionary *tableData = @{@"id": @"lines", @"role": @"table", @"label": @"Lines", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @300, @100]};
        NSDictionary *rowData = @{@"id": @"line-a", @"parent": @"lines", @"role": @"row", @"label": @"Line A", @"value": @"Line A", @"index": @0, @"selected": @NO, @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @300, @20]};
        NSMutableDictionary *firstRow = [rowData mutableCopy]; firstRow[@"selected"] = @YES;
        NSMutableDictionary *collisionRow = [rowData mutableCopy]; collisionRow[@"id"] = @"line-a.summary"; collisionRow[@"index"] = @1; collisionRow[@"selected"] = @YES;
        NSMutableDictionary *tableSnapshot = [snapshot mutableCopy]; tableSnapshot[@"revision"] = @5; tableSnapshot[@"nodes"] = @[tableData, firstRow, collisionRow];
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "row-only table accepted"); Pump();
        id table = provider.accessibilityChildren.firstObject;
        id row = [table accessibilityRows].firstObject;
        Check([row accessibilityChildren].count == 1, "row-only table has a readable cell for screen-reader navigation");
        id retainedCell = [row accessibilityChildren].firstObject;
        Check([[retainedCell accessibilityRole] isEqual:NSAccessibilityCellRole] && [[retainedCell accessibilityValue] isEqual:@"Line A"], "summary cell contains only the permitted row value");
        Check([table accessibilityRowCount] == 2 && [table accessibilityColumnCount] == 1 && [table accessibilityCellForColumn:0 row:0] == retainedCell, "table exposes consistent row column and cell lookup");
        Check([table accessibilityCellForColumn:1 row:0] == nil && [table accessibilityCellForColumn:0 row:2] == nil, "table cell lookup rejects out-of-range indexes");
        Check(![[retainedCell accessibilityIdentifier] isEqual:[[table accessibilityRows][1] accessibilityIdentifier]], "summary cell identity cannot collide with a real row key");
        Check(![retainedCell isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)], "summary cell never advertises text editing");
        Check(![retainedCell isAccessibilitySelectorAllowed:@selector(setAccessibilitySelected:)] && ![retainedCell isAccessibilitySelectorAllowed:@selector(setAccessibilityFocused:)], "summary cell does not advertise unsupported selection or focus setters");
        Check([table accessibilitySelectedRows].count == 2, "multiple selected rows precede cell activation");
        Check([retainedCell accessibilityPerformPress], "screen-reader cell activation queues selection");
        NSDictionary *cellAction = Exchange(first, 101, 1, session, tableSnapshot)[@"action"];
        Check([cellAction[@"node"] isEqual:@"lines"] && [cellAction[@"value"] isEqual:@[@"line-a"]], "cell activation selects its exact owning row");
        NSDictionary *cellReceipt = @{@"id": cellAction[@"id"], @"status": @"completed", @"message": @"selected"};
        firstRow[@"enabled"] = @NO; tableSnapshot[@"revision"] = @6;
        Check([Exchange(first, 101, 1, session, tableSnapshot, cellReceipt)[@"ok"] boolValue], "cell result and disabled row accepted"); Pump();
        Check(![retainedCell accessibilityPerformPress], "disabled row blocks retained summary cell");
        firstRow[@"enabled"] = @YES; firstRow[@"visible"] = @NO; tableSnapshot[@"revision"] = @7;
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "hidden row accepted"); Pump();
        Check(![retainedCell accessibilityPerformPress] && NSIsEmptyRect([retainedCell accessibilityFrame]), "hidden row blocks retained summary cell and frame");
        firstRow[@"visible"] = @YES; firstRow[@"value"] = @"Updated line"; tableSnapshot[@"revision"] = @8;
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "row update accepted"); Pump();
        Check([[retainedCell accessibilityValue] isEqual:@"Updated line"], "retained summary cell reads refreshed row value");
        NSWindow *cover = Window(@"Summary cell covering window"); Pump();
        Check(![retainedCell accessibilityPerformPress], "background window blocks retained summary cell");
        [cover close]; Pump(); [first orderFront:nil]; Pump();
        tableSnapshot[@"revision"] = @9; tableSnapshot[@"nodes"] = @[];
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "summary cell removal accepted"); Pump();
        Check(![retainedCell accessibilityPerformPress] && NSIsEmptyRect([retainedCell accessibilityFrame]), "retained summary cell cannot act after row removal");
        NSDictionary *labelData = @{@"id": @"label", @"role": @"text", @"label": @"Notes", @"value": @"Notes", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @0, @100, @20]};
        NSMutableDictionary *textData = [@{@"id": @"notes", @"role": @"textfield", @"label": @"Notes", @"labelledBy": @"label", @"value": @"Zoë 🎸\rSecond line", @"selection": @[@0, @3], @"multiline": @YES, @"editable": @YES, @"focusable": @YES, @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @300, @100]} mutableCopy];
        tableSnapshot[@"revision"] = @10; tableSnapshot[@"nodes"] = @[labelData, textData];
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "text editor snapshot accepted"); Pump();
        id textNode = provider.accessibilityChildren[1];
        Check([[textNode accessibilityRole] isEqual:NSAccessibilityTextAreaRole] && [textNode accessibilityTitleUIElement] == provider.accessibilityChildren[0], "multiline role and label relationship are native AX semantics");
        Check([[textNode accessibilitySelectedText] isEqual:@"Zoë"] && NSEqualRanges([textNode accessibilitySelectedTextRange], NSMakeRange(0, 3)), "selection uses UTF-16 offsets without splitting Unicode values");
        Check([[textNode accessibilityStringForRange:NSMakeRange(4, 2)] isEqual:@"🎸"] && [textNode accessibilityStringForRange:NSMakeRange(NSUIntegerMax, 1)] == nil, "parameterized text read preserves emoji and rejects overflow");
        Check([textNode accessibilityStringForRange:NSMakeRange(4, 1)] == nil && [textNode accessibilityStringForRange:NSMakeRange(5, 1)] == nil, "text ranges cannot publish half of a supplementary character");
        Check([textNode accessibilityLineForIndex:7] == 1 && NSEqualRanges([textNode accessibilityRangeForLine:1], NSMakeRange(7, 11)), "multiline navigation exposes consistent line ranges");
        Check([textNode accessibilityRangeForLine:99].location == NSNotFound && [textNode accessibilityLineForIndex:99] == NSNotFound, "text navigation rejects nonexistent lines and indexes");
        textData[@"editable"] = @NO; tableSnapshot[@"revision"] = @11;
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "read-only state accepted"); Pump();
        id readOnlyText = provider.accessibilityChildren[1];
        Check(![readOnlyText isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)] && ![readOnlyText isAccessibilitySelectorAllowed:@selector(setAccessibilitySelectedText:)], "read-only text does not advertise mutations");
        Check(readOnlyText != textNode && ![textNode isAccessibilityElement], "changing editor capabilities retires the old writable element");
        textData[@"editable"] = @YES; textData[@"multiline"] = @NO; textData[@"combo"] = @YES; textData[@"value"] = @"Guitar"; tableSnapshot[@"revision"] = @12;
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"ok"] boolValue], "combo snapshot accepted"); Pump();
        id combo = provider.accessibilityChildren[1];
        Check([[combo accessibilityRole] isEqual:NSAccessibilityComboBoxRole] && [combo isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)] &&
            [combo isAccessibilitySelectorAllowed:@selector(accessibilityPerformShowMenu)], "combo advertises editable text and menu semantics");
        Check([combo accessibilityPerformShowMenu], "combo requests its native menu through the guarded action queue");
        Check([Exchange(first, 101, 1, session, tableSnapshot)[@"action"][@"operation"] isEqual:@"showMenu"], "combo dispatches a menu operation without assigning its value");
        [first close]; Pump();
        Check(![Exchange(first, 101, 1, session, removed)[@"ok"] boolValue], "closed form session cannot reopen");
        Check(![retainedButton accessibilityPerformPress], "retained reference safe after window closes");
        Check(![Focus((void *)1)[@"ok"] boolValue], "native focus rejects an unknown opaque window without dereferencing it");
        __block NSDictionary *backgroundFocus;
        dispatch_semaphore_t focusDone = dispatch_semaphore_create(0);
        NSThread *worker = [[NSThread alloc] initWithBlock:^{
            @autoreleasepool { backgroundFocus = Focus((__bridge void *)first); }
            dispatch_semaphore_signal(focusDone);
        }];
        [worker start];
        Check(dispatch_semaphore_wait(focusDone, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, "native focus worker returns without waiting on the UI thread");
        Check([backgroundFocus[@"error"] isEqual:@"notMainThread"], "native focus never reads AppKit from a worker thread");
        NSWindow *editorWindow = Window(@"AXB native input focus test");
        NSTextView *editor = [[NSTextView alloc] initWithFrame:NSMakeRect(10, 10, 300, 150)];
        editor.string = @"Private editor value 🎸";
        [editorWindow.contentView addSubview:editor];
        [NSApp activateIgnoringOtherApps:YES];
        [editorWindow makeKeyAndOrderFront:nil];
        [editorWindow makeFirstResponder:editor];
        editor.selectedRange = NSMakeRange(21, 2);
        for (int i = 0; i < 40 && (!NSApp.isActive || !editorWindow.isKeyWindow); ++i) Pump();
        NSDictionary *focus = Focus((__bridge void *)editorWindow);
        if (![focus[@"ok"] boolValue] || ![focus[@"textInput"] boolValue])
            fprintf(stderr, "Focus diagnostic: active=%d key=%d responder=%s result=%s\n", NSApp.isActive, editorWindow.isKeyWindow, NSStringFromClass(editorWindow.firstResponder.class).UTF8String, focus.description.UTF8String);
        Check([focus[@"ok"] boolValue] && [focus[@"textInput"] boolValue], "native focus identifies an active public text input client");
        Check([focus[@"selection"] isEqual:@[@21, @2]] && [focus[@"caret"][3] doubleValue] > 0, "native focus returns real caret geometry and UTF-16 selection");
        Check(![[focus description] containsString:@"Private editor value"], "native focus does not disclose editor contents");
        NSString *inputSession = Open(editorWindow, 102);
        NSMutableDictionary *inputNode = [@{@"id": @"long-note", @"role": @"textfield", @"label": @"Long note", @"value": editor.string,
            @"selection": focus[@"selection"], @"frame": focus[@"frame"], @"multiline": @YES,
            @"editable": @YES, @"focusable": @YES, @"focused": @YES, @"enabled": @YES, @"visible": @YES} mutableCopy];
        NSMutableDictionary *inputSnapshot = [@{@"version": @1, @"revision": @1, @"label": @"Native input", @"enabled": @YES, @"nodes": @[inputNode]} mutableCopy];
        Check([Exchange(editorWindow, 102, 1, inputSession, inputSnapshot)[@"ok"] boolValue], "long-input native binding accepted"); Pump();
        id inputElement = Provider(editorWindow).accessibilityChildren.firstObject;
        NSString *longInput = [@"Native long note " stringByPaddingToLength:65000 withString:@"text " startingAtIndex:0];
        [inputElement setAccessibilityValue:longInput];
        NSDictionary *inputAction = Exchange(editorWindow, 102, 1, inputSession, inputSnapshot)[@"action"];
        Check(inputAction != nil, "native text replacement reaches its owning action queue");
        editor.selectedRange = NSMakeRange(0, editor.string.length);
        inputNode[@"selection"] = @[@0, @(editor.string.length)]; inputSnapshot[@"revision"] = @2;
        NSDictionary *nativeInput = @{@"action": inputAction[@"id"], @"serial": @1, @"mode": @"insert", @"text": longInput, @"selection": inputNode[@"selection"]};
        Check([Exchange(editorWindow, 102, 1, inputSession, inputSnapshot, nil, nativeInput)[@"ok"] boolValue], "validated long input accepted");
        Check(Exchange(editorWindow, 102, 1, inputSession, inputSnapshot)[@"editorInputResult"] == nil, "host polling before native dispatch sees no premature completion"); Pump();
        Check([editor.string isEqual:longInput], "native insertion reaches the real text input client");
        inputNode[@"value"] = editor.string; inputNode[@"selection"] = @[@(editor.selectedRange.location), @(editor.selectedRange.length)]; inputSnapshot[@"revision"] = @3;
        Check([Exchange(editorWindow, 102, 1, inputSession, inputSnapshot)[@"editorInputResult"][@"accepted"] boolValue], "native input acknowledgement follows actual insertion");
        receipt = @{@"id": inputAction[@"id"], @"status": @"completed", @"message": @"confirmed"};
        Check([Exchange(editorWindow, 102, 1, inputSession, inputSnapshot, receipt)[@"ok"] boolValue], "native insertion completes through a separate host receipt"); Pump();
        [inputElement setAccessibilityValue:@"must not enter a changed selection"];
        inputAction = Exchange(editorWindow, 102, 1, inputSession, inputSnapshot)[@"action"];
        nativeInput = @{@"action": inputAction[@"id"], @"serial": @1, @"mode": @"insert", @"text": @"must not enter a changed selection", @"selection": inputNode[@"selection"]};
        Check([Exchange(editorWindow, 102, 1, inputSession, inputSnapshot, nil, nativeInput)[@"ok"] boolValue], "selection-race test input accepted before scheduling");
        editor.selectedRange = NSMakeRange(0, 0); Pump();
        Check([editor.string isEqual:longInput], "a changed native selection cancels input before insertion");
        Check([Exchange(editorWindow, 102, 1, inputSession, inputSnapshot)[@"editorInputResult"][@"accepted"] isEqual:@NO], "cancelled native input explicitly reports failed delivery");
        NSWindow *focusCover = Window(@"AXB focus cover");
        [focusCover makeKeyAndOrderFront:nil]; Pump();
        Check([Focus((__bridge void *)editorWindow)[@"error"] isEqual:@"inactiveWindow"], "native focus rejects a window that no longer owns keyboard input");
        [focusCover close]; [editorWindow close]; Pump();
        AXBShutdown();
        puts("PASS: native provider lifecycle tests");
    }
}
