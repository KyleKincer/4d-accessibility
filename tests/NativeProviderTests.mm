// Tests this project's own AppKit windows. No external application is controlled.
// Requires an unlocked interactive desktop. This is not the external AX client.
#import <Cocoa/Cocoa.h>
#import "Bridge.h"
#import "BridgePrivate.h"
#import "NativeLayout.h"
#import "DrawnText.h"
#import "MessageDialogs.h"
#import "ProgressWindows.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <cstdio>
#include <cstdlib>
#include <thread>

#undef NSAccessibilityPostNotificationWithUserInfo
#undef NSAccessibilityPostNotification
static NSMutableArray<NSDictionary *> *Announcements, *TextEdits;
static NSMutableArray<NSDictionary *> *Posts;
void AXBTestPostNotification(id element, NSAccessibilityNotificationName notification) {
    if (Posts) [Posts addObject:@{@"element": element ?: NSNull.null, @"notification": notification}];
    NSAccessibilityPostNotification(element, notification);
}
void AXBTestPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification, NSDictionary *userInfo) {
    if (Posts) [Posts addObject:@{@"element": element ?: NSNull.null, @"notification": notification, @"info": userInfo ?: @{}}];
    if ([notification isEqual:NSAccessibilityAnnouncementRequestedNotification] && Announcements)
        [Announcements addObject:@{@"element": element, @"info": userInfo ?: @{}}];
    if ([notification isEqual:NSAccessibilityValueChangedNotification] && userInfo[@"AXTextChangeValues"] && TextEdits)
        [TextEdits addObject:@{@"element": element, @"info": userInfo}];
    NSAccessibilityPostNotificationWithUserInfo(element, notification, userInfo);
}

@interface AXBGridNode (ValueNotificationTests)
- (void)scheduleValueNotifications;
- (void)drainValueNotificationsAtTime:(NSTimeInterval)now;
@end

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
        if ([[child accessibilityIdentifier] hasPrefix:@"axb/"]) return child;
    }
    return nil;
}
static NSDictionary *Focus(void *window) {
    NSString *json = AXBNativeFocus(window);
    return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}
static void StableIdentifierTest(void) {
    NSWindow *first = Window(@"AXB stable locators first"), *second = Window(@"AXB stable locators second");
    [NSApp activateIgnoringOtherApps:YES]; [first makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(first, 9020), *other = Open(second, 9021);
    NSMutableDictionary *button = [@{@"id": @"route-first", @"automationPath": @[@"Search/É%"], @"role": @"button",
        @"label": @"Search", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @120, @30]} mutableCopy];
    NSMutableDictionary *column = [@{@"id": @"internal-column", @"automationKey": @"Description", @"label": @"Description",
        @"enabled": @YES, @"editable": @NO} mutableCopy];
    NSMutableDictionary *grid = [@{@"generation": @"first-binding", @"order": @1, @"rows": @[@"line/1", @"line%2"],
        @"columns": @[column], @"visible": @[], @"selected": @[], @"actions": @{@"select": @YES, @"reveal": @YES}} mutableCopy];
    NSMutableDictionary *tableData = [@{@"id": @"route-table", @"automationPath": @[@"Details", @"Items"], @"role": @"table",
        @"label": @"Items", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @60, @300, @120], @"grid": grid} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"automationKey": @"records.main", @"label": @"Records",
        @"enabled": @YES, @"nodes": @[button, tableData]} mutableCopy];
    Check([Exchange(first, 9020, 1, session, snapshot)[@"ok"] boolValue] &&
        [Exchange(second, 9021, 1, other, snapshot)[@"ok"] boolValue], "two windows accept the same logical screen locators"); Pump();
    id root = Provider(first), otherRoot = Provider(second), retained = [root accessibilityChildren][0];
    NSString *rootID = [root accessibilityIdentifier], *buttonID = [retained accessibilityIdentifier];
    Check([rootID isEqual:@"axb/records.main"] && [rootID isEqual:[otherRoot accessibilityIdentifier]], "root locator repeats within separately owned windows");
    Check([buttonID isEqual:@"axb/records.main/Search%2F%C3%89%25"] &&
        [buttonID isEqual:[[otherRoot accessibilityChildren][0] accessibilityIdentifier]], "ordinary locators are readable, escaped and independent of window UUIDs");
    Check([retained accessibilityPerformPress], "selected live window dispatches its located control");
    NSDictionary *action = Exchange(first, 9020, 1, session, snapshot)[@"action"];
    Check([action[@"node"] isEqual:@"route-first"] && !Exchange(second, 9021, 1, other, snapshot)[@"action"], "stable locator does not replace the session-specific action route");
    Exchange(first, 9020, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"}); Pump();
    AXBGridNode *table = [root accessibilityChildren][1];
    id row = table.accessibilityRows[0], cell = [table accessibilityCellForColumn:0 row:0], header = [table headerForColumn:@"internal-column"];
    Check([[row accessibilityIdentifier] isEqual:@"axb/records.main/Details/Items/row/line%2F1"], "grid row locator uses its key rather than visible position");
    Check([[cell accessibilityIdentifier] isEqual:@"axb/records.main/Details/Items/cell/line%2F1/Description"], "grid cell locator includes the row key and column name");
    Check([[header accessibilityIdentifier] isEqual:@"axb/records.main/Details/Items/header/Description"], "grid headers and cells have distinct locators");
    grid[@"rows"] = @[@"line%2", @"line/1"]; grid[@"order"] = @2; snapshot[@"revision"] = @2;
    Exchange(first, 9020, 1, session, snapshot); Pump();
    Check(table.accessibilityRows[1] == row && [table accessibilityCellForColumn:0 row:1] == cell,
        "sorting preserves row handles and public locators for the same record");
    column[@"automationKey"] = @"Renamed"; grid[@"order"] = @3; snapshot[@"revision"] = @3;
    Exchange(first, 9020, 1, session, snapshot); Pump();
    Check(![cell isAccessibilityElement] && ![header isAccessibilityElement] &&
        [[[table accessibilityCellForColumn:0 row:1] accessibilityIdentifier] hasSuffix:@"/Renamed"], "column locator changes retire retained cells and headers");
    column[@"automationKey"] = @"Description"; grid[@"generation"] = @"replacement-binding"; grid[@"order"] = @1; snapshot[@"revision"] = @4;
    Exchange(first, 9020, 1, session, snapshot); Pump();
    id replacementRow = table.accessibilityRows[1];
    Check(replacementRow != row && [[replacementRow accessibilityIdentifier] isEqual:[row accessibilityIdentifier]] &&
        ![row accessibilityPerformPress], "rebinding can repeat a locator while retiring its former row handle");
    // Resolve only the cell. Reading a header or AXEnabled would materialize
    // the column and hide the independent cell-registry retirement case.
    id headerlessCell = [table accessibilityCellForColumn:0 row:1];
    NSString *headerlessID = [headerlessCell accessibilityIdentifier];
    column[@"automationKey"] = @"HeaderlessRename"; grid[@"order"] = @2; snapshot[@"revision"] = @5;
    Check([Exchange(first, 9020, 1, session, snapshot)[@"ok"] boolValue], "headerless column rename publishes a new snapshot revision"); Pump();
    id renamedCell = [table accessibilityCellForColumn:0 row:1];
    Check(renamedCell != headerlessCell && ![headerlessCell isAccessibilityElement] &&
        [[headerlessCell accessibilityIdentifier] isEqual:headerlessID] &&
        [[renamedCell accessibilityIdentifier] hasSuffix:@"/HeaderlessRename"],
        "column locator changes retire cells even when no column or header was requested");
    button[@"id"] = @"route-replacement"; snapshot[@"revision"] = @6;
    Exchange(first, 9020, 1, session, snapshot); Pump();
    id replacement = [Provider(first) accessibilityChildren][0];
    Check(replacement != retained && [[replacement accessibilityIdentifier] isEqual:buttonID] && ![retained accessibilityPerformPress],
        "replacement internal routes do not resurrect retained ordinary handles");
    snapshot[@"automationKey"] = @"renamed.screen"; snapshot[@"revision"] = @7;
    Exchange(first, 9020, 1, session, snapshot);
    Check(![replacement accessibilityPerformPress], "screen renaming blocks old actions even before the queued native refresh"); Pump();
    AXBDetach(session, 1); Pump();
    snapshot[@"automationKey"] = @"records.main"; snapshot[@"revision"] = @1; button[@"id"] = @"route-reopened";
    NSString *reopened = Open(first, 9020);
    Check(![reopened isEqual:session] && [Exchange(first, 9020, 1, reopened, snapshot)[@"ok"] boolValue], "reopening allocates an independent internal session"); Pump();
    Check([[Provider(first) accessibilityIdentifier] isEqual:rootID] &&
        [[[Provider(first) accessibilityChildren][0] accessibilityIdentifier] isEqual:buttonID] && ![retained accessibilityPerformPress],
        "reopening repeats public locators and keeps closed references retired");
    Check(![Exchange(first, 9020, 1, session, snapshot)[@"ok"] boolValue], "old session cannot route through a reopened stable screen");
    [first close]; [second close]; Pump();
}
static void OutlineSemanticsTest(void) {
    NSWindow *window = Window(@"AXB outline semantics");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9040);
    NSMutableDictionary *grid = [@{@"generation": @"outline-first", @"order": @1, @"rows": @[@"group", @"leaf", @"later"],
        @"columns": @[@{@"id": @"a", @"label": @"Item", @"enabled": @YES, @"editable": @YES},
                       @{@"id": @"b", @"label": @"Value", @"enabled": @YES, @"editable": @YES}],
        @"visible": @[@"group", @"leaf", @"later"], @"selected": @[@"later"],
        @"actions": @{@"select": @YES, @"edit": @YES, @"reveal": @NO},
        @"outline": @{
            @"group": @{@"parent": @"", @"level": @0, @"kind": @"group", @"label": @"Repeated", @"expanded": @YES, @"frame": @[@10, @20, @300, @24]},
            @"leaf": @{@"parent": @"group", @"level": @1, @"kind": @"leaf"},
            @"later": @{@"parent": @"", @"level": @0, @"kind": @"group", @"label": @"Repeated", @"expanded": @NO, @"frame": @[@10, @68, @300, @24]}},
        @"frames": @{@"group": @{@"a": @[@10, @20, @300, @24]}, @"later": @{@"a": @[@10, @68, @300, @24]},
                     @"leaf": @{@"a": @[@10, @44, @150, @24], @"b": @[@160, @44, @150, @24]}}} mutableCopy];
    NSMutableDictionary *data = [@{@"id": @"grid", @"role": @"table", @"label": @"Groups", @"value": @"", @"visible": @YES,
        @"enabled": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Outline", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Check([Exchange(window, 9040, 1, session, snapshot)[@"ok"] boolValue], "native outline accepts authoritative selection"); Pump();
    AXBGridNode *outline = Provider(window).accessibilityChildren.firstObject;
    id group = outline.accessibilityRows[0], cell = [outline accessibilityCellForColumn:0 row:0], content = [cell accessibilityChildren][0];
    Check([outline.accessibilityRole isEqual:NSAccessibilityOutlineRole] && [outline.accessibilityRoleDescription isEqual:@"outline"], "native outline role and description agree");
    Check(AXBAttributeIsSettable(outline, NSAccessibilitySelectedRowsAttribute), "known outline selection advertises its permitted setter");
    Check([[content accessibilityRole] isEqual:NSAccessibilityStaticTextRole] && !AXBAttributeIsSettable(content, NSAccessibilityValueAttribute), "editable leaf columns cannot turn group labels into editors");
    Check([group accessibilityDisclosedRows][0] == outline.accessibilityRows[1], "native outline discloses the indexed direct child");
    NSDictionary *frames = grid[@"frames"];
    grid[@"columns"] = [[grid[@"columns"] reverseObjectEnumerator] allObjects];
    grid[@"frames"] = @{@"group": @{@"b": @[@10, @20, @300, @24]}, @"later": @{@"b": @[@10, @68, @300, @24]}, @"leaf": frames[@"leaf"]};
    grid[@"order"] = @2; snapshot[@"revision"] = @2;
    Check([Exchange(window, 9040, 1, session, snapshot)[@"ok"] boolValue], "outline columns can reorder with new label-cell geometry"); Pump();
    Check(![cell isAccessibilityElement] && ![content isAccessibilityElement], "reordering away from the label column retires the group cell and content");
    grid[@"columns"] = [[grid[@"columns"] reverseObjectEnumerator] allObjects]; grid[@"frames"] = frames;
    grid[@"order"] = @3; snapshot[@"revision"] = @3;
    Exchange(window, 9040, 1, session, snapshot); Pump();
    Check([outline accessibilityCellForColumn:0 row:0] != cell && ![cell isAccessibilityElement], "reordering back cannot resurrect the old group cell");
    [grid removeObjectForKey:@"outline"]; grid[@"generation"] = @"flat-replacement"; snapshot[@"revision"] = @4;
    Check([Exchange(window, 9040, 1, session, snapshot)[@"ok"] boolValue], "new generation accepts a flat replacement"); Pump();
    AXBGridNode *flat = Provider(window).accessibilityChildren.firstObject;
    Check(flat != outline && !outline.isAccessibilityElement && [flat.accessibilityRole isEqual:NSAccessibilityTableRole], "table replacement retires the retained outline root");
    [window close]; Pump();
}
static void OutlineDisclosureTest(void) {
    Announcements = [NSMutableArray new];
    NSWindow *window = Window(@"AXB outline disclosure");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9041);
    NSMutableDictionary *groupData = [@{@"parent": @"", @"level": @0, @"kind": @"group", @"label": @"Group", @"expanded": @NO,
        @"frame": @[@10, @20, @300, @24]} mutableCopy];
    NSMutableDictionary *grid = [@{@"generation": @"disclosure-first", @"order": @1, @"rows": @[@"group", @"leaf"],
        @"columns": @[@{@"id": @"item", @"label": @"Item", @"enabled": @YES, @"editable": @NO}],
        @"visible": @[@"group", @"leaf"], @"selectionKnown": @NO,
        @"actions": @{@"disclose": @YES},
        @"outline": @{@"group": groupData, @"leaf": @{@"parent": @"", @"level": @0, @"kind": @"leaf"}},
        @"frames": @{@"group": @{@"item": @[@10, @20, @300, @24]}, @"leaf": @{@"item": @[@10, @44, @300, @24]}}} mutableCopy];
    NSMutableDictionary *data = [@{@"id": @"grid", @"role": @"table", @"label": @"Groups", @"value": @"", @"visible": @YES,
        @"enabled": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Disclosure", @"enabled": @YES, @"nodes": @[data]} mutableCopy];
    Check([Exchange(window, 9041, 1, session, snapshot)[@"ok"] boolValue], "native disclosure accepts its independent outline capability"); Pump();
    AXBGridNode *outline = Provider(window).accessibilityChildren.firstObject;
    id group = outline.accessibilityRows[0], leaf = outline.accessibilityRows[1];
    id cell = [outline accessibilityCellForColumn:0 row:0], content = [cell accessibilityChildren][0];
    Check([[content accessibilityRole] isEqual:NSAccessibilityDisclosureTriangleRole] && [[content accessibilityLabel] isEqual:@"Group"] &&
        [[content accessibilityValue] isEqual:@NO] && [[cell accessibilityValue] isEqual:@"Group"],
        "interactive group child exposes a labeled Boolean disclosure control while its cell retains the caption");
    Check(AXBAttributeIsSettable(group, NSAccessibilityDisclosingAttribute) && !AXBAttributeIsSettable(leaf, NSAccessibilityDisclosingAttribute),
        "external mutability routing permits live group disclosure and omits leaves");
    Check([group isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && [cell isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] &&
        [content isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && ![leaf isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)],
        "group row, cell and disclosure child permit disclosure without leaf selection");
    Check(!AXBAttributeIsSettable(content, NSAccessibilityValueAttribute) && !AXBAttributeIsSettable(content, NSAccessibilityFocusedAttribute) &&
        !AXBAttributeIsSettable(group, NSAccessibilitySelectedAttribute), "disclosure cannot enable group editing, keyboard focus or unknown selection");
    Check([content accessibilityPerformPress] && [[content accessibilityValue] isEqual:@NO], "disclosure-child activation queues intent without optimistically changing its value");
    NSDictionary *action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Check(outline.owner.actionFeedback[@"control"] == content && [outline.owner.actionFeedback[@"id"] isEqual:action[@"id"]],
        "disclosure feedback belongs to the retained control and its exact queued action");
    Check(Announcements.count == 0, "queued disclosure cannot announce an optimistic state");
    Check([action[@"operation"] isEqual:@"gridSetExpanded"] && [action[@"value"][@"expanded"] boolValue] && !action[@"value"][@"expectedGroup"][@"frame"],
        "native press resolves the desired state and semantic guard from the refreshed group");
    groupData[@"expanded"] = @YES; grid[@"order"] = @2; snapshot[@"revision"] = @2;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check(outline.owner.actionFeedback != nil, "disclosure publication cannot announce success before its host receipt");
    Check(Announcements.count == 0, "published state alone produces no disclosure success announcement");
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check([cell accessibilityChildren][0] == content && [[content accessibilityValue] isEqual:@YES], "expansion retains the disclosure child and updates its Boolean from application state");
    Check(outline.owner.actionFeedback == nil, "confirmed disclosure consumes feedback exactly once");
    Check(Announcements.count == 1 && Announcements[0][@"element"] == window &&
        [Announcements[0][@"info"][NSAccessibilityAnnouncementKey] isEqual:@"Group: expanded"],
        "confirmed expansion posts the exact caption and state to its owning window once");
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(outline.owner.actionFeedback == nil, "disclosure receipt replay cannot recreate feedback");
    Check(Announcements.count == 1, "receipt replay produces no additional disclosure announcement");
    [group setAccessibilityDisclosed:NO];
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"gridSetExpanded"] && [action[@"value"][@"expanded"] isEqual:@NO],
        "group setter requests the explicit Boolean instead of toggling");
    groupData[@"expanded"] = @NO; grid[@"order"] = @3; snapshot[@"revision"] = @3;
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(Announcements.count == 2 && [Announcements[1][@"info"][NSAccessibilityAnnouncementKey] isEqual:@"Group: collapsed"],
        "confirmed row-setter collapse announces the authoritative collapsed state");
    [group setAccessibilityDisclosed:NO];
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Check(action && outline.owner.actionFeedback == nil, "idempotent disclosure retains host validation without creating speech feedback");
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"already collapsed"}); Pump();
    Check(Announcements.count == 2, "idempotent completion cannot repeat the collapsed announcement");
    grid[@"disabled"] = @[@"group"]; snapshot[@"revision"] = @4;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check(!AXBAttributeIsSettable(group, NSAccessibilityDisclosingAttribute) && ![content accessibilityPerformPress] && [cell accessibilityChildren][0] == content &&
        [content isAccessibilityElement] && ![content isAccessibilityEnabled],
        "disabled group disclosure rejects through both native entry paths");
    grid[@"disabled"] = @[]; snapshot[@"revision"] = @5;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check([cell accessibilityChildren][0] == content && [content isAccessibilityEnabled], "reenabling a group keeps the same disclosure representation");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [content accessibilityPerformAction:NSAccessibilityPressAction];
