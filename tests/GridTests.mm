#import "Grid.h"
#import "Session.h"
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

static NSUInteger checks;
static void Check(BOOL condition, const char *message) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static NSMutableDictionary *Copy(id value) {
    return [NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];
}
static NSDictionary *Descriptor(NSUInteger count) {
    NSMutableArray *rows = [NSMutableArray new], *columns = [NSMutableArray new];
    for (NSUInteger index = 0; index < count; index++) [rows addObject:[NSString stringWithFormat:@"row-%05lu", index]];
    for (NSUInteger index = 0; index < 24; index++) [columns addObject:@{@"id": [NSString stringWithFormat:@"column-%lu", index],
        @"label": [NSString stringWithFormat:@"Column %lu", index + 1], @"enabled": @YES, @"editable": @NO}];
    return @{@"generation": @"grid-a", @"order": @1, @"rows": rows, @"columns": columns, @"visible": @[], @"selected": @[]};
}
static NSDictionary *Page(NSDictionary *request, NSDictionary *descriptor) {
    NSMutableArray *rows = [NSMutableArray new];
    NSUInteger start = [request[@"row"] unsignedIntegerValue], column = [request[@"column"] unsignedIntegerValue];
    for (NSUInteger row = start; row < start + [request[@"rowCount"] unsignedIntegerValue]; row++) {
        NSMutableArray *cells = [NSMutableArray new];
        NSString *key = descriptor[@"rows"][row];
        for (NSUInteger c = column; c < column + [request[@"columnCount"] unsignedIntegerValue]; c++) {
            NSString *columnID = descriptor[@"columns"][c][@"id"];
            [cells addObject:@{@"column": columnID, @"value": [NSString stringWithFormat:@"%@ / %@", key, columnID], @"enabled": @YES, @"editable": @NO}];
        }
        [rows addObject:@{@"id": key, @"cells": cells}];
    }
    NSMutableDictionary *page = [request mutableCopy]; page[@"rows"] = rows;
    return page;
}
static NSDictionary *Snapshot(NSDictionary *descriptor, NSUInteger revision) {
    return @{@"version": @1, @"revision": @(revision), @"label": @"All rows", @"enabled": @YES, @"nodes": @[
        @{@"id": @"grid", @"role": @"table", @"label": @"Items", @"value": @"", @"visible": @YES, @"enabled": @YES, @"frame": @[@0, @0, @400, @300], @"grid": descriptor},
        @{@"id": @"button", @"role": @"button", @"label": @"Close", @"value": @"", @"visible": @YES, @"enabled": @YES, @"frame": @[@0, @310, @100, @30]}]};
}
int main(void) {
    @autoreleasepool {
        NSDictionary *descriptor = Descriptor(50000);
        NSMutableDictionary *headerGrid = Copy(Descriptor(0));
        NSMutableDictionary *header = [@{@"visible": @YES, @"enabled": @YES, @"press": @YES, @"sortable": @YES, @"sort": @"ascending"} mutableCopy];
        headerGrid[@"columns"][0][@"header"] = header;
        headerGrid[@"headers"] = @{@"column-0": @[@0, @0, @120, @24]};
        headerGrid[@"headerHeight"] = @24;
        Check(AXBValidateGrid(headerGrid) == nil, "empty grids retain their actionable sort headers");
        header[@"sort"] = @"guessed";
        Check(AXBValidateGrid(headerGrid) != nil, "header sort direction must be a known displayed state");
        header[@"sort"] = @"ascending";
        header[@"press"] = @1;
        Check(AXBValidateGrid(headerGrid) != nil, "header capabilities require real booleans");
        header[@"press"] = @YES;
        AXBSession *headerSession = [[AXBSession alloc] initWithIdentifier:@"header-test" windowID:20];
        NSDictionary *headerSnapshot = Snapshot(headerGrid, 1);
        Check([[headerSession exchange:@{@"snapshot": headerSnapshot} now:0][@"ok"] boolValue], "empty header snapshot publishes");
        Check([headerSession enqueueNode:@"grid" revision:@1 operation:@"gridHeaderPress" value:@{@"column": @"column-0"} now:0], "sort header activation requires no row or editable cell");
        NSDictionary *headerAction = [headerSession exchange:@{@"snapshot": headerSnapshot} now:0][@"action"];
        Check([headerAction[@"value"][@"expectedHeader"] isEqual:header], "header request captures its displayed state");
        NSDictionary *headerInput = @{@"action": headerAction[@"id"], @"point": @[@60, @12]};
        Check([[headerSession exchange:@{@"snapshot": headerSnapshot, @"controlInput": headerInput} now:0][@"controlInput"] isEqual:headerInput] && [headerSession controlInputNode:headerInput] != nil, "native header click stays inside its own header");
        Check(![headerSession exchange:@{@"snapshot": headerSnapshot, @"controlInput": headerInput} now:0][@"controlInput"], "header activation dispatches once");
        NSMutableDictionary *hiddenHeaderGrid = Copy(headerGrid);
        hiddenHeaderGrid[@"order"] = @2;
        hiddenHeaderGrid[@"columns"][0][@"header"][@"visible"] = @NO;
        Check([[headerSession exchange:@{@"snapshot": Snapshot(hiddenHeaderGrid, 2)} now:0][@"ok"] boolValue] && ![headerSession controlInputNode:headerInput], "hidden header cancels native input before delivery");
        [headerSession invalidate];
        NSMutableDictionary *geometry = Copy(Descriptor(2));
        NSMutableArray *columnExtents = [NSMutableArray new];
        for (NSUInteger column = 0; column < 24; column++) [columnExtents addObject:@[@(column * 120), @120]];
        geometry[@"layout"] = @{@"rows": @[@[@(-2000000), @24], @[@2000000, @37]], @"columns": columnExtents};
        Check(AXBValidateGrid(geometry) == nil, "real offscreen layout supports large coordinates and variable row heights");
        NSMutableDictionary *badGeometry = Copy(geometry);
        [badGeometry[@"layout"][@"rows"] removeLastObject];
        Check(AXBValidateGrid(badGeometry) != nil, "layout must cover every logical row");
        badGeometry = Copy(geometry); badGeometry[@"layout"][@"columns"][0][1] = @0;
        Check(AXBValidateGrid(badGeometry) != nil, "zero-sized logical cells cannot masquerade as navigable layout");
        badGeometry = Copy(geometry); badGeometry[@"layout"][@"rows"][0][0] = @YES;
        Check(AXBValidateGrid(badGeometry) != nil, "layout coordinates reject booleans");
        badGeometry = Copy(geometry); badGeometry[@"layout"][@"rows"][0][0] = @1000000001;
        Check(AXBValidateGrid(badGeometry) != nil, "logical geometry retains a finite size bound");
        AXBSession *session = [[AXBSession alloc] initWithIdentifier:@"grid-test" windowID:1];
        NSDictionary *snapshot = Snapshot(descriptor, 1);
        Check([[session exchange:@{@"snapshot": snapshot} now:0][@"ok"] boolValue], "50,000 logical rows fit independently of the ordinary node budget");
        AXBGrid *grid = [session gridForNode:@"grid"];
        Check(grid.active && [grid.descriptor[@"rows"] count] == 50000 && grid.cachedPageCount == 0, "complete order needs no cell-value allocation");
        Check([grid indexOfRow:@"row-49999"] == 49999 && [grid indexOfColumn:@"column-23"] == 23, "last offscreen row and column remain addressable");
        Check([grid cellForRow:@"row-49999" column:@"column-23" now:1] == nil, "unloaded cell is unknown rather than an empty value");
        (void)[grid cellForRow:@"row-49998" column:@"column-22" now:1];
        (void)[grid cellForRow:@"row-25000" column:@"column-8" now:1];
        (void)[grid cellForRow:@"row-00000" column:@"column-0" now:1];
        Check([session enqueueNode:@"button" revision:@1 operation:@"press" value:nil now:1], "read requests do not occupy action queue");
        NSDictionary *reply = [session exchange:@{@"snapshot": snapshot} now:1];
        NSArray *requests = reply[@"gridRequests"];
        Check(requests.count == 3 && reply[@"action"] != nil, "deduplicated beginning middle and end pages accompany the normal action");
        NSMutableArray *pages = [NSMutableArray new];
        for (NSDictionary *request in requests) [pages addObject:Page(request, descriptor)];
        NSDictionary *receipt = @{@"id": reply[@"action"][@"id"], @"status": @"completed", @"message": @""};
        Check([[session exchange:@{@"snapshot": snapshot, @"gridPages": pages, @"receipt": receipt} now:1.1][@"ok"] boolValue], "page values publish without fabricating a new form revision");
        Check([[grid cellForRow:@"row-49999" column:@"column-23" now:1.2][@"value"] isEqual:@"row-49999 / column-23"], "far cell reads its own stable key and column");
        Check(grid.cachedPageCount == 3 && [grid takeRequestsAtTime:1.2].count == 0, "current pages do not cause redundant requests");
        (void)[grid cellForRow:@"row-49999" column:@"column-23" now:2];
        Check([grid takeRequestsAtTime:2].count == 1, "stale cached values request refresh while remaining readable");

        NSMutableDictionary *invalidPage = Copy(pages[0]);
        invalidPage[@"rows"][0][@"id"] = @"different-record";
        Check(![[session exchange:@{@"snapshot": snapshot, @"gridPages": @[invalidPage]} now:2][@"ok"] boolValue], "wrong row identity rejects a page atomically");
        Check([[grid cellForRow:@"row-49999" column:@"column-23" now:2][@"value"] isEqual:@"row-49999 / column-23"], "rejected page cannot damage the prior cache");
        NSMutableDictionary *changed = Copy(descriptor);
        [changed[@"rows"] exchangeObjectAtIndex:0 withObjectAtIndex:49999];
        Check(![[session exchange:@{@"snapshot": Snapshot(changed, 2)} now:2][@"ok"] boolValue], "reordering requires a new grid order");
        changed[@"order"] = @2;
        Check([[session exchange:@{@"snapshot": Snapshot(changed, 2), @"gridPages": pages} now:2][@"ok"] boolValue], "stale in-flight pages are ignored after a legitimate sort");
        Check([session gridForNode:@"grid"] == grid && [grid indexOfRow:@"row-49999"] == 0 && grid.cachedPageCount == 0, "stable row survives reorder while positional value cache retires");
        changed[@"order"] = @1;
        Check(![[session exchange:@{@"snapshot": Snapshot(changed, 3)} now:3][@"ok"] boolValue], "grid order cannot go backwards");
        changed[@"generation"] = @"replacement";
        Check([[session exchange:@{@"snapshot": Snapshot(changed, 3)} now:3][@"ok"] boolValue], "replacement can start an independent order sequence");
        Check(!grid.active && [grid indexOfRow:@"row-49999"] == NSNotFound, "retained old grid cannot act on replacement data");
        grid = [session gridForNode:@"grid"];
        Check(grid.active && [grid takeRequestsAtTime:3].count == 0, "replacement has an independent request queue");

        // An eager AX client can ask for many cells. Bound work in flight and
        // cache allocation, while preserving access to the complete order.
        for (NSUInteger batch = 0; batch < 40; batch++) {
            NSString *key = changed[@"rows"][batch * 16];
            (void)[grid cellForRow:key column:@"column-0" now:10 + batch];
            for (NSDictionary *request in [grid takeRequestsAtTime:10 + batch]) Check([grid acceptPage:Page(request, changed) now:10 + batch], "requested cache page accepted");
        }
        Check(grid.cachedPageCount == 32 && [grid indexOfRow:@"row-49999"] == 0, "eviction bounds values without dropping logical row identity");
        for (NSUInteger index = 1000; index < 2000; index += 16) (void)[grid cellForRow:changed[@"rows"][index] column:@"column-0" now:100];
        Check([grid takeRequestsAtTime:100].count == 8, "burst reads request at most eight pages");
        for (NSUInteger index = 3000; index < 4000; index += 16) (void)[grid cellForRow:changed[@"rows"][index] column:@"column-0" now:100];
        Check([grid takeRequestsAtTime:100].count == 0, "outstanding requests also count against the work bound");
        (void)[grid cellForRow:changed[@"rows"][3000] column:@"column-0" now:104];
        Check([grid takeRequestsAtTime:104].count == 1, "lost page response can retry after bounded expiry");

        std::vector<std::thread> threads;
        for (NSUInteger n = 0; n < 8; n++) threads.emplace_back([grid, changed, n] {
            @autoreleasepool { for (NSUInteger i = 0; i < 100; i++) (void)[grid cellForRow:changed[@"rows"][n * 100 + i] column:@"column-1" now:200]; }
        });
        for (auto &thread : threads) thread.join();
        Check([grid takeRequestsAtTime:200].count <= 8, "concurrent readers retain the same bounded request queue");
        [session invalidate];
        Check(!grid.active && [grid takeRequestsAtTime:300].count == 0 && [grid cellForRow:@"row-00000" column:@"column-0" now:300] == nil, "session closure retires retained values and requests");

        changed = Copy(Descriptor(19));
        changed[@"actions"] = @{@"select": @YES, @"reveal": @YES, @"edit": @YES};
        changed[@"columns"][0][@"editable"] = @YES;
        session = [[AXBSession alloc] initWithIdentifier:@"grid-actions" windowID:2];
        snapshot = Snapshot(changed, 1);
        Check([[session exchange:@{@"snapshot": snapshot} now:0][@"ok"] boolValue], "grid action capabilities accepted");
        grid = [session gridForNode:@"grid"];
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridEdit" value:@{@"row": @"row-00000", @"column": @"column-0"} now:1], "uncached edit capability cannot authorize entry");
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridReveal" value:@{@"row": @"missing", @"column": @"column-0"} now:1], "unknown row cannot be revealed");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridReveal" value:@{@"row": @"row-00018", @"column": @"column-23"} now:1], "real reveal may target an uncached offscreen cell");
        reply = [session exchange:@{@"snapshot": snapshot} now:1];
        receipt = @{@"id": reply[@"action"][@"id"], @"status": @"completed", @"message": @""};
        Check([[session exchange:@{@"snapshot": snapshot, @"receipt": receipt} now:1.1][@"ok"] boolValue], "reveal still requires the provider's completion receipt");
        requests = [grid takeRequestsAtTime:1.1];
        // The attempted edit already requested this page; it may have been
        // handed to the provider with the reveal reply.
        NSDictionary *request = requests.count ? requests[0] : reply[@"gridRequests"][0];
        NSMutableDictionary *editablePage = Copy(Page(request, changed));
        editablePage[@"rows"][0][@"cells"][0][@"editable"] = @YES;
        Check([[session exchange:@{@"snapshot": snapshot, @"gridPages": @[editablePage]} now:1.2][@"ok"] boolValue], "live provider publishes an editable cell");
        NSMutableDictionary *edit = [@{@"row": @"row-00000", @"column": @"column-0", @"text": @"New value"} mutableCopy];
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridSetValue" value:edit now:1.3], "known enterable cell accepts real-editor request");
        edit[@"text"] = @"Changed behind queue";
        reply = [session exchange:@{@"snapshot": snapshot} now:1.4];
        Check([reply[@"action"][@"value"][@"text"] isEqual:@"New value"] && [reply[@"action"][@"value"][@"expectedValue"] isEqual:@"row-00000 / column-0"], "queued edit owns immutable text and supplies live-value precondition");
        receipt = @{@"id": reply[@"action"][@"id"], @"status": @"rejected", @"message": @"Existing validation rejected entry"};
        Check([[session exchange:@{@"snapshot": snapshot, @"receipt": receipt} now:1.5][@"ok"] boolValue], "existing validation can reject an accepted editor request");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridEdit" value:edit now:1.6], "new cell editor action can queue after rejection");
        editablePage[@"rows"][0][@"cells"][0][@"value"] = @"Updated by another UI event";
        reply = [session exchange:@{@"snapshot": snapshot, @"gridPages": @[editablePage]} now:1.7];
        Check(reply[@"action"] == nil && [reply[@"result"][@"status"] isEqual:@"rejected"], "changed cached cell rejects an edit before dispatch");
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridSelect" value:@[@"row-00000", @"row-00000"] now:2], "logical selection rejects duplicate identities");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridSelect" value:@[@"row-00018"] now:2], "selection is not limited to the viewport");
        [session invalidate];

        // Typed controls never accept text-editor operations, and a retained
        // checkbox state cannot toggle a value changed before dispatch.
        NSMutableDictionary *widgetPage = Copy(editablePage);
        NSMutableDictionary *widget = widgetPage[@"rows"][0][@"cells"][0];
        widget[@"role"] = @"checkbox"; widget[@"checked"] = @2; widget[@"label"] = @"Approved";
        Check(AXBValidateGridPage(widgetPage) == nil, "mixed checkbox page accepts a typed state");
        for (id invalid in @[@YES, @(-1), @3, @0.5, @"1", NSNull.null]) {
            widget[@"checked"] = invalid;
            Check(AXBValidateGridPage(widgetPage) != nil, "checkbox state rejects nonintegral and out-of-range data");
        }
        widget[@"checked"] = @2;
        session = [[AXBSession alloc] initWithIdentifier:@"grid-widgets" windowID:9];
        NSMutableDictionary *widgetGeometry = Copy(changed);
        widgetGeometry[@"visible"] = @[@"row-00000"];
        widgetGeometry[@"frames"] = @{@"row-00000": @{@"column-0": @[@10, @20, @100, @28]}};
        snapshot = Snapshot(widgetGeometry, 1);
        Check([[session exchange:@{@"snapshot": snapshot, @"gridPages": @[widgetPage]} now:0][@"ok"] boolValue], "typed checkbox enters the live cache");
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridSetValue" value:edit now:0.1], "checkbox rejects string assignment through the text editor");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridPress" value:edit now:0.1], "checkbox accepts its native activation");
        reply = [session exchange:@{@"snapshot": snapshot} now:0.2];
        Check([reply[@"action"][@"value"][@"expectedCell"][@"checked"] isEqual:@2], "checkbox action carries its exact observed state");
        NSString *widgetAction = reply[@"action"][@"id"];
        for (id point in @[@[@YES, @30], @[@20], @[@20, NSNull.null], @"20,30"])
            Check(AXBValidateEnvelope(@{@"snapshot": snapshot, @"controlInput": @{@"action": widgetAction, @"point": point}}) != nil, "native grid point rejects malformed coordinates");
        Check(![[session exchange:@{@"snapshot": snapshot, @"controlInput": @{@"action": widgetAction}} now:0.2][@"ok"] boolValue], "grid activation requires its own cell point");
        NSDictionary *outsideInput = @{@"action": widgetAction, @"point": @[@110, @30]};
        Check([[session exchange:@{@"snapshot": snapshot, @"controlInput": outsideInput} now:0.2][@"ok"] boolValue] && ![session controlInputNode:outsideInput], "a point outside its clipped cell rejects input without disabling the session");
        [session finishControlInput:outsideInput accepted:NO];
        Check(![[session exchange:@{@"snapshot": snapshot} now:0.2][@"controlInputResult"][@"accepted"] boolValue], "out-of-bounds native input has an explicit failed acknowledgement");
        [session exchange:@{@"snapshot": snapshot, @"receipt": @{@"id": widgetAction, @"status": @"rejected", @"message": @"moved"}} now:0.2];
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridPress" value:edit now:0.2], "a rejected point leaves subsequent actions available");
        reply = [session exchange:@{@"snapshot": snapshot} now:0.2]; widgetAction = reply[@"action"][@"id"];
        NSDictionary *widgetInput = @{@"action": widgetAction, @"point": @[@21, @34]};
        NSDictionary *widgetEnvelope = @{@"snapshot": snapshot, @"controlInput": widgetInput};
        Check([[session exchange:widgetEnvelope now:0.2][@"controlInput"] isEqual:widgetInput], "grid activation requests a single native click");
        Check([session controlInputNode:widgetInput][@"target"] != nil, "native click identifies its exact live grid cell");
        Check(![session exchange:widgetEnvelope now:0.2][@"controlInput"], "grid input replay cannot duplicate activation");
        Check(![[session exchange:@{@"snapshot": snapshot, @"controlInput": @{@"action": widgetAction, @"point": @[@22, @34]}} now:0.2][@"ok"] boolValue], "input replay cannot move its click to another point");
        [session finishControlInput:widgetInput accepted:YES];
        Check([[session exchange:widgetEnvelope now:0.2][@"controlInputResult"][@"accepted"] boolValue] && ![session controlInputNode:widgetInput], "native completion acknowledges once and prevents reinjection");
        receipt = @{@"id": reply[@"action"][@"id"], @"status": @"completed", @"message": @"changed"};
        (void)[session exchange:@{@"snapshot": snapshot, @"receipt": receipt} now:0.3];
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridPress" value:edit now:0.4], "second checkbox request queues independently");
        widget[@"checked"] = @1;
        reply = [session exchange:@{@"snapshot": snapshot, @"gridPages": @[widgetPage]} now:0.5];
        Check(!reply[@"action"] && [reply[@"result"][@"status"] isEqual:@"rejected"], "changed checkbox state rejects an undelivered toggle");
        widget[@"role"] = @"popup";
        Check(AXBValidateGridPage(widgetPage) != nil, "popup cannot carry a checkbox state");
        [widget removeObjectForKey:@"checked"];
        Check([[session exchange:@{@"snapshot": snapshot, @"gridPages": @[widgetPage]} now:0.6][@"ok"] boolValue], "popup typed page publishes");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridEdit" value:edit now:0.7], "popup can receive focus without a text selection");
        [session invalidate];
        session = [[AXBSession alloc] initWithIdentifier:@"grid-widget-race" windowID:10];
        [session exchange:@{@"snapshot": snapshot, @"gridPages": @[widgetPage]} now:0];
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridPress" value:edit now:0.1], "popup can request guarded native input");
        widgetAction = [session exchange:@{@"snapshot": snapshot} now:0.2][@"action"][@"id"];
        widgetInput = @{@"action": widgetAction, @"point": @[@50, @34]};
        [session exchange:@{@"snapshot": snapshot, @"controlInput": widgetInput} now:0.2];
        widget[@"value"] = @"Changed before the mouse event";
        [session exchange:@{@"snapshot": snapshot, @"gridPages": @[widgetPage]} now:0.3];
        Check(![session controlInputNode:widgetInput], "cell value changes after host dispatch still cancel native input");
        [session invalidate];
        session = [[AXBSession alloc] initWithIdentifier:@"grid-widget-tracking" windowID:11];
        [session exchange:@{@"snapshot": snapshot, @"gridPages": @[widgetPage]} now:0];
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridPress" value:edit now:0.1], "popup tracking fixture queues activation");
        widgetAction = [session exchange:@{@"snapshot": snapshot} now:0.2][@"action"][@"id"];
        widgetInput = @{@"action": widgetAction, @"point": @[@50, @34]};
        [session exchange:@{@"snapshot": snapshot, @"controlInput": widgetInput} now:0.2];
        [session noteMenuForControlInput:@"unrelated"];
        Check(![session exchange:@{@"snapshot": snapshot} now:0.3][@"controlInputResult"], "an unrelated menu cannot acknowledge pending input");
        [session noteMenuForControlInput:widgetAction];
        reply = [session exchange:@{@"snapshot": snapshot} now:5];
        Check([reply[@"controlInputResult"][@"accepted"] boolValue] && [reply[@"controlInputResult"][@"menuOpened"] boolValue], "verified menu opening is acknowledged while mouse tracking is still active");
        [session finishControlInput:widgetInput accepted:NO];
        Check([[session exchange:@{@"snapshot": snapshot} now:6][@"controlInputResult"] isEqual:reply[@"controlInputResult"]], "a later tracking return cannot overwrite the observed menu opening");
        [session invalidate];
        widget[@"role"] = @"unsupported";
        Check(AXBValidateGridPage(widgetPage) != nil, "unknown cell role cannot silently become a text editor");

        // Selection and editing are independent native row capabilities.
        NSMutableDictionary *rowStates = Copy(changed);
        rowStates[@"unselectable"] = @[@"row-00000"];
        rowStates[@"uneditable"] = @[];
        Check(AXBValidateGrid(rowStates) == nil, "independent row editing capability validates");
        Check(AXBGridRowAllowsEditing(rowStates, @"row-00000"), "unselectable row permits an explicitly available editor");
        session = [[AXBSession alloc] initWithIdentifier:@"row-states" windowID:8];
        snapshot = Snapshot(rowStates, 1);
        Check([[session exchange:@{@"snapshot": snapshot, @"gridPages": @[editablePage]} now:0][@"ok"] boolValue], "row capability fixture publishes");
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridSelect" value:@[@"row-00000"] now:0.1], "unselectable row cannot be highlighted");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridSetValue" value:@{@"row": @"row-00000", @"column": @"column-0", @"text": @"Allowed"} now:0.2], "same unselectable row can accept a real editor request");
        rowStates[@"uneditable"] = @[@"row-00000"];
        reply = [session exchange:@{@"snapshot": Snapshot(rowStates, 2)} now:0.3];
        Check(reply[@"action"] == nil && [reply[@"result"][@"status"] isEqual:@"rejected"], "row becoming noneditable cancels queued input before dispatch");
        Check(![session enqueueNode:@"grid" revision:@2 operation:@"gridEdit" value:edit now:0.4], "noneditable row rejects a new editor request");
        [session invalidate];
        rowStates[@"uneditable"] = @[]; rowStates[@"disabled"] = @[@"row-00000"];
        Check(!AXBGridRowAllowsEditing(rowStates, @"row-00000"), "disabled row always blocks editing");
        [rowStates removeObjectForKey:@"disabled"]; [rowStates removeObjectForKey:@"uneditable"];
        Check(!AXBGridRowAllowsEditing(rowStates, @"row-00000"), "legacy providers retain their existing nonselectable editor guard");
        rowStates[@"uneditable"] = @[@"row-00000"];
        rowStates[@"unselectable"] = @[]; rowStates[@"disabled"] = @[@"row-00000"];
        Check(AXBGridRowAllowsSelection(rowStates, @"row-00000"), "native disabled row remains selectable independently of its cells");
        rowStates[@"unselectable"] = @[@"row-00000"];
        Check(!AXBGridRowAllowsSelection(rowStates, @"row-00000"), "native unselectable flag independently prevents new selection");
        rowStates[@"selected"] = @[@"row-00000"];
        session = [[AXBSession alloc] initWithIdentifier:@"retained-restricted-selection" windowID:9];
        Check([[session exchange:@{@"snapshot": Snapshot(rowStates, 1)} now:0][@"ok"] boolValue], "already selected restricted row publishes");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridSelect" value:@[@"row-00000", @"row-00001"] now:0.1], "multi-selection can retain a restricted row while adding another");
        [session invalidate];
        rowStates[@"uneditable"] = @[@"unknown"];
        Check(AXBValidateGrid(rowStates) != nil, "row capability cannot name an absent row");

        session = [[AXBSession alloc] initWithIdentifier:@"grid-unicode" windowID:3];
        snapshot = Snapshot(changed, 1);
        (void)[session exchange:@{@"snapshot": snapshot, @"gridPages": @[editablePage]} now:0];
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridSetValue" value:@{@"row": @"row-00000", @"column": @"column-0", @"text": @"A🎸"} now:0.1], "grid Unicode uses the same real-editor action");
        reply = [session exchange:@{@"snapshot": snapshot} now:0.2];
        NSDictionary *input = @{@"action": reply[@"action"][@"id"], @"serial": @2, @"text": @"🎸"};
        Check(![session canPostEditorInput:input], "grid keyboard input requires actual cell focus");
        changed[@"focused"] = @{@"row": @"row-00000", @"column": @"column-0"};
        snapshot = Snapshot(changed, 2);
        Check([[session exchange:@{@"snapshot": snapshot, @"editorInput": input} now:0.3][@"editorInput"] isEqual:input], "focused grid accepts a complete supplementary character at its exact text position");
        NSMutableDictionary *wrong = Copy(changed);
        wrong[@"focused"][@"row"] = @"row-00001";
        Check(![[session exchange:@{@"snapshot": Snapshot(wrong, 3), @"editorInput": input} now:0.4][@"ok"] boolValue], "moving to another grid row prevents late Unicode input");
        wrong = Copy(changed); wrong[@"uneditable"] = @[@"row-00000"];
        Check(![[session exchange:@{@"snapshot": Snapshot(wrong, 3), @"editorInput": input} now:0.4][@"ok"] boolValue], "row restriction added after editor dispatch rejects delayed Unicode input");
        wrong = Copy(changed); wrong[@"generation"] = @"replacement";
        Check(![[session exchange:@{@"snapshot": Snapshot(wrong, 3), @"editorInput": input} now:0.4][@"ok"] boolValue], "rebound grid cannot receive an old editor event with reused row keys");
        Check(![session canPostEditorInput:@{@"action": input[@"action"], @"serial": @1, @"text": @"🎸"}], "character found elsewhere in requested text cannot authorize the wrong position");
        [session invalidate];

        // Undo/Redo updates the live editor before the background page cache.
        // A cache refresh must preserve actions on the unchanged editor, while
        // still rejecting newly restricted cells and changed editor contents.
        for (NSString *transition in @[@"value", @"permission", @"editor"]) {
            session = [[AXBSession alloc] initWithIdentifier:@"grid-editor-cache" windowID:4];
            changed[@"focused"] = @{@"row": @"row-00000", @"column": @"column-0", @"value": @"A🎸B", @"selection": @[@1, @2]};
            snapshot = Snapshot(changed, 1);
            (void)[session exchange:@{@"snapshot": snapshot, @"gridPages": @[editablePage]} now:0];
            Check([session enqueueNode:@"grid" revision:@1 operation:@"gridSetSelection" value:@{@"row": @"row-00000", @"column": @"column-0", @"selection": @[@0, @1]} now:0.1], "live editor selection queues before a cell cache refresh");
            NSMutableDictionary *refreshed = Copy(editablePage);
            refreshed[@"rows"][0][@"cells"][0][@"value"] = @"Refreshed backing value";
            if ([transition isEqual:@"permission"]) refreshed[@"rows"][0][@"cells"][0][@"editable"] = @NO;
            wrong = Copy(changed);
            if ([transition isEqual:@"editor"]) wrong[@"focused"][@"value"] = @"B🎸B";
            reply = [session exchange:@{@"snapshot": Snapshot(wrong, 2), @"gridPages": @[refreshed]} now:0.2];
            Check((reply[@"action"] != nil) == [transition isEqual:@"value"], "backing cache text may refresh only when the exact editor and editing permissions remain unchanged");
            [session invalidate];
        }

        session = [[AXBSession alloc] initWithIdentifier:@"grid-selection" windowID:4];
        changed[@"focused"] = @{@"row": @"row-00000", @"column": @"column-0", @"value": @"A🎸B", @"selection": @[@1, @2]};
        snapshot = Snapshot(changed, 1);
        Check([[session exchange:@{@"snapshot": snapshot, @"gridPages": @[editablePage]} now:0][@"ok"] boolValue], "live grid editor publishes UTF-16 text and selection");
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridSetSelection" value:@{@"row": @"row-00000", @"column": @"column-0", @"selection": @[@2, @0]} now:0.1], "grid selection cannot split a surrogate pair");
        Check(![session enqueueNode:@"grid" revision:@1 operation:@"gridReplaceSelection" value:@{@"row": @"row-00001", @"column": @"column-0", @"text": @"x"} now:0.1], "partial replacement cannot target another row's editor");
        Check([session enqueueNode:@"grid" revision:@1 operation:@"gridReplaceSelection" value:@{@"row": @"row-00000", @"column": @"column-0", @"text": @"🎹"} now:0.1], "focused editor accepts Unicode selection replacement");
        reply = [session exchange:@{@"snapshot": snapshot} now:0.2];
        Check([reply[@"action"][@"value"][@"expectedValue"] isEqual:@"A🎸B"] && [reply[@"action"][@"value"][@"expectedEditor"][@"selection"] isEqual:@[@1, @2]], "partial replacement guards live text and selection rather than committed data");
        input = @{@"action": reply[@"action"][@"id"], @"serial": @1, @"text": @"🎹"};
        Check([session canPostEditorInput:input], "selection replacement authorizes its exact supplementary character");
        [session invalidate];

        for (id value in @[NSNull.null, @"bad", @1, @YES, @[], @{}]) {
            Check(AXBValidateGrid(value) != nil && AXBValidateGridPage(value) != nil, "malformed model or page shape rejects");
            for (NSString *field in @[@"generation", @"order", @"rows", @"columns", @"selected", @"visible"]) {
                NSMutableDictionary *bad = Copy(Descriptor(2)); bad[field] = value; (void)AXBValidateGrid(bad);
            }
        }
        printf("PASS: %lu logical-grid checks, 50,000 rows, 24 columns, concurrent readers\n", checks);
    }
}