#pragma clang diagnostic pop
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"gridSetExpanded"] && [action[@"value"][@"expanded"] isEqual:@YES], "legacy disclosure press routes through the same guarded intent");
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"cancelled"}); Pump();
    Check(outline.owner.actionFeedback == nil && Announcements.count == 2, "rejected disclosure produces no success announcement");
    Check([content accessibilityPerformPress], "disclosure accepts an intent before delayed state publication");
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(outline.owner.actionFeedback != nil && Announcements.count == 2, "receipt before state waits without announcing the old value");
    groupData[@"expanded"] = @YES; grid[@"order"] = @4; snapshot[@"revision"] = @6;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check(outline.owner.actionFeedback == nil && Announcements.count == 3 &&
        [Announcements[2][@"info"][NSAccessibilityAnnouncementKey] isEqual:@"Group: expanded"],
        "delayed state consumes the retained exact receipt and announces once");
    Check([content accessibilityPerformPress], "disclosure accepts an intent before its feedback expires");
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    NSMutableDictionary *expired = [outline.owner.actionFeedback mutableCopy]; expired[@"deadline"] = @0;
    outline.owner.actionFeedback = expired;
    groupData[@"expanded"] = @NO; grid[@"order"] = @5; snapshot[@"revision"] = @7;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check(outline.owner.actionFeedback == nil && Announcements.count == 3, "state arriving after the feedback deadline cannot announce an expired request");
    Check([content accessibilityPerformPress], "disclosure accepts an intent before a newer accepted action");
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(outline.owner.actionFeedback != nil, "confirmed disclosure retains feedback while its state is unchanged");
    [group setAccessibilityDisclosed:NO];
    NSDictionary *newer = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Check(newer && ![newer[@"id"] isEqual:action[@"id"]] && outline.owner.actionFeedback == nil,
        "a newer accepted action cancels the older disclosure feedback");
    Exchange(window, 9041, 1, session, snapshot, @{@"id": newer[@"id"], @"status": @"completed", @"message": @"unchanged"}); Pump();
    Check(Announcements.count == 3, "newer idempotent completion cannot revive an older announcement");
    Check([content accessibilityPerformPress], "disclosure accepts an intent before its caption changes");
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    groupData[@"label"] = @"Renamed"; groupData[@"expanded"] = @YES; grid[@"order"] = @6; snapshot[@"revision"] = @8;
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(outline.owner.actionFeedback == nil && Announcements.count == 3, "changed captions cancel disclosure feedback without speaking a replacement target");
    Check([content accessibilityPerformPress], "disclosure accepts an intent before capability retirement");
    action = Exchange(window, 9041, 1, session, snapshot)[@"action"];
    Exchange(window, 9041, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(outline.owner.actionFeedback != nil, "confirmed disclosure awaits state before capability retirement");
    grid[@"actions"] = @{@"disclose": @NO}; snapshot[@"revision"] = @9;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check(outline.owner.actionFeedback == nil && Announcements.count == 3, "capability retirement cancels confirmed feedback without announcing success");
    grid[@"actions"] = @{@"disclose": @YES}; snapshot[@"revision"] = @10;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    Check(![content isAccessibilityElement] && ![content accessibilityPerformPress],
        "capability revoke and restore permanently retire the old child without an intervening children query");
    content = [cell accessibilityChildren][0];
    grid[@"actions"] = @{@"disclose": @NO}; snapshot[@"revision"] = @11;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    id text = [cell accessibilityChildren][0];
    Check(text != content && [[text accessibilityRole] isEqual:NSAccessibilityStaticTextRole] && ![content isAccessibilityElement] && ![content accessibilityPerformPress],
        "capability removal without generation replacement retires the disclosure child and restores read-only text");
    grid[@"generation"] = @"controller-removed"; snapshot[@"revision"] = @12;
    Exchange(window, 9041, 1, session, snapshot); Pump();
    [group setAccessibilityDisclosed:YES];
    Check(![group isAccessibilityElement] && !AXBAttributeIsSettable(group, NSAccessibilityDisclosingAttribute) && ![content accessibilityPerformPress] &&
        !Exchange(window, 9041, 1, session, snapshot)[@"action"], "controller removal retires retained group, cell and disclosure actions");
    [window close]; Pump();
    Announcements = nil;
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
@property(nonatomic) NSEventModifierFlags lastFlags;
@end
@implementation AXBStepperTestView
- (BOOL)isFlipped { return YES; }
- (void)mouseDown:(NSEvent *)event { self.presses++; self.lastFlags = event.modifierFlags; self.lastPoint = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.menu) [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidBeginTrackingNotification object:self.menu]; }
- (void)mouseUp:(NSEvent *)event { (void)event; self.releases++; }
@end
static void SingleSelectionRowTest(void) {
    // A row's selected setter in a single-selection grid requests only that row.
    NSWindow *window = Window(@"AXB single selection rows");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9042);
    NSMutableDictionary *grid = [@{@"generation": @"single", @"order": @1, @"rows": @[@"g", @"l"],
        @"columns": @[@{@"id": @"item", @"label": @"Item", @"enabled": @YES, @"editable": @NO, @"selectionTarget": @YES}],
        @"visible": @[@"g", @"l"], @"selected": @[@"g"], @"selectionMode": @"single",
        @"actions": @{@"disclose": @YES, @"select": @YES},
        @"outline": @{@"g": @{@"parent": @"", @"level": @0, @"kind": @"group", @"label": @"Guitars", @"expanded": @NO, @"frame": @[@10, @20, @300, @18]},
                      @"l": @{@"parent": @"", @"level": @0, @"kind": @"leaf"}},
        @"frames": @{@"g": @{@"item": @[@10, @20, @300, @18]}, @"l": @{@"item": @[@10, @38, @300, @18]}}} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"List", @"enabled": @YES, @"nodes": @[
        @{@"id": @"grid", @"role": @"table", @"label": @"Catalog", @"value": @"", @"visible": @YES, @"enabled": @YES,
          @"frame": @[@10, @20, @300, @140], @"grid": grid}]} mutableCopy];
    Check([Exchange(window, 9042, 1, session, snapshot)[@"ok"] boolValue], "single-selection outline accepted"); Pump();
    AXBGridNode *outline = Provider(window).accessibilityChildren.firstObject;
    [outline.accessibilityRows[1] setAccessibilitySelected:YES];
    NSDictionary *action = Exchange(window, 9042, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"gridSelect"] && [action[@"value"] isEqual:@[@"l"]], "selecting a row of a single-selection grid requests only that row");
    [window close]; Pump();
}
static void SplitterTest(void) {
    // A splitter is adjusted by the host through 4D's own splitter handling.
    NSWindow *window = Window(@"AXB splitter");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9043);
    NSDictionary *splitter = @{@"id": @"split", @"role": @"splitter", @"label": @"Divider", @"value": @100, @"enabled": @YES, @"visible": @YES,
        @"focusable": @NO, @"adjustable": @YES, @"vertical": @YES, @"step": @10, @"min": @0, @"max": @520, @"frame": @[@100, @20, @6, @200]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Panes", @"enabled": @YES, @"nodes": @[splitter]} mutableCopy];
    Check([Exchange(window, 9043, 1, session, snapshot)[@"ok"] boolValue], "a splitter node is accepted"); Pump();
    id node = Provider(window).accessibilityChildren.firstObject;
    Check([[node accessibilityRole] isEqual:NSAccessibilitySplitterRole] && [node accessibilityOrientation] == NSAccessibilityOrientationVertical &&
          [[node accessibilityValue] isEqual:@100] && [[node accessibilityLabel] isEqual:@"Divider"], "a vertical splitter reports its role, orientation and position");
    Check([node isAccessibilitySelectorAllowed:@selector(accessibilityPerformIncrement)] && [node isAccessibilitySelectorAllowed:@selector(accessibilityPerformDecrement)],
          "a splitter can be adjusted in both directions");
    Check([node accessibilityPerformIncrement], "an increment is accepted");
    NSDictionary *action = Exchange(window, 9043, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"increment"], "the increment reaches the host");
    Check(![Exchange(window, 9043, 1, session, snapshot, nil, nil, @{@"action": action[@"id"]})[@"ok"] boolValue], "a splitter takes no native pointer input");
    Exchange(window, 9043, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"Splitter moved"}); Pump();
    Check(AXBAttributeIsSettable(node, NSAccessibilityValueAttribute), "VoiceOver can write a splitter's position");
    [node setAccessibilityValue:@126];
    action = Exchange(window, 9043, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"setValue"] && [action[@"value"] isEqual:@126], "a written position reaches the host as the requested position");
    Exchange(window, 9043, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"Splitter moved"}); Pump();
    NSMutableDictionary *invalid = [splitter mutableCopy]; [invalid removeObjectForKey:@"vertical"]; snapshot[@"nodes"] = @[invalid]; snapshot[@"revision"] = @2;
    Check(![Exchange(window, 9043, 1, session, snapshot)[@"ok"] boolValue], "a splitter without an orientation is rejected");
    [window close]; Pump();
}
// Like 4D's picture popup palette: mouse-down runs a menu of one item whose
// view draws every cell, and the item's tag is the chosen cell.
@interface AXBPicturePaletteTestView : NSView
@property(nonatomic) NSInteger picked;
@property(nonatomic) NSUInteger opened;
@end
@implementation AXBPicturePaletteTestView
- (BOOL)isFlipped { return YES; }
- (void)mouseDown:(NSEvent *)event {
    self.opened++;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(pick:) keyEquivalent:@""];
    item.target = self;
    item.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 96, 32)];
    [menu addItem:item];
    [menu popUpMenuPositioningItem:nil atLocation:[self convertPoint:event.locationInWindow fromView:nil] inView:self];
}
- (void)pick:(NSMenuItem *)item { self.picked = item.tag; }
@end
static void PicturePopupTest(void) {
    NSWindow *window = Window(@"AXB picture popup");
    AXBPicturePaletteTestView *canvas = [[AXBPicturePaletteTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9044);
    NSDictionary *popup = @{@"id": @"color", @"role": @"popup", @"label": @"Color", @"value": @"Blue", @"enabled": @YES, @"visible": @YES,
        @"choices": @[@"Blue", @"Purple", @"Violet"], @"choice": @1, @"frame": @[@20, @20, @32, @32]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Pictures", @"enabled": @YES, @"nodes": @[popup]} mutableCopy];
    Check([Exchange(window, 9044, 1, session, snapshot)[@"ok"] boolValue], "a picture popup with choices is accepted"); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    Check([[node accessibilityRole] isEqual:NSAccessibilityPopUpButtonRole] && [[node accessibilityValue] isEqual:@"Blue"] &&
          [node isAccessibilitySelectorAllowed:@selector(accessibilityPerformShowMenu)], "a picture popup is a popup button showing its chosen cell");
    Check(![node queue:@"choose" value:@0] && ![node queue:@"choose" value:@4] && ![node queue:@"choose" value:@1.5], "only one of its cells can be chosen");
    // Pressing it offers the labeled cells in a native menu; choosing one asks the host for that cell.
    AXBWindowView *owner = node.owner;
    __block NSArray *titles = nil;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        NSMenu *menu = notification.object;
        if (menu != owner.choiceMenu) return;
        titles = [menu.itemArray valueForKey:@"title"];
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{ [menu performActionForItemAtIndex:2]; [menu cancelTracking]; });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }];
    Check([node accessibilityPerformPress], "pressing a picture popup offers its choices"); Pump(); Pump();
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    Check([titles isEqual:@[@"Blue", @"Purple", @"Violet"]] && !owner.choiceMenu, "the choice menu lists every cell's label and closes after a choice");
    NSDictionary *action = Exchange(window, 9044, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"choose"] && [action[@"value"] isEqual:@3], "the chosen cell reaches the host");
    Check(![Exchange(window, 9044, 1, session, snapshot, nil, nil, @{@"action": action[@"id"], @"point": @[@36, @36], @"choice": @2})[@"ok"] boolValue],
          "native input for a different cell is rejected");
    NSDictionary *input = @{@"action": action[@"id"], @"point": @[@36, @36], @"choice": @3};
    Exchange(window, 9044, 1, session, snapshot, nil, nil, input); Pump(); Pump();
    Check(canvas.opened == 1 && canvas.picked == 3, "the control's own click opens its palette and the plugin chooses that cell");
    Check([Exchange(window, 9044, 1, session, snapshot, nil, nil, input)[@"controlInputResult"][@"accepted"] boolValue], "the palette choice has an exact acknowledgement");
    Exchange(window, 9044, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"Choice confirmed"}); Pump();
    NSMutableDictionary *invalid = [popup mutableCopy]; invalid[@"choice"] = @4; snapshot[@"nodes"] = @[invalid]; snapshot[@"revision"] = @2;
    Check(![Exchange(window, 9044, 1, session, snapshot)[@"ok"] boolValue], "a chosen cell outside its choices is rejected");
    [window close]; Pump();
}
static void PictureEditTest(void) {
    // An editable picture offers its standard edit actions as custom actions.
    NSWindow *window = Window(@"AXB editable picture");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9045);
    NSDictionary *photo = @{@"id": @"photo", @"role": @"image", @"label": @"Photo", @"value": @"No picture", @"enabled": @YES, @"visible": @YES,
        @"pictureActions": @[@"paste"], @"frame": @[@20, @20, @120, @80]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Pictures", @"enabled": @YES, @"nodes": @[photo]} mutableCopy];
    Check([Exchange(window, 9045, 1, session, snapshot)[@"ok"] boolValue], "an editable picture is accepted"); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    NSArray *actions = node.accessibilityCustomActions;
    Check([[node accessibilityRole] isEqual:NSAccessibilityImageRole] && [[actions valueForKey:@"name"] isEqual:@[@"Paste"]],
          "an empty editable picture offers only Paste");
    Check(![node queue:@"pictureEdit" value:@"cut"] && ![node queue:@"pictureEdit" value:@"print"], "only an offered edit can be requested");
    Check([actions.firstObject handler](), "performing Paste is accepted");
    NSDictionary *action = Exchange(window, 9045, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"pictureEdit"] && [action[@"value"] isEqual:@"paste"], "the requested edit reaches the host");
    Exchange(window, 9045, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"Picture edited"}); Pump();
    NSMutableDictionary *full = [photo mutableCopy]; full[@"value"] = @""; full[@"pictureActions"] = @[@"cut", @"copy", @"paste", @"clear"];
    snapshot[@"nodes"] = @[full]; snapshot[@"revision"] = @2;
    Exchange(window, 9045, 1, session, snapshot); Pump();
    Check([[node.accessibilityCustomActions valueForKey:@"name"] isEqual:@[@"Cut", @"Copy", @"Paste", @"Clear"]], "a picture with content offers every edit");
    NSMutableDictionary *invalid = [photo mutableCopy]; invalid[@"role"] = @"button"; snapshot[@"nodes"] = @[invalid]; snapshot[@"revision"] = @3;
    Check(![Exchange(window, 9045, 1, session, snapshot)[@"ok"] boolValue], "picture actions on another role are rejected");
    [window close]; Pump();
}
static void ButtonMenuTest(void) {
    // A button's own pop-up menu: Show Menu requests the click the host places, on the
    // arrow of a separated menu, and the plugin delivers it as an ordinary click.
    NSWindow *window = Window(@"AXB button menu");
    AXBStepperTestView *canvas = [[AXBStepperTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9046);
    NSMutableDictionary *search = [@{@"id": @"search", @"role": @"button", @"label": @"Search", @"value": @"", @"enabled": @YES, @"visible": @YES,
        @"menu": @"separated", @"frame": @[@20, @20, @160, @24]} mutableCopy];
    NSDictionary *plain = @{@"id": @"plain", @"role": @"button", @"label": @"Plain", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @60, @160, @24]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Button menus", @"enabled": @YES, @"nodes": @[search, plain]} mutableCopy];
    Check([Exchange(window, 9046, 1, session, snapshot)[@"ok"] boolValue], "a button with a pop-up menu is accepted"); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject, *other = Provider(window).accessibilityChildren.lastObject;
    Check([node isAccessibilitySelectorAllowed:@selector(accessibilityPerformShowMenu)] && [node isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] &&
          ![other isAccessibilitySelectorAllowed:@selector(accessibilityPerformShowMenu)], "only a button with a pop-up menu offers Show Menu beside Press");
    Check(![node queue:@"showMenu" value:@"x"] && ![other queue:@"showMenu" value:nil], "Show Menu takes no value and needs the button's menu");
    Check([node accessibilityPerformShowMenu], "Show Menu is accepted");
    NSDictionary *action = Exchange(window, 9046, 1, session, snapshot)[@"action"];
    Check([action[@"operation"] isEqual:@"showMenu"] && [action[@"node"] isEqual:@"search"], "Show Menu reaches the host for that button");
    NSDictionary *outside = @{@"action": action[@"id"], @"point": @[@200, @35]};
    Exchange(window, 9046, 1, session, snapshot, nil, nil, outside); Pump(); Pump();
    Check(canvas.presses == 0, "a click outside the button is never delivered");
    Exchange(window, 9046, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"outside"}); Pump();
    Check([node accessibilityPerformShowMenu], "Show Menu can be requested again");
    action = Exchange(window, 9046, 1, session, snapshot)[@"action"];
    NSDictionary *arrow = @{@"action": action[@"id"], @"point": @[@175, @39]};
    Exchange(window, 9046, 1, session, snapshot, nil, nil, arrow); Pump(); Pump();
    Check(canvas.presses == 1 && canvas.releases == 1 && canvas.lastPoint.x == 175 && canvas.lastPoint.y == 39,
          "the menu's click is one ordinary mouse pair at the arrow the host placed");
    Check([Exchange(window, 9046, 1, session, snapshot, nil, nil, arrow)[@"controlInputResult"][@"accepted"] boolValue], "the menu's click has an exact acknowledgement");
    Exchange(window, 9046, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"dispatched"}); Pump();
    NSMutableDictionary *invalid = [search mutableCopy]; invalid[@"menu"] = @"dropdown"; snapshot[@"nodes"] = @[invalid, plain]; snapshot[@"revision"] = @2;
    Check(![Exchange(window, 9046, 1, session, snapshot)[@"ok"] boolValue], "an unknown menu placement is rejected");
    invalid[@"menu"] = @"linked"; invalid[@"role"] = @"checkbox"; invalid[@"value"] = @NO;
    Check(![Exchange(window, 9046, 1, session, snapshot)[@"ok"] boolValue], "a menu on another role is rejected");
    [window close]; Pump();
}
static void SelectionInputTest(void) {
    NSWindow *window = Window(@"AXB native row selection");
    AXBStepperTestView *canvas = [[AXBStepperTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9026);
    NSMutableDictionary *grid = [@{@"generation": @"row-click", @"order": @1, @"rows": @[@"one", @"two"],
        @"columns": @[@{@"id": @"name", @"label": @"Name", @"enabled": @YES, @"editable": @NO, @"selectionTarget": @YES}],
        @"visible": @[@"one", @"two"], @"selected": @[], @"selectionMode": @"multiple",
        @"frames": @{@"one": @{@"name": @[@10, @30, @200, @24]}, @"two": @{@"name": @[@10, @54, @200, @24]}},
        @"actions": @{@"select": @YES, @"reveal": @YES, @"edit": @NO}} mutableCopy];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Native selection", @"enabled": @YES,
        @"nodes": @[@{@"id": @"items", @"role": @"table", @"label": @"Items", @"value": @"", @"visible": @YES,
            @"enabled": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid}]} mutableCopy];
    Exchange(window, 9026, 1, session, snapshot); Pump();
    AXBGridNode *table = Provider(window).accessibilityChildren.firstObject;
    [table setAccessibilitySelectedRows:[table accessibilityRows]];
    NSDictionary *action = Exchange(window, 9026, 1, session, snapshot)[@"action"];
    NSDictionary *first = @{@"action": action[@"id"], @"serial": @1, @"point": @[@30, @42]};
    Exchange(window, 9026, 1, session, snapshot, nil, nil, first); Pump(); Pump();
    Check(canvas.presses == 1 && canvas.releases == 1 && (canvas.lastFlags & NSEventModifierFlagCommand), "multiple row selection dispatches a complete native command-click");
    Check([Exchange(window, 9026, 1, session, snapshot)[@"controlInputResult"][@"serial"] isEqual:@1], "first native selection click has its own acknowledgement");
    grid[@"selected"] = @[@"one"]; snapshot[@"revision"] = @2;
    NSDictionary *second = @{@"action": action[@"id"], @"serial": @2, @"point": @[@30, @66]};
    Exchange(window, 9026, 1, session, snapshot, nil, nil, second); Pump(); Pump();
    Check(canvas.presses == 2 && canvas.releases == 2, "a second selection step delivers one additional mouse pair");
    Exchange(window, 9026, 1, session, snapshot, nil, nil, second); Pump();
    Check(canvas.presses == 2, "replaying a selection step cannot toggle the row twice");
    grid[@"selected"] = @[@"one", @"two"]; snapshot[@"revision"] = @3;
    Exchange(window, 9026, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    grid[@"selectionMode"] = @"single"; grid[@"selected"] = @[@"one"]; snapshot[@"revision"] = @4;
    Exchange(window, 9026, 1, session, snapshot); Pump();
    [table setAccessibilitySelectedRows:@[[table accessibilityRows][1]]];
    action = Exchange(window, 9026, 1, session, snapshot)[@"action"];
    NSDictionary *single = @{@"action": action[@"id"], @"serial": @1, @"point": @[@30, @66]};
    Exchange(window, 9026, 1, session, snapshot, nil, nil, single); Pump(); Pump();
    Check(canvas.presses == 3 && !(canvas.lastFlags & NSEventModifierFlagCommand), "single row selection uses the normal unmodified click");
    [window close]; Pump();
}
static void ButtonInputTest(void) {
    NSWindow *window = Window(@"AXB guarded button delivery");
    AXBStepperTestView *canvas = [[AXBStepperTestView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:canvas];
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9025);
    NSMutableDictionary *button = [@{@"id": @"remember", @"role": @"button", @"label": @"Remember",
        @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @120, @30]} mutableCopy];
    NSDictionary *caption = @{@"id": @"caption", @"role": @"text", @"label": @"Remember caption",
        @"value": @"Remember", @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @25, @100, @20]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Button input", @"enabled": @YES, @"nodes": @[button, caption]} mutableCopy];
    Exchange(window, 9025, 1, session, snapshot); Pump();
    AXBNode *node = Provider(window).accessibilityChildren.firstObject;
    NSPoint middle = NSMakePoint(NSMidX([node accessibilityFrame]), NSMidY([node accessibilityFrame]));
    Check([Provider(window) accessibilityHitTest:middle] == node, "static caption hit resolves to its overlapping button");
    Check([node accessibilityPerformPress], "ordinary button accepts an accessibility activation");
    NSDictionary *action = Exchange(window, 9025, 1, session, snapshot)[@"action"];
    NSDictionary *input = @{@"action": action[@"id"], @"point": @[@50, @35]};
    Exchange(window, 9025, 1, session, snapshot, nil, nil, input); Pump(); Pump();
    Check(canvas.presses == 1 && canvas.releases == 1 && canvas.lastPoint.x == 50 && canvas.lastPoint.y == 35, "ordinary button receives one complete native mouse pair at the verified point");
    Check([Exchange(window, 9025, 1, session, snapshot, nil, nil, input)[@"controlInputResult"][@"accepted"] boolValue], "ordinary button dispatch has an exact acknowledgement"); Pump();
    Check(canvas.presses == 1, "replaying an ordinary button request cannot repeat its handler");
    Exchange(window, 9025, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"dispatched"}); Pump();
    Check([node accessibilityPerformPress], "ordinary button can request a subsequent activation");
    action = Exchange(window, 9025, 1, session, snapshot)[@"action"];
    input = @{@"action": action[@"id"], @"point": @[@50, @35]};
    Exchange(window, 9025, 1, session, snapshot, nil, nil, input);
    button[@"enabled"] = @NO; snapshot[@"revision"] = @2;
    Exchange(window, 9025, 1, session, snapshot); Pump();
    Check(canvas.presses == 1 && ![Exchange(window, 9025, 1, session, snapshot)[@"controlInputResult"][@"accepted"] boolValue], "disabling a button before native dispatch prevents its handler");
    [window close]; Pump();
}
static CALayer *MessageLayer(CALayer *form, NSString *name, NSRect frame, NSArray<NSString *> *texts) {
    CALayer *layer = [CALayer layer];
    layer.name = name; layer.frame = frame;
    [form addSublayer:layer];
    if (texts) AXBDrawnTextRecordForTesting(layer, texts);
    return layer;
}
static NSArray *MessageChildren(NSView *form) {
    for (NSView *view in form.subviews) if (![view isKindOfClass:AXBWindowView.class] && view.accessibilityChildren.count) return view.accessibilityChildren;
    return @[];
}
static id MessageElement(NSView *form, NSString *name) {
    for (id element in MessageChildren(form)) if ([[element accessibilityIdentifier] isEqual:[@"axb/message/" stringByAppendingString:name]]) return element;
    return nil;
}
static void MessageDialogsTest(void) {
    // A standard 4D message is an internal form whose objects are named layers.
    AXBMessagesEnableForTesting();
    NSWindow *window = Window(@"AXB standard message");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSView *form = [[NSView alloc] initWithFrame:window.contentView.bounds];
    form.wantsLayer = YES;
    [window.contentView addSubview:form];
    CALayer *context = [CALayer layer]; context.name = @"formContext"; context.frame = form.layer.bounds;
    [form.layer addSublayer:context];
    MessageLayer(context, @"main", NSMakeRect(20, 100, 360, 40), @[@"Delete the selected order?"]);
    MessageLayer(context, @"comment", NSMakeRect(20, 60, 360, 30), nil);
    CALayer *cancel = MessageLayer(context, @"cancel", NSMakeRect(200, 10, 80, 30), @[@"Keep"]);
    CALayer *ok = MessageLayer(context, @"ok", NSMakeRect(290, 10, 90, 30), @[@"Delete"]);
    MessageLayer(context, @"icon", NSMakeRect(10, 100, 40, 40), nil);
    Check(AXBMessagesRefreshWindow(window), "a window whose form objects are standard message layers is published");
    NSArray *children = MessageChildren(form);
    Check(children.count == 3, "message text and both buttons are published; empty and decorative layers are not");
    id main = MessageElement(form, @"main"), keep = MessageElement(form, @"cancel"), remove = MessageElement(form, @"ok");
    Check([[main accessibilityRole] isEqual:NSAccessibilityStaticTextRole] && [[main accessibilityValue] isEqual:@"Delete the selected order?"],
          "the message is static text with its drawn value");
    Check([[keep accessibilityRole] isEqual:NSAccessibilityButtonRole] && [[keep accessibilityLabel] isEqual:@"Keep"] &&
          [[remove accessibilityLabel] isEqual:@"Delete"] && [children indexOfObject:keep] < [children indexOfObject:remove],
          "buttons carry their drawn titles in reading order");
    Check(NSApp.accessibilityApplicationFocusedUIElement == remove, "focus starts on the default button");
    NSRect frame = [remove accessibilityFrame];
    NSPoint expected = [window convertPointFromScreen:NSMakePoint(NSMidX(frame), NSMidY(frame))];
    Check([remove accessibilityPerformPress], "a button press is accepted");
    // 4D discards input queued before its modal loop starts; a press right after publication waits.
    Check([NSApp nextEventMatchingMask:NSEventMaskLeftMouseDown untilDate:[NSDate dateWithTimeIntervalSinceNow:0.2] inMode:NSDefaultRunLoopMode dequeue:NO] == nil,
          "a press right after the window is published is held until it settles");
    NSEvent *down = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDown untilDate:[NSDate dateWithTimeIntervalSinceNow:1] inMode:NSDefaultRunLoopMode dequeue:YES];
    NSEvent *up = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:[NSDate dateWithTimeIntervalSinceNow:1] inMode:NSDefaultRunLoopMode dequeue:YES];
    Check(down && up && down.window == window && fabs(down.locationInWindow.x - expected.x) < 2 && fabs(down.locationInWindow.y - expected.y) < 2,
          "the press is an ordinary click at the button's center");
    Check(![main accessibilityPerformPress] && ![main isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)], "message text is not actionable");
    AXBDrawnTextRecordForTesting(ok, @[@"Remove"]);
    AXBMessagesRefreshWindow(window);
    Check([[MessageElement(form, @"ok") accessibilityLabel] isEqual:@"Remove"], "redrawn text updates the published title");
    cancel.hidden = YES;
    AXBMessagesRefreshWindow(window);
    Check(!MessageElement(form, @"cancel"), "a hidden button leaves the tree");
    CALayer *box = MessageLayer(context, @"box", NSMakeRect(20, 50, 360, 24), @[@"Default"]);
    AXBMessagesRefreshWindow(window);
    id field = MessageElement(form, @"box");
    Check([[field accessibilityRole] isEqual:NSAccessibilityTextFieldRole] && [[field accessibilityValue] isEqual:@"Default"] &&
          [field isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)], "a Request field is an editable text field");
    Check(NSApp.accessibilityApplicationFocusedUIElement == field, "a Request field drawn after the buttons takes the initial focus");
    Check(NSEqualRanges([field accessibilitySelectedTextRange], NSMakeRange(0, 7)), "the Request answer starts selected, as 4D shows it");
    TextEdits = [NSMutableArray new];
    AXBDrawnTextRecordForTesting(box, @[@"L"]);
    AXBMessagesRefreshWindow(window);
    AXBDrawnTextRecordForTesting(box, @[@"La"]);
    AXBMessagesRefreshWindow(window);
    NSDictionary *first = TextEdits.firstObject[@"info"], *second = TextEdits.lastObject[@"info"];
    Check(TextEdits.count == 2 && TextEdits.firstObject[@"element"] == field && [first[@"AXTextStateChangeType"] isEqual:@1] &&
          [first[@"AXTextChangeValues"] isEqual:(@[@{@"AXTextEditType": @1, @"AXTextChangeValue": @"Default"}, @{@"AXTextEditType": @3, @"AXTextChangeValue": @"L"}])],
          "replacing the selected answer is announced as its removal and the typed character");
    Check([second[@"AXTextChangeValues"] isEqual:(@[@{@"AXTextEditType": @3, @"AXTextChangeValue": @"a"}])] &&
          NSEqualRanges([field accessibilitySelectedTextRange], NSMakeRange(2, 0)) && [field accessibilityNumberOfCharacters] == 2,
          "each typed character is announced and the caret follows it");
    AXBDrawnTextRecordForTesting(box, @[@"L"]);
    AXBMessagesRefreshWindow(window);
    Check([TextEdits.lastObject[@"info"][@"AXTextChangeValues"] isEqual:(@[@{@"AXTextEditType": @1, @"AXTextChangeValue": @"a"}])] &&
          NSEqualRanges([field accessibilitySelectedTextRange], NSMakeRange(1, 0)), "a deletion is announced with the removed text");
    [box removeFromSuperlayer];
    box = MessageLayer(context, @"box", NSMakeRect(20, 50, 360, 24), @[@"Lo"]);
    AXBMessagesRefreshWindow(window);
    Check(MessageElement(form, @"box") == field && [[field accessibilityValue] isEqual:@"Lo"] &&
          [TextEdits.lastObject[@"info"][@"AXTextChangeValues"] isEqual:(@[@{@"AXTextEditType": @3, @"AXTextChangeValue": @"o"}])],
          "a replaced field layer keeps its element, so focus and typing echo continue");
    AXBDrawnTextRecordForTesting(box, nil);
    AXBMessagesRefreshWindow(window);
    Check(MessageElement(form, @"box") == field && [[field accessibilityValue] isEqual:@""] &&
          [TextEdits.lastObject[@"info"][@"AXTextChangeValues"] isEqual:(@[@{@"AXTextEditType": @1, @"AXTextChangeValue": @"Lo"}])],
          "deleting the whole answer leaves an empty, still-published field");
    TextEdits = nil;
    MessageLayer(context, @"customButton", NSMakeRect(20, 10, 80, 30), @[@"Other"]);
    Check(!AXBMessagesRefreshWindow(window) && MessageChildren(form).count == 0, "any other object name leaves the window untouched");
    Check(NSApp.accessibilityApplicationFocusedUIElement != field, "an unpublished message window releases the application focus");
    [window close]; Pump();
    // An empty default answer is still an editable field, and closing returns focus to AppKit.
    NSWindow *request = Window(@"AXB standard request");
    [request makeKeyAndOrderFront:nil]; Pump();
    NSView *requestForm = [[NSView alloc] initWithFrame:request.contentView.bounds];
    requestForm.wantsLayer = YES;
    [request.contentView addSubview:requestForm];
    CALayer *requestContext = [CALayer layer]; requestContext.name = @"formContext"; requestContext.frame = requestForm.layer.bounds;
    [requestForm.layer addSublayer:requestContext];
    MessageLayer(requestContext, @"main", NSMakeRect(20, 100, 360, 40), @[@"Name?"]);
    MessageLayer(requestContext, @"box", NSMakeRect(20, 60, 360, 24), @[]);
    MessageLayer(requestContext, @"ok", NSMakeRect(290, 10, 90, 30), @[@"OK"]);
    Check(AXBMessagesRefreshWindow(request), "a Request with an empty default answer is published");
    id empty = MessageElement(requestForm, @"box");
    Check(empty && [[empty accessibilityValue] isEqual:@""] && NSApp.accessibilityApplicationFocusedUIElement == empty, "an empty Request field is published and focused");
    [request close]; Pump();
    Check(NSApp.accessibilityApplicationFocusedUIElement != empty, "closing a message window releases its focus override");
    // Text follows an image only while that image lives; a new image at a reused address has none.
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, 4, 4, 8, 16, space, kCGImageAlphaPremultipliedLast);
    uintptr_t freed = 0;
    @autoreleasepool {
        CGImageRef image = CGBitmapContextCreateImage(bitmap);
        AXBDrawnTextRecordImageForTesting(image, @[@"Old"]);
        Check([AXBDrawnTextForImageForTesting(image) isEqual:@[@"Old"]], "drawn text follows its image");
        freed = (uintptr_t)image;
        CGImageRelease(image);
    }
    BOOL clean = YES;
    for (int i = 0; i < 64; i++) {
        CGImageRef image = CGBitmapContextCreateImage(bitmap);
        clean = clean && AXBDrawnTextForImageForTesting(image) == nil;
        BOOL reused = (uintptr_t)image == freed;
        CGImageRelease(image);
        if (reused) break;
    }
    CGContextRelease(bitmap); CGColorSpaceRelease(space);
    Check(clean, "a freed image's text never attaches to a later image");
}
static id ProgressElement(NSView *form, NSString *identifier) {
    for (NSView *view in form.subviews)
        for (id element in view.accessibilityChildren) if ([[element accessibilityIdentifier] isEqual:identifier]) return element;
    return nil;
}
static NSArray *ProgressChildren(NSView *form) {
    for (NSView *view in form.subviews) if (view.accessibilityChildren.count) return view.accessibilityChildren;
    return @[];
}
static CALayer *Child(CALayer *context, NSString *name) {
    for (CALayer *layer in context.sublayers) if ([layer.name isEqual:name]) return layer;
    return nil;
}
// One progress of 4D's Progress component: a subform whose form context holds its objects.
static CALayer *ProgressLayers(CALayer *window, NSRect frame, NSString *title, NSString *message, NSString *value, BOOL stop) {
    CALayer *subform = MessageLayer(window, @"Subform1", frame, nil);
    CALayer *context = [CALayer layer]; context.name = @"formContext"; context.frame = subform.bounds;
    [subform addSublayer:context];
    MessageLayer(context, @"Picture3", NSMakeRect(0, 0, 400, 68), nil);
    MessageLayer(context, @"ThermoProgress", NSMakeRect(56, 20, 333, 23), nil);
    MessageLayer(context, @"Message1", NSMakeRect(50, 23, 355, 48), title ? @[title] : nil);
    MessageLayer(context, @"Message2", NSMakeRect(50, -12, 355, 44), message ? @[message] : nil);
    MessageLayer(context, @"ProgressValue", NSMakeRect(7, -162, 211, 48), @[value]);
    if (stop) MessageLayer(context, @"StopButton", NSMakeRect(366, 22, 28, 28), nil);
    return context;
}
static void ProgressWindowsTest(void) {
    AXBProgressEnableForTesting();
    NSWindow *window = Window(@"AXB progress");
    [window orderFront:nil]; Pump();
    NSView *form = [[NSView alloc] initWithFrame:window.contentView.bounds];
    form.wantsLayer = YES;
    [window.contentView addSubview:form];
    CALayer *context = [CALayer layer]; context.name = @"formContext"; context.frame = form.layer.bounds;
    [form.layer addSublayer:context];
    CALayer *first = ProgressLayers(context, NSMakeRect(0, 100, 400, 68), @"Importing orders", @"Order 3 of 10", @"0.3", YES);
    CALayer *second = ProgressLayers(context, NSMakeRect(0, 32, 400, 68), @"Waiting for server", nil, @"-1", NO);
    Check(AXBProgressRefreshWindow(window), "a window holding Progress component forms is published");
    NSArray *children = ProgressChildren(form);
    id bar = ProgressElement(form, @"axb/progress/1/progress"), message = ProgressElement(form, @"axb/progress/1/message");
    id stop = ProgressElement(form, @"axb/progress/1/stop"), waiting = ProgressElement(form, @"axb/progress/2/progress");
    Check(children.count == 4 && children[0] == bar && children[1] == message && children[2] == stop && children[3] == waiting,
          "each progress is published top to bottom: indicator, message, then Stop; empty messages and absent buttons are not");
    Check([[bar accessibilityRole] isEqual:NSAccessibilityProgressIndicatorRole] && [[bar accessibilityLabel] isEqual:@"Importing orders"] &&
          [[bar accessibilityValue] isEqual:@30] && [[bar accessibilityMinValue] isEqual:@0] && [[bar accessibilityMaxValue] isEqual:@100],
          "the indicator is labelled with the title and reports the stored progress as a percentage");
    Check([[message accessibilityRole] isEqual:NSAccessibilityStaticTextRole] && [[message accessibilityValue] isEqual:@"Order 3 of 10"], "the message is static text");
    Check([[stop accessibilityRole] isEqual:NSAccessibilityButtonRole] && [[stop accessibilityLabel] isEqual:@"Stop"] &&
          [stop isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && ![bar accessibilityPerformPress], "Stop is a button; the indicator is not actionable");
    NSRect barFrame = [bar accessibilityFrame], messageFrame = [message accessibilityFrame];
    Check(NSMaxY(barFrame) > NSMaxY(messageFrame) && NSMinX(barFrame) <= NSMinX(messageFrame),
          "the indicator's frame includes its title, so it reads before the message overlapping its bar");
    Check([[waiting accessibilityLabel] isEqual:@"Waiting for server"] && [waiting accessibilityValue] == nil && [waiting accessibilityMaxValue] == nil,
          "an indeterminate progress has no value");
    NSRect frame = [stop accessibilityFrame];
    NSPoint expected = [window convertPointFromScreen:NSMakePoint(NSMidX(frame), NSMidY(frame))];
    Check([stop accessibilityPerformPress], "a Stop press is accepted");
    NSEvent *down = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDown untilDate:[NSDate dateWithTimeIntervalSinceNow:1] inMode:NSDefaultRunLoopMode dequeue:YES];
    NSEvent *up = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:[NSDate dateWithTimeIntervalSinceNow:1] inMode:NSDefaultRunLoopMode dequeue:YES];
    Check(down && up && down.window == window && fabs(down.locationInWindow.x - expected.x) < 2 && fabs(down.locationInWindow.y - expected.y) < 2,
          "the press is an ordinary click at the Stop button's center");
    Posts = [NSMutableArray new];
    AXBDrawnTextRecordForTesting(Child(first, @"ProgressValue"), @[@"0,75"]);
    AXBDrawnTextRecordForTesting(Child(first, @"Message2"), @[@"Order 8 of 10"]);
    AXBProgressRefreshWindow(window);
    BOOL announced = NO;
    for (NSDictionary *post in Posts) announced |= post[@"element"] == bar && [post[@"notification"] isEqual:NSAccessibilityValueChangedNotification];
    Check([[bar accessibilityValue] isEqual:@75] && [[message accessibilityValue] isEqual:@"Order 8 of 10"] && announced,
          "a redrawn progress, with either decimal separator, updates and announces its value");
    Posts = nil;
    [first.superlayer removeFromSuperlayer];
    AXBProgressRefreshWindow(window);
    Check(ProgressChildren(form).count == 1 && ProgressElement(form, @"axb/progress/1/progress") == waiting &&
          [[waiting accessibilityLabel] isEqual:@"Waiting for server"],
          "a finished progress leaves the tree; the others keep their elements and take its position");
    MessageLayer(context, @"main", NSMakeRect(20, 10, 80, 30), @[@"Other"]);
    [second.superlayer removeFromSuperlayer];
    Check(!AXBProgressRefreshWindow(window) && ProgressChildren(form).count == 0, "a window without progress forms is left untouched");
    [window close]; Pump();
}
static AXBWindowView *BridgeView(NSWindow *window) {
    NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:window.contentView];
    while (pending.count) {
        NSView *view = pending.lastObject; [pending removeLastObject];
        if ([view isKindOfClass:AXBWindowView.class]) return (AXBWindowView *)view;
        [pending addObjectsFromArray:view.subviews];
    }
    return nil;
}
static NSSet<NSString *> *ExposedIDs(NSWindow *window) {
    NSMutableSet *ids = [NSMutableSet new];
    for (AXBNode *node in BridgeView(window).nodes) if (node.isAccessibilityElement) [ids addObject:node.data[@"id"]];
    return ids;
}
static void ParkedControlsTest(void) {
    // 4D forms park shortcut-only buttons, their legends and state fields beyond a fixed window.
    NSWindow *window = Window(@"AXB parked controls");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9032);
    NSDictionary *(^node)(NSString *, NSString *, NSArray *, BOOL) = ^NSDictionary *(NSString *identifier, NSString *role, NSArray *frame, BOOL focused) {
        // Automatically discovered controls are revealable; that does not make a parked control reachable.
        return @{@"id": identifier, @"role": role, @"label": identifier, @"value": @"", @"editable": @([role isEqual:@"textfield"]),
                 @"focusable": @([role isEqual:@"textfield"]), @"focused": @(focused), @"enabled": @YES, @"visible": @YES, @"revealable": @YES, @"frame": frame};
    };
    NSMutableArray *nodes = [@[node(@"inside", @"button", @[@20, @20, @100, @24], NO), node(@"edge", @"button", @[@390, @20, @30, @20], NO),
        node(@"parked", @"button", @[@600, @20, @22, @11], NO), node(@"legend", @"text", @[@630, @20, @150, @11], NO),
        node(@"below", @"textfield", @[@20, @400, @150, @17], NO), node(@"search", @"textfield", @[@600, @60, @2, @12], YES)] mutableCopy];
    // A subform row that scrolled below the window has a longer navigation path and stays readable.
    NSMutableDictionary *row = [node(@"row", @"textfield", @[@20, @420, @150, @17], NO) mutableCopy];
    row[@"navigation"] = @[@100, @20, @320, @0];
    [nodes addObject:row];
    NSSet *all = [NSSet setWithArray:@[@"inside", @"edge", @"parked", @"legend", @"below", @"search", @"row"]];
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Customers", @"enabled": @YES, @"nodes": nodes} mutableCopy];
    Check([Exchange(window, 9032, 1, session, snapshot)[@"ok"] boolValue], "parked-control snapshot accepted"); Pump();
    Check([ExposedIDs(window) isEqual:all], "without the application option every visible control stays exposed");
    snapshot[@"omitOutsideWindow"] = @YES; snapshot[@"revision"] = @2;
    Check([Exchange(window, 9032, 1, session, snapshot)[@"ok"] boolValue], "fixed-window option accepted"); Pump();
    Check([ExposedIDs(window) isEqual:[NSSet setWithArray:@[@"inside", @"edge", @"search", @"row"]]],
          "with the option, root-form controls wholly outside the window are omitted; partly visible, focused and subform controls remain");
    AXBNode *parked = nil;
    for (AXBNode *candidate in BridgeView(window).nodes) if ([candidate.data[@"id"] isEqual:@"parked"]) parked = candidate;
    Check(parked && ![parked accessibilityPerformPress] && ![Provider(window).accessibilityChildren containsObject:parked],
          "a parked button is neither listed nor pressable through accessibility");
    nodes[5] = node(@"search", @"textfield", @[@600, @60, @2, @12], NO); snapshot[@"revision"] = @3;
    Exchange(window, 9032, 1, session, snapshot); Pump();
    Check(![ExposedIDs(window) containsObject:@"search"], "a parked field leaves the tree when it loses focus");
    snapshot[@"omitOutsideWindow"] = @"yes"; snapshot[@"revision"] = @4;
    Check(![Exchange(window, 9032, 1, session, snapshot)[@"ok"] boolValue], "a non-Boolean fixed-window option is rejected");
    [snapshot removeObjectForKey:@"omitOutsideWindow"]; snapshot[@"revision"] = @5;
    Exchange(window, 9032, 1, session, snapshot); Pump();
    Check([ExposedIDs(window) isEqual:all], "removing the option restores every visible control");
    [window close]; Pump();
}
static void FocusAfterLayoutTest(void) {
    // A host mode change can make the focused field editable in the same refresh
    // that replaces it. VoiceOver follows the new focus only when the layout change
    // names it and the focus change follows the layout change.
    NSWindow *window = Window(@"AXB focus after layout");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9031);
    NSMutableDictionary *note = [@{@"id": @"note", @"role": @"textfield", @"label": @"Latest note", @"value": @"Note",
        @"editable": @NO, @"focusable": @YES, @"focused": @YES, @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @200, @60]} mutableCopy];
    NSDictionary *search = @{@"id": @"search", @"role": @"textfield", @"label": @"Quick search", @"value": @"",
        @"editable": @YES, @"focusable": @YES, @"focused": @NO, @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @100, @200, @24]};
    NSMutableDictionary *snapshot = [@{@"version": @1, @"revision": @1, @"label": @"Notes", @"enabled": @YES, @"nodes": @[note, search]} mutableCopy];
    Check([Exchange(window, 9031, 1, session, snapshot)[@"ok"] boolValue], "read-only focused note accepted"); Pump();
    id readOnly = NSApp.accessibilityApplicationFocusedUIElement;
    Check([[readOnly accessibilityIdentifier] hasSuffix:@"/note"] && ![readOnly isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)],
          "the read-only note owns application focus before the mode change");
    Posts = [NSMutableArray new];
    note[@"editable"] = @YES; snapshot[@"revision"] = @2;
    Check([Exchange(window, 9031, 1, session, snapshot)[@"ok"] boolValue], "editable note accepted"); Pump();
    id editable = NSApp.accessibilityApplicationFocusedUIElement;
    NSArray *posts = Posts; Posts = nil;
    NSUInteger focus = [posts indexOfObjectPassingTest:^BOOL(NSDictionary *post, NSUInteger, BOOL *) {
        return [post[@"notification"] isEqual:NSAccessibilityFocusedUIElementChangedNotification] && post[@"element"] == editable; }];
    NSUInteger layout = [posts indexOfObjectPassingTest:^BOOL(NSDictionary *post, NSUInteger, BOOL *) {
        return [post[@"notification"] isEqual:NSAccessibilityLayoutChangedNotification] && post[@"element"] == window; }];
    Check(editable != readOnly && [[editable accessibilityIdentifier] hasSuffix:@"/note"] &&
          [editable isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)], "the replacement editable note owns application focus");
    Check(focus != NSNotFound && layout != NSNotFound, "replacing the focused note posts both focus and layout changes");
    Check(layout < focus, "focus is announced after the layout change that replaced the focused note");
    Check([posts[layout][@"info"][NSAccessibilityUIElementsKey] isEqual:@[editable]], "the layout change names the newly focused note");
    Posts = [NSMutableArray new];
    note[@"value"] = @"Edited"; snapshot[@"revision"] = @3;
    Exchange(window, 9031, 1, session, snapshot); Pump();
    posts = Posts; Posts = nil;
    Check(![posts indexesOfObjectsPassingTest:^BOOL(NSDictionary *post, NSUInteger, BOOL *) {
        return [post[@"notification"] isEqual:NSAccessibilityLayoutChangedNotification] || [post[@"notification"] isEqual:NSAccessibilityFocusedUIElementChangedNotification]; }].count,
          "an ordinary value change moves neither layout nor focus");
    [window close]; Pump();
}
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
    Check(table.owner.actionFeedback[@"control"] == checkbox && [table.owner.actionFeedback[@"id"] isEqual:action[@"id"]], "grid checkbox feedback belongs to its exact live control and request");
    NSDictionary *input = @{@"action": action[@"id"], @"point": @[@21, @44]};
    Exchange(window, 9012, 1, session, snapshot, nil, nil, input); Pump(); Pump();
    if (canvas.presses != 1 || canvas.releases != 1 || canvas.lastPoint.x != 21 || canvas.lastPoint.y != 44)
        fprintf(stderr, "Grid input diagnostic: active=%d key=%d presses=%lu releases=%lu point=%.1f,%.1f\n", NSApp.isActive, window.isKeyWindow, (unsigned long)canvas.presses, (unsigned long)canvas.releases, canvas.lastPoint.x, canvas.lastPoint.y);
    Check(canvas.presses == 1 && canvas.releases == 1 && canvas.lastPoint.x == 21 && canvas.lastPoint.y == 44, "grid control receives exactly one native mouse pair at its checked point");
    Check([Exchange(window, 9012, 1, session, snapshot, nil, nil, input)[@"controlInputResult"][@"accepted"] boolValue], "grid mouse delivery has an exact acknowledgement"); Pump();
    Check(canvas.presses == 1, "grid input replay cannot repeat the native click");
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(table.owner.actionFeedback != nil, "grid checkbox receipt waits for its updated value page");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [cell accessibilityPerformAction:NSAccessibilityScrollToVisibleAction];
#pragma clang diagnostic pop
    NSDictionary *reveal = Exchange(window, 9012, 1, session, snapshot)[@"action"]; Pump();
    Check([reveal[@"operation"] isEqual:@"gridReveal"] && table.owner.actionFeedback != nil,
        "same-cell automatic reveal preserves confirmed checkbox feedback while its page loads");
    Exchange(window, 9012, 1, session, snapshot, @{@"id": reveal[@"id"], @"status": @"completed", @"message": @"revealed"}); Pump();
    Check(table.owner.actionFeedback != nil, "later reveal receipt cannot erase confirmed checkbox feedback");
    value[@"checked"] = @1; value[@"value"] = @"1";
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    Check([[checkbox accessibilityValue] isEqual:@1] && table.owner.actionFeedback == nil, "published checkbox state consumes confirmed feedback once");
    Exchange(window, 9012, 1, session, snapshot, @{@"id": reveal[@"id"], @"status": @"completed", @"message": @"revealed"}, nil, nil, @[page]); Pump();
    Check(table.owner.actionFeedback == nil, "grid checkbox receipt replay cannot repeat feedback");
    Check([checkbox accessibilityPerformPress], "grid checkbox accepts activation before an unrelated selection");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    [table setAccessibilitySelectedRows:@[[table accessibilityRows][0]]];
    NSDictionary *selection = Exchange(window, 9012, 1, session, snapshot)[@"action"]; Pump();
    Check([selection[@"operation"] isEqual:@"gridSelect"] && table.owner.actionFeedback == nil,
        "unrelated selection cancels delayed checkbox feedback");
    Exchange(window, 9012, 1, session, snapshot, @{@"id": selection[@"id"], @"status": @"completed", @"message": @"selected"}); Pump();
    Check([checkbox accessibilityPerformPress], "grid checkbox accepts a separately rejected request");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"rejected", @"message": @"validation rejected"}); Pump();
    Check(table.owner.actionFeedback == nil, "rejected grid activation clears feedback without announcing success");
    Check([checkbox accessibilityPerformPress], "grid checkbox accepts a request whose value arrives late");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    NSMutableDictionary *expired = [table.owner.actionFeedback mutableCopy];
    expired[@"deadline"] = @(NSProcessInfo.processInfo.systemUptime-1); table.owner.actionFeedback = expired;
    value[@"checked"] = @2; value[@"value"] = @"2";
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    Check(table.owner.actionFeedback == nil, "late checkbox value publication cannot keep expired feedback alive");
    Check([checkbox accessibilityPerformPress], "grid checkbox accepts a request before its role retires");
    action = Exchange(window, 9012, 1, session, snapshot)[@"action"];
    value[@"role"] = @"text"; [value removeObjectForKey:@"checked"];
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    (void)[cell accessibilityChildren];
    Exchange(window, 9012, 1, session, snapshot, @{@"id": action[@"id"], @"status": @"completed", @"message": @"confirmed"}); Pump();
    Check(![checkbox isAccessibilityElement] && table.owner.actionFeedback == nil, "retired grid checkbox cannot announce a replacement control's result");
    value[@"role"] = @"checkbox";
    value[@"checked"] = @2; value[@"value"] = @"2";
    value[@"enabled"] = @NO; value[@"editable"] = @NO;
    Exchange(window, 9012, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    checkbox = [cell accessibilityChildren][0];
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
        grid[@"actions"] = @{@"select": @NO, @"edit": @NO, @"reveal": @NO};
        grid[@"order"] = @5; snapshot[@"revision"] = @5;
        Exchange(window, 9021, 1, session, snapshot); Pump();
        Check(![[header accessibilityActionNames] containsObject:NSAccessibilityScrollToVisibleAction], "headers omit reveal when the grid cannot reveal");
        [header accessibilityPerformAction:NSAccessibilityScrollToVisibleAction];
        Check(!Exchange(window, 9021, 1, session, snapshot)[@"action"], "unsupported header reveal never enters the action queue");
    }
#pragma clang diagnostic pop
    headerData[@"visible"] = @NO; grid[@"headerHeight"] = @0; grid[@"order"] = @6; snapshot[@"revision"] = @6;
    Exchange(window, 9021, 1, session, snapshot); Pump();
    Check([[table accessibilityColumnHeaderUIElements] count] == 0 && ![header isAccessibilityElement] && ![header accessibilityPerformPress], "hidden headers retire their actions and relationships");
    [window close]; Pump();
}

static void GridValueNotificationTest(void) {
    NSWindow *window = Window(@"AXB settled grid values");
    NSString *session = Open(window, 9030);
    NSDictionary *grid = @{@"generation": @"settled", @"order": @1, @"rows": @[@"one"],
        @"columns": @[@{@"id": @"label", @"label": @"Label", @"enabled": @YES, @"editable": @NO}],
        @"visible": @[], @"selected": @[], @"frames": @{}, @"layout": @{@"rows": @[@[@20, @28]], @"columns": @[@[@10, @200]]},
        @"actions": @{@"select": @NO, @"reveal": @NO, @"edit": @NO}};
    NSDictionary *snapshot = @{@"version": @1, @"revision": @1, @"label": @"Settled values", @"enabled": @YES,
        @"nodes": @[@{@"id": @"items", @"role": @"table", @"label": @"Items", @"value": @"", @"visible": @YES,
            @"enabled": @YES, @"frame": @[@10, @20, @300, @140], @"grid": grid}]};
    Check([Exchange(window, 9030, 1, session, snapshot)[@"ok"] boolValue], "settled-value fixture publishes"); Pump();
    AXBGridNode *table = Provider(window).accessibilityChildren.firstObject;
    id cell = [table accessibilityCellForColumn:0 row:0];
    Check([[cell accessibilityValue] isEqual:@"Loading"], "settled-value fixture starts with an actual cold cell");
    NSMutableDictionary *value = [@{@"column": @"label", @"value": @"A", @"enabled": @YES, @"editable": @NO} mutableCopy];
    NSDictionary *page = @{@"node": @"items", @"generation": @"settled", @"order": @1, @"row": @0, @"column": @0,
        @"rows": @[@{@"id": @"one", @"cells": @[value]}]};
    Exchange(window, 9030, 1, session, snapshot, nil, nil, nil, @[page]); Pump();
    NSMapTable *pending = [table valueForKey:@"pendingValueNotifications"];
    Check(pending.count == 1 && [[cell accessibilityValue] isEqual:@"A"], "arrival keeps one pending notification while exposing its value immediately");
    value[@"value"] = @"B";
    Exchange(window, 9030, 1, session, snapshot, nil, nil, nil, @[page]);
    [table drainValueNotificationsAtTime:NSProcessInfo.processInfo.systemUptime + 2];
    Check([pending objectForKey:cell] && ![pending objectForKey:cell][@"deadline"], "model arrival ahead of native publication retains a dormant notification");
    Pump(); pending = [table valueForKey:@"pendingValueNotifications"];
    Check([pending objectForKey:cell][@"deadline"] && [[cell accessibilityValue] isEqual:@"B"], "native publication reactivates the latest pending value");
    value[@"value"] = @"A";
    Exchange(window, 9030, 1, session, snapshot, nil, nil, nil, @[page]);
    [table drainValueNotificationsAtTime:NSProcessInfo.processInfo.systemUptime + 2];
    Check([pending objectForKey:cell] && ![pending objectForKey:cell][@"deadline"], "a second model change makes the pending notification dormant");
    value[@"value"] = @"B";
    Exchange(window, 9030, 1, session, snapshot, nil, nil, nil, @[page]);
    Pump(); pending = [table valueForKey:@"pendingValueNotifications"];
    Check([pending objectForKey:cell][@"deadline"] && [[cell accessibilityValue] isEqual:@"B"], "returning to the published value reactivates a dormant notification");
    [table drainValueNotificationsAtTime:NSProcessInfo.processInfo.systemUptime + 2];
    Check(pending.count == 0, "the latest settled value consumes its notification once");
    NSMapTable *dead = [NSMapTable weakToStrongObjectsMapTable];
    __weak NSObject *gone;
    @autoreleasepool {
        NSObject *key = [NSObject new]; gone = key;
        [dead setObject:@{@"deadline": @0} forKey:key];
    }
    Check(!gone, "notification scheduler fixture has a genuinely deallocated weak key");
    [table setValue:dead forKey:@"pendingValueNotifications"];
    [table setValue:@NO forKey:@"valueNotificationScheduled"];
    [table scheduleValueNotifications];
    Check(dead.count == 0 && ![[table valueForKey:@"valueNotificationScheduled"] boolValue], "dead weak keys cannot retain a notification drain or schedule a loop");
    [window close]; Pump();
}

static NSData *PaintCell(NSView *view, NSCell *cell, CGFloat anchorY = 20) {
    NSData *pixels;
    @autoreleasepool {
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide:400 pixelsHigh:100
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        CGContextTranslateCTM(NSGraphicsContext.currentContext.CGContext, 0, anchorY);
        [cell drawWithFrame:NSMakeRect(20, 0, 180, 24) inView:view];
        pixels = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [NSGraphicsContext restoreGraphicsState];
    }
    return pixels;
}
static NSSegmentedCell *TabCell(void) {
    NSSegmentedCell *cell = [NSSegmentedCell new];
    cell.segmentCount = 3;
    [cell setWidth:40 forSegment:0]; [cell setWidth:80 forSegment:1]; [cell setWidth:50 forSegment:2];
    [cell setLabel:@"One" forSegment:0]; [cell setLabel:@"Longer" forSegment:1]; [cell setLabel:@"Last" forSegment:2];
    [cell setSelected:YES forSegment:0];
    return cell;
}
static NSData *PaintTabs(NSView *view) { return PaintCell(view, TabCell()); }
static NSData *PaintPopup(NSView *view) {
    NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
    [cell addItemsWithTitles:@[@"First", @"Last"]];
    [cell selectItemAtIndex:1];
    return PaintCell(view, cell);
}
static NSDictionary *TabLayout(NSWindow *window, NSString *request = @"{\"frame\":[20,20,180,24],\"count\":3}") {
    return [NSJSONSerialization JSONObjectWithData:[AXBReadNativeLayout((__bridge void *)window, request) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}
static void NativeTabLayoutTest(void) {
    NSWindow *window = Window(@"AXB native tab layout");
    IMP original = method_getImplementation(class_getInstanceMethod(NSSegmentedCell.class, @selector(drawWithFrame:inView:)));
    IMP originalPopup = method_getImplementation(class_getInstanceMethod(NSPopUpButtonCell.class, @selector(drawWithFrame:inView:)));
    NSData *baseline = PaintTabs(window.contentView);
    NSData *popupBaseline = PaintPopup(window.contentView);
    AXBLayoutInitialize();
    IMP observed = method_getImplementation(class_getInstanceMethod(NSSegmentedCell.class, @selector(drawWithFrame:inView:)));
    NSData *candidate = PaintTabs(window.contentView);
    Check([baseline isEqual:candidate], "tab observation preserves every rendered pixel");
    Check([TabLayout(window)[@"error"] isEqual:@"inactiveLayoutWindow"], "painting does not register an inactive native window");
    AXBLayoutObserve(window);
    NSDictionary *layout = TabLayout(window);
    Check([layout[@"ok"] boolValue] && [layout[@"segments"] count] == 3, "first paint survives later bridge registration");
    Check([layout[@"segments"][0][@"selected"] boolValue] && ![layout[@"segments"][1][@"selected"] boolValue], "captured native state preserves actual selection");
    Check([layout[@"segments"][1][@"frame"][2] doubleValue] > [layout[@"segments"][0][@"frame"][2] doubleValue], "captured native frames preserve unequal widths");
    NSSegmentedCell *reused = TabCell();
    PaintCell(window.contentView, reused);
    NSUInteger beforeReuse = [TabLayout(window)[@"serial"] unsignedIntegerValue];
    // NSActionCell can remember the canvas it last drew in. That canvas is
    // not an owning NSControl and must not suppress the next capture.
    reused.controlView = window.contentView;
    [reused setSelected:YES forSegment:2];
    PaintCell(window.contentView, reused);
    layout = TabLayout(window);
    Check([layout[@"serial"] unsignedIntegerValue] > beforeReuse && [layout[@"segments"][2][@"selected"] boolValue], "reused canvas cells publish their actual later paint");
    NSUInteger beforeQueued = [layout[@"serial"] unsignedIntegerValue];
    [reused setSelected:YES forSegment:1]; PaintCell(window.contentView, reused);
    [reused setSelected:YES forSegment:2]; PaintCell(window.contentView, reused);
    layout = TabLayout(window);
    Check([layout[@"serial"] unsignedIntegerValue] == beforeQueued+1 && [layout[@"segments"][2][@"selected"] boolValue], "queued paints at one anchor keep only the latest actual state");
    NSPopUpButtonCell *manyPopups = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
    [manyPopups addItemsWithTitles:@[@"Grid choice"]];
    for (NSInteger i = 0; i < 600; ++i) PaintCell(window.contentView, manyPopups, 30+i);
    Check([TabLayout(window)[@"kind"] isEqual:@"tabs"], "popup paint traffic cannot evict a tab strip's geometry");
    NSString *firstOwner = @"{\"frame\":[20,20,180,24],\"count\":3,\"owner\":\"first\"}";
    NSString *secondOwner = @"{\"frame\":[20,20,180,24],\"count\":3,\"owner\":\"second\"}";
    Check([TabLayout(window, firstOwner)[@"ok"] boolValue], "first control claims its actual native layout");
    Check([TabLayout(window, secondOwner)[@"error"] isEqual:@"nativeTabLayoutPending"], "a new control cannot reuse the previous control's paint");
    PaintTabs(window.contentView);
    Check([TabLayout(window, secondOwner)[@"ok"] boolValue], "fresh painting allows the replacement control to claim its geometry");
    Check([TabLayout(window, firstOwner)[@"error"] isEqual:@"nativeTabLayoutPending"], "returning to an earlier control also requires its actual repaint");
    Check([popupBaseline isEqual:PaintPopup(window.contentView)], "popup observation preserves every rendered pixel");
    layout = TabLayout(window);
    Check([layout[@"ok"] boolValue] && [layout[@"kind"] isEqual:@"popup"] && [layout[@"label"] isEqual:@"Last"], "native popup painting replaces the prior segmented presentation");
    PaintTabs(window.contentView);
    Check([TabLayout(window)[@"kind"] isEqual:@"tabs"], "returning native tabs replace the popup layout");
    NSString *restartOwner = @"{\"frame\":[20,20,180,24],\"count\":3,\"owner\":\"beforeRestart\",\"signature\":\"sameLabels\"}";
    NSString *restartedOwner = @"{\"frame\":[20,20,180,24],\"count\":3,\"owner\":\"afterRestart\",\"signature\":\"sameLabels\"}";
    Check([TabLayout(window, restartOwner)[@"ok"] boolValue], "restart fixture claims its painted source");
    Check([TabLayout(window, @"{\"operation\":\"restart\"}")[@"ok"] boolValue], "active window can prepare an intentional registration restart");
    AXBLayoutForget(window);
    Check([TabLayout(window, restartedOwner)[@"error"] isEqual:@"inactiveLayoutWindow"], "prepared restart grants no access before the replacement registration");
    AXBLayoutObserve(window);
    Check([TabLayout(window, @"{\"frame\":[20,20,180,24],\"count\":3,\"owner\":\"changed\",\"signature\":\"newLabels\"}")[@"error"] isEqual:@"nativeTabLayoutPending"], "restart cannot reuse geometry for changed source labels");
    Check([TabLayout(window, @"{\"frame\":[10,20,200,24],\"count\":3,\"owner\":\"changedFrame\",\"signature\":\"sameLabels\"}")[@"error"] isEqual:@"nativeTabLayoutPending"], "restart cannot reuse geometry for changed dimensions at the same anchor");
    Check([TabLayout(window, restartedOwner)[@"ok"] boolValue], "intentional restart reuses unchanged painted geometry without forcing native redraw");
    Check([TabLayout(window, @"{\"frame\":[20,20,180,24],\"count\":3,\"owner\":\"afterRestart\",\"signature\":\"newLabels\"}")[@"error"] isEqual:@"nativeTabLayoutPending"], "source changes on the same owner wait for real painting");
    Check([TabLayout(window, restartOwner)[@"error"] isEqual:@"nativeTabLayoutPending"], "restart transfers a paint claim only once");
    for (NSString *request in @[@"[]", @"{\"frame\":[0,0,0,20],\"count\":3}", @"{\"frame\":[20,20,180,24],\"count\":3.5}", @"{\"frame\":[20,20,180],\"count\":3}",
        @"{\"frame\":[true,20,180,24],\"count\":3}", @"{\"frame\":[20,20,180,24],\"count\":true}"])
        Check([TabLayout(window, request)[@"error"] isEqual:@"invalidLayoutRequest"], "invalid native tab requests fail closed");
    Check([TabLayout(window, @"{\"frame\":[20,60,180,24],\"count\":3}")[@"error"] isEqual:@"nativeTabLayoutPending"], "unpainted geometry is not invented");
    AXBLayoutForget(window);
    Check([TabLayout(window)[@"error"] isEqual:@"inactiveLayoutWindow"], "detached window cannot retain a readable layout");
    AXBLayoutShutdown();
    Check(method_getImplementation(class_getInstanceMethod(NSSegmentedCell.class, @selector(drawWithFrame:inView:))) == original, "shutdown restores the original public drawing method");
    Check(method_getImplementation(class_getInstanceMethod(NSPopUpButtonCell.class, @selector(drawWithFrame:inView:))) == originalPopup, "shutdown restores native popup drawing too");
    AXBLayoutInitialize();
    Check(method_getImplementation(class_getInstanceMethod(NSSegmentedCell.class, @selector(drawWithFrame:inView:))) == observed, "database reopen reuses its drawing observer without stacking wrappers");
    AXBLayoutObserve(window);
    Check([TabLayout(window)[@"error"] isEqual:@"nativeTabLayoutPending"], "database reopen cannot inherit a previous layout");
    PaintTabs(window.contentView);
    Check([TabLayout(window)[@"ok"] boolValue], "new painting works after database reopen");
    NSDictionary *workerRead;
    std::thread reader([&] { @autoreleasepool { workerRead = TabLayout(window); } }); reader.join();
    Check([workerRead[@"error"] isEqual:@"notMainThread"], "worker layout reads reject without touching AppKit windows");
    AXBLayoutForget(window); AXBLayoutObserve(window);
    NSSegmentedControl *native = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(20, 20, 180, 24)];
    NSSegmentedCell *nativeCell = TabCell();
    native.cell = nativeCell; nativeCell.controlView = native;
    PaintCell(window.contentView, nativeCell);
    Check([TabLayout(window)[@"error"] isEqual:@"nativeTabLayoutPending"], "a real AppKit control keeps its native tree without a duplicate captured layout");
    NSView *replacedCanvas = [[NSView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:replacedCanvas];
    PaintTabs(replacedCanvas);
    Check([TabLayout(window)[@"ok"] boolValue], "paint belongs to its live canvas in the registered window");
    [replacedCanvas removeFromSuperview];
    Check([TabLayout(window)[@"error"] isEqual:@"nativeTabLayoutPending"], "a detached canvas cannot supply geometry to its replacement");
    // A second plugin can wrap our drawing observer and keep it after close.
    // Reopening must preserve both observers without collecting twice.
    Method draw = class_getInstanceMethod(NSSegmentedCell.class, @selector(drawWithFrame:inView:));
    Method popup = class_getInstanceMethod(NSPopUpButtonCell.class, @selector(drawWithFrame:inView:));
    IMP chained = method_getImplementation(draw), chainedPopup = method_getImplementation(popup);
    __block NSInteger laterDraws = 0, laterPopups = 0;
    IMP later = imp_implementationWithBlock(^(id cell, NSRect frame, NSView *view) {
        ++laterDraws; ((void (*)(id, SEL, NSRect, NSView *))chained)(cell, @selector(drawWithFrame:inView:), frame, view);
    });
    IMP laterPopup = imp_implementationWithBlock(^(id cell, NSRect frame, NSView *view) {
        ++laterPopups; ((void (*)(id, SEL, NSRect, NSView *))chainedPopup)(cell, @selector(drawWithFrame:inView:), frame, view);
    });
    method_setImplementation(draw, later); method_setImplementation(popup, laterPopup);
    AXBLayoutShutdown();
    Check(method_getImplementation(draw) == later && method_getImplementation(popup) == laterPopup, "closing preserves a later plugin's drawing observers");
    Check([baseline isEqual:PaintTabs(window.contentView)] && [popupBaseline isEqual:PaintPopup(window.contentView)], "inactive chained observers preserve native rendering");
    AXBLayoutInitialize(); AXBLayoutObserve(window);
    NSInteger priorDraws = laterDraws, priorPopups = laterPopups;
    PaintTabs(window.contentView); NSUInteger tabSerial = [TabLayout(window)[@"serial"] unsignedIntegerValue];
    PaintPopup(window.contentView); NSUInteger popupSerial = [TabLayout(window)[@"serial"] unsignedIntegerValue];
    Check(laterDraws == priorDraws+1 && laterPopups == priorPopups+1 && popupSerial == tabSerial+1, "reopen chains other observers once and captures each layout once");
    AXBLayoutShutdown();
    Check(method_getImplementation(draw) == later && method_getImplementation(popup) == laterPopup, "second shutdown preserves the other plugin too");
    method_setImplementation(draw, original); method_setImplementation(popup, originalPopup);
    imp_removeBlock(later); imp_removeBlock(laterPopup);
    [window close]; Pump();
}

static void TabSemanticsTest(void) {
    NSWindow *window = Window(@"AXB tab semantics");
    [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; Pump();
    NSString *session = Open(window, 9030);
    NSDictionary *group = @{@"id": @"tabs", @"role": @"tabgroup", @"label": @"Sections", @"value": @"", @"enabled": @YES,
        @"visible": @YES, @"frame": @[@10, @20, @300, @30]};
    NSDictionary *tab = @{@"id": @"first", @"parent": @"tabs", @"role": @"tab", @"label": @"First", @"value": @YES, @"enabled": @YES,
        @"visible": @YES, @"frame": @[@10, @20, @100, @30]};
    NSDictionary *snapshot = @{@"version": @1, @"revision": @1, @"label": @"Tab semantics", @"enabled": @YES, @"nodes": @[group, tab]};
    Check([Exchange(window, 9030, 1, session, snapshot)[@"ok"] boolValue], "native tab semantics snapshot accepted"); Pump();
    id tabs = Provider(window).accessibilityChildren.firstObject, child = [tabs accessibilityTabs][0];
    Check([[child accessibilityRole] isEqual:NSAccessibilityRadioButtonRole] && [[child accessibilitySubrole] isEqual:NSAccessibilityTabButtonSubrole], "tab uses Apple's radio role and tab-button subrole");
    Check([[tabs accessibilitySelectedChildren] isEqual:@[child]] && [tabs accessibilityValue] == child && [child accessibilityParent] == tabs, "selected tab and containment relationships agree");
    NSMutableDictionary *unselected = [tab mutableCopy]; unselected[@"value"] = @NO;
    NSMutableDictionary *updated = [snapshot mutableCopy]; updated[@"revision"] = @2; updated[@"nodes"] = @[group, unselected];
    Exchange(window, 9030, 1, session, updated); Pump();
    Check([child accessibilityPerformPress], "tab selection queues its original action");
    NSDictionary *action = Exchange(window, 9030, 1, session, updated)[@"action"];
    Exchange(window, 9030, 1, session, updated, @{@"id": action[@"id"], @"status": @"completed", @"message": @"dispatched"}); Pump();
    AXBWindowView *view = ((AXBNode *)child).owner;
    Check(view.actionFeedback != nil, "dispatch acknowledgement keeps tab feedback until selection is published");
    updated[@"revision"] = @3; updated[@"nodes"] = @[group, tab];
    Exchange(window, 9030, 1, session, updated); Pump();
    Check(view.actionFeedback == nil, "published selection consumes exact tab feedback once");
    Exchange(window, 9030, 1, session, updated); Pump();
    Check(view.actionFeedback == nil, "receipt replay does not repeat completed tab feedback");
    updated[@"revision"] = @4; updated[@"nodes"] = @[group, unselected];
    Exchange(window, 9030, 1, session, updated); Pump();
    Check([child accessibilityPerformPress], "vetoed selection can be requested without changing its native value");
    action = Exchange(window, 9030, 1, session, updated)[@"action"];
    Exchange(window, 9030, 1, session, updated, @{@"id": action[@"id"], @"status": @"completed", @"message": @"dispatched"}); Pump();
    NSMutableDictionary *expired = [view.actionFeedback mutableCopy]; expired[@"deadline"] = @0; view.actionFeedback = expired;
    Exchange(window, 9030, 1, session, updated); Pump();
    Check(view.actionFeedback == nil && ![[child accessibilityValue] boolValue], "unchanged tab selection expires without inventing a selected value");
    [window close]; Pump();
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        StableIdentifierTest();
        OutlineSemanticsTest();
        OutlineDisclosureTest();
        SingleSelectionRowTest();
        SplitterTest();
        PicturePopupTest();
        PictureEditTest();
        NativeTabLayoutTest();
        TabSemanticsTest();
        SessionLifetimeTest();
        LogicalFrameTest();
        NavigationOrderTest();
        ProgressAdjustmentTest();
        RefreshDelayTest();
        GridRefreshDelayTest();
        GridControlsTest();
        GridHeaderTest();
        GridValueNotificationTest();
        CheckboxFeedbackTest();
        AdjustableTest();
        ButtonInputTest();
        ButtonMenuTest();
        MessageDialogsTest();
        ProgressWindowsTest();
        FocusAfterLayoutTest();
        ParkedControlsTest();
        SelectionInputTest();
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
        NSWindow *reopenedWindow = Window(@"AXB reopened database");
        Check([OpenResult(reopenedWindow, 103, 1)[@"error"] isEqual:@"plugin stopped"], "shutdown rejects sessions until plugin initialization");
        Check(![inputElement isAccessibilityEnabled], "database close leaves old native elements disabled");
        AXBInitialize();
        NSDictionary *reopened = OpenResult(reopenedWindow, 103, 1);
        Check([reopened[@"ok"] boolValue], "plugin initialization allows the next database to create sessions");
        Check(![reopened[@"session"] isEqual:inputSession], "reopened database receives a new session identity");
        Check([Exchange(reopenedWindow, 103, 1, inputSession, inputSnapshot)[@"ok"] isEqual:@NO], "old database session cannot dispatch in the new database");
        AXBInitialize();
        Check([OpenResult(reopenedWindow, 103, 1)[@"error"] isEqual:@"window already has another session"], "repeated initialization preserves the active session owner");
        // A 4D help tip window: borderless, level 16, ignoring the mouse, its text field as content.
        NSWindow *(^tipWindow)(BOOL) = ^NSWindow *(BOOL text) {
            NSWindow *tip = [[NSWindow alloc] initWithContentRect:NSMakeRect(300, 300, 60, 18) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            tip.releasedWhenClosed = NO; tip.level = 16; tip.ignoresMouseEvents = YES;
            if (text) {
                NSTextField *field = [NSTextField labelWithString:@"Mode"]; field.frame = NSMakeRect(0, 0, 60, 18); tip.contentView = field;
            }
            return tip;
        };
        NSWindow *tip = tipWindow(YES), *other = tipWindow(NO);
        Check(AXBIsHelpTipWindow(tip) && !AXBIsHelpTipWindow(other) && !AXBIsHelpTipWindow(focusCover), "only a help tip's shape is recognized as one");
        [tip orderFrontRegardless]; [other orderFrontRegardless]; [tip update]; [other update]; Pump();
        Check(!tip.isAccessibilityElement && !tip.contentView.isAccessibilityElement && ![NSApp.accessibilityWindows containsObject:tip],
              "a shown help tip leaves the accessibility tree with its text");
        Check(other.isAccessibilityElement, "another borderless window stays accessible");
        [tip close]; [other close]; Pump();
        AXBShutdown();
        [reopenedWindow close]; Pump();
        puts("PASS: native provider lifecycle tests");
    }
}
