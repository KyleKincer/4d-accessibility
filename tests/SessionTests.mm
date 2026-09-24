#import "Session.h"
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

static int checks;
static void Check(BOOL condition, const char *description) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", description); exit(1); }
}
static NSDictionary *Envelope(NSInteger revision, BOOL enabled = YES) {
    return @{@"snapshot": @{@"version": @1, @"revision": @(revision), @"label": @"Fixture", @"enabled": @(enabled), @"nodes": @[
        @{@"id": @"button", @"role": @"button", @"label": @"Submit", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @20, @120, @30]},
        @{@"id": @"field", @"role": @"textfield", @"label": @"Name", @"value": @"QA", @"enabled": @YES, @"visible": @YES, @"frame": @[@10, @60, @120, @30]}
    ]}};
}
static BOOL Press(AXBSession *session, NSInteger revision, NSTimeInterval now = 1) {
    return [session enqueueNode:@"button" revision:@(revision) operation:@"press" value:nil now:now];
}
static AXBSession *Fresh(void) {
    AXBSession *session = [[AXBSession alloc] initWithIdentifier:@"fixture" windowID:1];
    Check([[session exchange:Envelope(1) now:0][@"ok"] boolValue], "initial snapshot accepted");
    return session;
}
static NSMutableDictionary *MutableCopy(id object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingMutableContainers error:nil];
}
int main(void) {
    @autoreleasepool {
        AXBSession *s = Fresh();
        Check(!Press(s, 0), "stale revision rejected");
        Check(Press(s, 1), "current revision accepted");
        Check(!Press(s, 1), "second in-flight action rejected");
        NSDictionary *response = [s exchange:Envelope(1) now:2];
        NSDictionary *action = response[@"action"];
        Check(action != nil, "pending action delivered");
        Check([s exchange:Envelope(1) now:2][@"action"] == nil, "action delivered only once");
        Check(!Press(s, 1, 1000), "delivered action never silently expires and permits a duplicate");
        NSMutableDictionary *receipt = [Envelope(2) mutableCopy];
        receipt[@"receipt"] = @{@"id": @"wrong", @"status": @"completed", @"message": @""};
        Check(![[s exchange:receipt now:3][@"ok"] boolValue], "wrong receipt rejected atomically");
        Check([s.snapshot[@"revision"] isEqual:@1], "wrong receipt did not publish state");
        receipt[@"receipt"] = @{@"id": action[@"id"], @"status": @"completed", @"message": @"done"};
        Check([[s exchange:receipt now:3][@"ok"] boolValue], "matching completion accepted");
        Check([[s exchange:receipt now:3][@"ok"] boolValue], "receipt replay idempotent");
        NSDictionary *goodReceipt = receipt[@"receipt"];
        receipt[@"receipt"] = @{@"id": action[@"id"], @"status": @"rejected", @"message": @"changed"};
        Check(![[s exchange:receipt now:3][@"ok"] boolValue], "receipt replay cannot change its result");
        receipt[@"receipt"] = goodReceipt;
        Check(Press(s, 2, 4), "new action accepted after completion");
        Check([s exchange:Envelope(2) now:8][@"action"] == nil, "undelivered action expires");
        Check(Press(s, 2, 9), "queue usable after expiration");
        NSMutableDictionary *changedTarget = MutableCopy(Envelope(3));
        changedTarget[@"snapshot"][@"nodes"][0][@"label"] = @"Delete";
        Check([s exchange:changedTarget now:9][@"action"] == nil, "target change cancels queued action");
        Check(!Press(s, 2, 10), "old revision remains invalid");
        Check(![[s exchange:Envelope(2) now:10][@"ok"] boolValue], "revision cannot go backwards");
        Check(![[s exchange:Envelope(3, NO) now:10][@"ok"] boolValue], "same revision cannot represent changed state");
        Check([[s exchange:Envelope(4, NO) now:10][@"ok"] boolValue], "disabled state published");
        Check(!Press(s, 4), "disabled window rejects action");
        [s invalidate];
        Check(!Press(s, 4), "closed session rejects retained references");
        Check(![[s exchange:Envelope(5) now:10][@"ok"] boolValue], "closed session cannot revive");

        s = Fresh();
        Check(Press(s, 1), "action queued before unrelated update");
        NSMutableDictionary *backgroundUpdate = MutableCopy(Envelope(2));
        backgroundUpdate[@"snapshot"][@"nodes"][1][@"value"] = @"A background refresh";
        response = [s exchange:backgroundUpdate now:2];
        action = response[@"action"];
        Check([action[@"node"] isEqual:@"button"] && [action[@"revision"] isEqual:@2] && [action[@"requestedRevision"] isEqual:@1], "unrelated value update delivers action against checked current revision");
        Check(!Press(s, 2) && [s exchange:backgroundUpdate now:2][@"action"] == nil, "rebased action remains single flight and is not replayed");
        backgroundUpdate[@"receipt"] = @{@"id": action[@"id"], @"status": @"completed", @"message": @""};
        Check([[s exchange:backgroundUpdate now:2][@"ok"] boolValue] && ![s.activity[@"busy"] boolValue], "rebased action uses the same completion identity");

        for (NSString *key in @[@"label", @"value", @"frame", @"enabled", @"visible", @"id"]) {
            s = Fresh(); Check(Press(s, 1), "action queued before target mutation");
            NSMutableDictionary *changed = MutableCopy(Envelope(2));
            NSDictionary *values = @{@"label": @"Changed", @"value": @"Changed", @"frame": @[@11, @20, @120, @30], @"enabled": @NO, @"visible": @NO, @"id": @"replacement"};
            changed[@"snapshot"][@"nodes"][0][key] = values[key];
            response = [s exchange:changed now:2];
            Check([response[@"ok"] boolValue] && response[@"action"] == nil && [response[@"result"][@"status"] isEqual:@"rejected"], "changed target or generation cannot rebase an action");
        }
        s = Fresh(); Check(Press(s, 1), "action queued before focus change");
        backgroundUpdate = MutableCopy(Envelope(2));
        backgroundUpdate[@"snapshot"][@"nodes"][1][@"focused"] = @YES;
        Check([s exchange:backgroundUpdate now:2][@"action"] == nil, "focus context change cancels action even if target is unchanged");
        s = Fresh(); Check(Press(s, 1), "action queued before window scope label change");
        backgroundUpdate = MutableCopy(Envelope(2)); backgroundUpdate[@"snapshot"][@"label"] = @"Another record";
        Check([s exchange:backgroundUpdate now:2][@"action"] == nil, "window context change cancels action");
        s = Fresh(); Check(Press(s, 1), "action queued before unrelated expired update");
        backgroundUpdate = MutableCopy(Envelope(2)); backgroundUpdate[@"snapshot"][@"nodes"][1][@"value"] = @"Updated";
        Check([s exchange:backgroundUpdate now:5][@"action"] == nil, "unrelated updates do not extend action expiry");

        s = Fresh();
        Check(![s enqueueNode:@"missing" revision:@1 operation:@"press" value:nil now:1], "unknown target rejected");
        Check(![s enqueueNode:@"field" revision:@1 operation:@"press" value:nil now:1], "wrong role action rejected");
        Check(![s enqueueNode:@"button" revision:@1 operation:@"setValue" value:@"x" now:1], "button not writable");
        Check(![s enqueueNode:@"field" revision:@1 operation:@"setValue" value:@1 now:1], "wrong value type rejected");
        unichar unmatchedSurrogate = 0xD83C;
        NSString *invalidUnicode = [[NSString alloc] initWithCharacters:&unmatchedSurrogate length:1];
        Check(![s enqueueNode:@"field" revision:@1 operation:@"setValue" value:invalidUnicode now:1], "unpaired UTF-16 cannot enter the host action queue");
        Check([s enqueueNode:@"field" revision:@1 operation:@"setValue" value:@"Unicode: café 日本語 🎸" now:1], "Unicode text accepted");
        Check([[[s exchange:Envelope(1) now:2][@"action"] objectForKey:@"value"] isEqual:@"Unicode: café 日本語 🎸"], "Unicode text preserved");

        s = Fresh();
        Check(![s enqueueNode:@"field" revision:@1 operation:@"reveal" value:nil now:1], "ordinary provider must opt in to reveal");
        NSMutableDictionary *reveal = MutableCopy(Envelope(2));
        reveal[@"snapshot"][@"nodes"][1][@"revealable"] = @YES;
        reveal[@"snapshot"][@"nodes"][1][@"frame"] = @[@10, @600, @120, @30];
        reveal[@"snapshot"][@"nodes"][1][@"clip"] = @[@0, @0, @200, @100];
        Check([[s exchange:reveal now:1][@"ok"] boolValue], "logical offscreen bounds accepted independently of clipping");
        Check(![s enqueueNode:@"field" revision:@2 operation:@"reveal" value:@YES now:1], "reveal accepts no caller-supplied coordinates");
        Check([s enqueueNode:@"field" revision:@2 operation:@"reveal" value:nil now:1], "offscreen reveal queues the exact logical control");
        action = [s exchange:reveal now:2][@"action"];
        Check([action[@"operation"] isEqual:@"reveal"] && [action[@"node"] isEqual:@"field"], "owning host receives reveal once");
        Check([s exchange:reveal now:2][@"action"] == nil, "reveal cannot replay while waiting for host readback");
        NSMutableDictionary *invalidReveal = MutableCopy(reveal);
        invalidReveal[@"snapshot"][@"nodes"][1][@"revealable"] = @"yes";
        Check(AXBValidateEnvelope(invalidReveal) != nil, "reveal capability must be Boolean");
        NSMutableDictionary *navigation = MutableCopy(reveal);
        navigation[@"snapshot"][@"nodes"][1][@"navigation"] = @[@20, @10, @600, @10];
        Check(AXBValidateEnvelope(navigation) == nil, "nested form navigation coordinates are accepted independently of scrolling");
        navigation[@"snapshot"][@"nodes"][1][@"navigation"] = @[@20, @10, @"bad", @10];
        Check(AXBValidateEnvelope(navigation) != nil, "navigation coordinates must be finite numbers");
        navigation[@"snapshot"][@"nodes"][1][@"navigation"] = @[@20, @10, @600];
        Check(AXBValidateEnvelope(navigation) != nil, "navigation paths require complete form coordinate pairs");
        s = Fresh();
        reveal[@"snapshot"][@"nodes"][1][@"enabled"] = @NO;
        [s exchange:reveal now:1];
        Check(![s enqueueNode:@"field" revision:@2 operation:@"setValue" value:@"disabled edit" now:1], "disabled offscreen control rejects editing");
        Check([s enqueueNode:@"field" revision:@2 operation:@"reveal" value:nil now:1], "disabled offscreen control can still be revealed for reading");
        s = Fresh();
        reveal[@"snapshot"][@"nodes"][1][@"visible"] = @NO;
        [s exchange:reveal now:1];
        Check(![s enqueueNode:@"field" revision:@2 operation:@"reveal" value:nil now:1], "hidden control cannot be revealed");

        // Exercise the actual acceptance lock with competing accessibility requests.
        s = Fresh();
        std::atomic<int> successes{0};
        auto *counter = &successes;
        std::vector<std::thread> workers;
        for (int i = 0; i < 20; ++i) workers.emplace_back([captured = s, counter]() {
            @autoreleasepool {
                for (int request = 0; request < 10; ++request) if (Press(captured, 1)) counter->fetch_add(1);
            }
        });
        for (auto &worker : workers) worker.join();
        Check(successes == 1, "concurrent requests admit exactly one action");

        Check(AXBValidateEnvelope(nil) != nil, "missing payload rejected");
        NSArray *bad = @[NSNull.null, @"bad", @[], @{}, @YES, @-1, @1.5];
        for (NSString *key in @[@"version", @"revision", @"nodes", @"label", @"enabled"]) {
            for (id value in bad) {
                NSMutableDictionary *e = MutableCopy(Envelope(1));
                e[@"snapshot"][key] = value;
                (void)AXBValidateEnvelope(e); // Wrong JSON shapes must never throw or crash.
            }
        }
        NSMutableDictionary *e = MutableCopy(Envelope(1));
        [e[@"snapshot"][@"nodes"] addObject:e[@"snapshot"][@"nodes"][0]];
        Check(AXBValidateEnvelope(e) != nil, "duplicate node identities rejected");
        e = MutableCopy(Envelope(1)); e[@"snapshot"][@"nodes"][0][@"frame"] = @[@0, @0, @0, @20];
        Check(AXBValidateEnvelope(e) != nil, "zero area rejected");
        e = MutableCopy(Envelope(1)); e[@"snapshot"][@"nodes"][0][@"role"] = @"password";
        Check(AXBValidateEnvelope(e) != nil, "password control not exposed");
        e = MutableCopy(Envelope(1)); e[@"snapshot"][@"nodes"][0][@"enabled"] = @NO;
        s = [[AXBSession alloc] initWithIdentifier:@"fixture" windowID:1];
        [s exchange:e now:0]; Check(!Press(s, 1), "disabled control rejects action");
        e = MutableCopy(Envelope(1)); e[@"snapshot"][@"nodes"][0][@"visible"] = @NO;
        s = [[AXBSession alloc] initWithIdentifier:@"fixture" windowID:1];
        [s exchange:e now:0]; Check(!Press(s, 1), "hidden control rejects action");

        e = MutableCopy(Envelope(1));
        NSMutableArray *nodes = e[@"snapshot"][@"nodes"];
        [nodes addObject:@{@"id": @"lines", @"role": @"table", @"label": @"Items", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@0, @100, @300, @200]}];
        for (int i = 1; i <= 3; ++i) [nodes addObject:@{@"id": [NSString stringWithFormat:@"line-%d", i], @"role": @"row", @"parent": @"lines", @"label": @"Duplicate SKU", @"value": @"SKU", @"selected": @NO, @"index": @(i-1), @"enabled": @YES, @"visible": @YES, @"frame": @[@0, @(100+i*20), @300, @20]}];
        s = [[AXBSession alloc] initWithIdentifier:@"grid" windowID:1];
        Check([[s exchange:e now:0][@"ok"] boolValue], "table hierarchy accepted");
        e[@"snapshot"][@"label"] = @"Changed outside session";
        Check([s.snapshot[@"label"] isEqual:@"Fixture"], "caller mutation cannot change published snapshot");
        e[@"snapshot"][@"label"] = @"Fixture";
        Check(![s enqueueNode:@"lines" revision:@1 operation:@"selectRows" value:@[@"missing"] now:1], "missing row identity rejected");
        Check(![s enqueueNode:@"lines" revision:@1 operation:@"selectRows" value:@[@"line-3", @"line-3"] now:1], "duplicate selection rejected");
        Check([s enqueueNode:@"lines" revision:@1 operation:@"selectRows" value:@[@"line-3"] now:1], "stable ID selected despite duplicate display label");
        e[@"snapshot"][@"revision"] = @2;
        [nodes exchangeObjectAtIndex:3 withObjectAtIndex:5];
        Check([s exchange:e now:2][@"action"] == nil, "sort revision cancels queued row selection");
        Check([s enqueueNode:@"lines" revision:@2 operation:@"selectRows" value:@[@"line-3"] now:3], "stable ID survives reordering");
        [nodes removeObjectAtIndex:3]; e[@"snapshot"][@"revision"] = @3;
        Check([s exchange:e now:3][@"action"] == nil, "removed row cancels pending selection");
        Check(![s enqueueNode:@"lines" revision:@3 operation:@"selectRows" value:@[@"line-3"] now:3], "removed row cannot be targeted");
        Check([s enqueueNode:@"lines" revision:@3 operation:@"selectRows" value:@[] now:3], "empty selection can clear table");
        e = MutableCopy(e); e[@"snapshot"][@"nodes"][0][@"parent"] = @"lines";
        Check(AXBValidateEnvelope(e) != nil, "unsupported parent shape rejected");

        e = MutableCopy(Envelope(1));
        NSMutableDictionary *field = e[@"snapshot"][@"nodes"][1];
        field[@"focusable"] = @YES; field[@"editable"] = @YES;
        field[@"selection"] = @[@0, @2];
        s = [[AXBSession alloc] initWithIdentifier:@"editor" windowID:1];
        Check([[s exchange:e now:0][@"ok"] boolValue], "editor capabilities and a valid selection accepted");
        Check(![s enqueueNode:@"field" revision:@1 operation:@"setSelection" value:@[@0, @3] now:1], "selection beyond text rejected");
        Check(![s enqueueNode:@"field" revision:@1 operation:@"setSelection" value:@[@-1, @1] now:1], "negative selection rejected");
        Check(![s enqueueNode:@"field" revision:@1 operation:@"setSelection" value:@[@0.5, @1] now:1], "fractional selection rejected");
        Check(![s enqueueNode:@"field" revision:@1 operation:@"focus" value:@NO now:1], "unsupported focus clearing rejected");
        Check([s enqueueNode:@"field" revision:@1 operation:@"setSelection" value:@[@1, @1] now:1], "valid partial text selection queued");
        field[@"selection"] = @[@1, @2];
        Check(AXBValidateEnvelope(e) != nil, "invalid published selection rejected");
        [field removeObjectForKey:@"selection"];
        field[@"protected"] = @YES;
        Check(AXBValidateEnvelope(e) != nil, "protected field cannot publish nonempty text");
        field[@"value"] = @"";
        Check(AXBValidateEnvelope(e) == nil, "protected field can publish empty secure semantics");
        s = [[AXBSession alloc] initWithIdentifier:@"secure" windowID:1];
        [s exchange:e now:0];
        Check(![s enqueueNode:@"field" revision:@1 operation:@"replaceSelection" value:@"x" now:1], "protected selection replacement rejected");
        Check([s enqueueNode:@"field" revision:@1 operation:@"setValue" value:@"synthetic input" now:1], "protected field accepts write-only text entry");
        field[@"editable"] = @NO;
        s = [[AXBSession alloc] initWithIdentifier:@"readonly" windowID:1];
        [s exchange:e now:0];
        Check(![s enqueueNode:@"field" revision:@1 operation:@"setValue" value:@"x" now:1], "read-only field rejects text mutation");
        field[@"protected"] = @NO; field[@"value"] = @"QA";
        for (NSString *key in @[@"focused", @"focusable", @"editable", @"protected", @"multiline", @"selection", @"labelledBy", @"placeholder"])
            for (id value in bad) {
                NSMutableDictionary *malformed = MutableCopy(e);
                malformed[@"snapshot"][@"nodes"][1][key] = value;
                (void)AXBValidateEnvelope(malformed);
            }
        e = MutableCopy(Envelope(1));
        field = e[@"snapshot"][@"nodes"][1];
        field[@"editable"] = @YES; field[@"focused"] = @YES;
        s = [[AXBSession alloc] initWithIdentifier:@"unicode" windowID:1];
        [s exchange:e now:0];
        Check([s enqueueNode:@"field" revision:@1 operation:@"setValue" value:@"🎸🎹" now:1], "supplementary text action queued");
        action = [s exchange:e now:1][@"action"];
        NSDictionary *input = @{@"action": action[@"id"], @"serial": @1, @"text": @"🎸"};
        e[@"editorInput"] = input;
        Check([[s exchange:e now:2][@"editorInput"] isEqual:input], "one complete supplementary character dispatched for the active editor");
        Check([s exchange:e now:2][@"editorInput"] == nil, "repeated input exchange cannot type the character twice");
        Check([s exchange:e now:2][@"editorInputResult"] == nil, "queued input is not acknowledged before native delivery");
        [s finishEditorInput:@{@"action": @"stale", @"serial": @1, @"text": @"🎸"} accepted:YES];
        Check([s exchange:e now:2][@"editorInputResult"] == nil, "stale native delivery cannot acknowledge the current action");
        [s finishEditorInput:input accepted:YES];
        NSDictionary *inputResult = [s exchange:e now:2][@"editorInputResult"];
        Check([inputResult[@"action"] isEqual:action[@"id"]] && [inputResult[@"serial"] isEqual:@1] && [inputResult[@"accepted"] boolValue], "native confirmation identifies the exact delivered character");
        [s finishEditorInput:input accepted:NO];
        Check([[s exchange:e now:2][@"editorInputResult"] isEqual:inputResult], "native input confirmation is immutable");
        e[@"editorInput"] = @{@"action": action[@"id"], @"serial": @1, @"text": @"🎹"};
        Check(![[s exchange:e now:2][@"ok"] boolValue], "input replay cannot change the character");
        e[@"snapshot"][@"revision"] = @2; field[@"focused"] = @NO;
        e[@"editorInput"] = @{@"action": action[@"id"], @"serial": @3, @"text": @"🎹"};
        Check(![[s exchange:e now:2][@"ok"] boolValue] && [s.snapshot[@"revision"] isEqual:@1], "input for an unfocused editor rejects without publishing its snapshot");
        field[@"focused"] = @YES; field[@"editable"] = @NO;
        Check(![[s exchange:e now:2][@"ok"] boolValue], "editor input cannot continue after editability is removed");
        field[@"editable"] = @YES;
        e[@"editorInput"] = @{@"action": @"another action", @"serial": @2, @"text": @"🎹"};
        Check(![[s exchange:e now:2][@"ok"] boolValue], "another action cannot inject a keyboard event");
        for (NSString *key in @[@"action", @"serial", @"text"])
            for (id value in bad) {
                if ([key isEqual:@"action"] && [value isKindOfClass:NSString.class]) continue;
                NSMutableDictionary *malformed = MutableCopy(e);
                malformed[@"editorInput"][key] = value;
                Check(AXBValidateEnvelope(malformed) != nil, "malformed editor input rejected");
            }
        [s invalidate];
        Check(![s canPostEditorInput:input], "closing the session cancels a scheduled editor event");
        e = MutableCopy(Envelope(1));
        field = e[@"snapshot"][@"nodes"][1];
        field[@"editable"] = @YES; field[@"focused"] = @YES;
        field[@"selection"] = @[@0, @2];
        s = [[AXBSession alloc] initWithIdentifier:@"bulk-text" windowID:1];
        [s exchange:e now:0];
        NSString *bulkText = [@"Long note " stringByPaddingToLength:10000 withString:@"text " startingAtIndex:0];
        Check([s enqueueNode:@"field" revision:@1 operation:@"setValue" value:bulkText now:1], "long native insertion action queued");
        action = [s exchange:e now:1][@"action"];
        input = @{@"action": action[@"id"], @"serial": @1, @"mode": @"insert", @"text": bulkText, @"selection": @[@0, @2]};
        e[@"editorInput"] = input;
        Check([[s exchange:e now:2][@"editorInput"] isEqual:input], "complete long input dispatches for the selected ordinary editor");
        Check([s exchange:e now:2][@"editorInput"] == nil, "long input replay cannot repeat an insertion");
        NSMutableDictionary *alteredInput = [input mutableCopy];
        alteredInput[@"text"] = @"unrequested text"; e[@"editorInput"] = alteredInput;
        Check(![[s exchange:e now:2][@"ok"] boolValue], "long insertion cannot substitute another value");
        e[@"editorInput"] = input; e[@"snapshot"][@"revision"] = @2;
        field[@"selection"] = @[@1, @1];
        Check(![[s exchange:e now:2][@"ok"] boolValue], "changed editor selection cancels long insertion");
        field[@"selection"] = @[@0, @2]; field[@"focused"] = @NO;
        Check(![[s exchange:e now:2][@"ok"] boolValue], "changed focus cancels long insertion");
        [s invalidate];
        Check(![s canPostEditorInput:input], "closing the form cancels long insertion");
        e = MutableCopy(Envelope(1));
        field = e[@"snapshot"][@"nodes"][1];
        field[@"editable"] = @YES; field[@"focused"] = @YES; field[@"selection"] = @[@0, @2];
        s = [[AXBSession alloc] initWithIdentifier:@"bulk-line-endings" windowID:1];
        [s exchange:e now:0];
        Check([s enqueueNode:@"field" revision:@1 operation:@"setValue" value:[bulkText stringByAppendingString:@"\r\n\r\n"] now:1], "long value with CRLF endings queued");
        action = [s exchange:e now:1][@"action"];
        e[@"editorInput"] = @{@"action": action[@"id"], @"serial": @1, @"mode": @"insert", @"text": bulkText, @"selection": @[@0, @2]};
        Check([s exchange:e now:2][@"editorInput"] != nil, "native prefix matches normalized input before guarded trailing Returns");
        // A real invoice definition has hundreds of ordinary controls. Its
        // text fields can contain substantially more than a small label.
        e = MutableCopy(Envelope(1));
        NSMutableArray *largeForm = [NSMutableArray new];
        NSString *longNote = [@"Invoice note " stringByPaddingToLength:524288 withString:@"text " startingAtIndex:0];
        for (NSUInteger i = 0; i < 600; i++) {
            NSMutableDictionary *control = [e[@"snapshot"][@"nodes"][1] mutableCopy];
            control[@"id"] = [NSString stringWithFormat:@"field-%lu", i];
            control[@"label"] = [NSString stringWithFormat:@"Field %lu", i];
            control[@"value"] = i == 599 ? longNote : @"Ordinary value";
            control[@"editable"] = @YES;
            [largeForm addObject:control];
        }
        e[@"snapshot"][@"nodes"] = largeForm;
        s = [[AXBSession alloc] initWithIdentifier:@"large-form" windowID:1];
        Check([[s exchange:e now:0][@"ok"] boolValue], "complete large form and long note remain accessible");
        Check([s.snapshot[@"nodes"] count] == 600 && [s.snapshot[@"nodes"][599][@"value"] isEqual:longNote], "large form retains every ordinary control and the entire note");
        Check([s enqueueNode:@"field-599" revision:@1 operation:@"setSelection" value:@[@60000, @10] now:1], "selection can address text beyond the old field limit");
        s = [[AXBSession alloc] initWithIdentifier:@"long-entry" windowID:1];
        [s exchange:e now:0];
        Check([s enqueueNode:@"field-599" revision:@1 operation:@"setValue" value:longNote now:1], "long text can reach the existing editor action pipeline");
        largeForm[599][@"value"] = [longNote stringByPaddingToLength:1048577 withString:@"x" startingAtIndex:0];
        Check(AXBValidateEnvelope(e) != nil, "per-control text still has a bounded memory budget");
        largeForm[599][@"value"] = @"";
        for (NSUInteger i = largeForm.count; i < 4097; i++) {
            NSMutableDictionary *control = [largeForm[0] mutableCopy];
            control[@"id"] = [NSString stringWithFormat:@"field-%lu", i];
            [largeForm addObject:control];
        }
        Check(AXBValidateEnvelope(e) != nil, "ordinary node count remains bounded independently of logical grid rows");
        e = MutableCopy(Envelope(1));
        NSMutableArray *semanticNodes = e[@"snapshot"][@"nodes"];
        NSMutableDictionary *group = [semanticNodes[0] mutableCopy];
        group[@"id"] = @"group"; group[@"role"] = @"group"; group[@"label"] = @"Shipping";
        [semanticNodes addObject:group];
        semanticNodes[0][@"parent"] = @"group";
        NSMutableDictionary *progress = [group mutableCopy];
        progress[@"id"] = @"progress"; progress[@"role"] = @"progress"; progress[@"value"] = @35;
        progress[@"min"] = @0; progress[@"max"] = @100; progress[@"indeterminate"] = @NO;
        progress[@"valueDescription"] = @"35 items received";
        [semanticNodes addObject:progress];
        NSMutableDictionary *picture = [group mutableCopy];
        picture[@"id"] = @"image"; picture[@"role"] = @"image"; picture[@"value"] = @"Ready to ship";
        [semanticNodes addObject:picture];
        Check(AXBValidateEnvelope(e) == nil, "ordinary groups, described images and numeric progress are valid");
        s = [[AXBSession alloc] initWithIdentifier:@"semantics" windowID:1];
        [s exchange:e now:0];
        Check(![s enqueueNode:@"progress" revision:@1 operation:@"setValue" value:@50 now:1] &&
            ![s enqueueNode:@"image" revision:@1 operation:@"press" value:nil now:1], "status controls never advertise or queue edits");
        Check(Press(s, 1), "grouped ordinary button retains its existing action");
        group[@"parent"] = @"group";
        Check(AXBValidateEnvelope(e) != nil, "group cannot parent itself");
        group[@"parent"] = @"image";
        Check(AXBValidateEnvelope(e) != nil, "image cannot become a container");
        [group removeObjectForKey:@"parent"];
        NSMutableDictionary *inner = [group mutableCopy];
        inner[@"id"] = @"inner"; inner[@"parent"] = @"group";
        [semanticNodes addObject:inner];
        group[@"parent"] = @"inner";
        Check(AXBValidateEnvelope(e) != nil, "indirect group cycle is rejected");
        [group removeObjectForKey:@"parent"];
        Check(AXBValidateEnvelope(e) == nil, "nested semantic groups remain valid");
        progress[@"max"] = @-1;
        Check(AXBValidateEnvelope(e) != nil, "progress requires an ordered finite range");
        progress[@"max"] = @100; progress[@"indeterminate"] = @YES; progress[@"value"] = NSNull.null;
        Check(AXBValidateEnvelope(e) == nil, "indeterminate progress omits a fictitious percentage");
        progress[@"valueDescription"] = @42;
        Check(AXBValidateEnvelope(e) != nil, "status description must be text");
        e = MutableCopy(Envelope(1));
        field = e[@"snapshot"][@"nodes"][1]; field[@"combo"] = @YES; field[@"editable"] = @YES;
        Check(AXBValidateEnvelope(e) == nil, "editable combo reuses the ordinary text contract");
        s = [[AXBSession alloc] initWithIdentifier:@"combo" windowID:1];
        [s exchange:e now:0];
        Check(![s enqueueNode:@"button" revision:@1 operation:@"showMenu" value:nil now:1], "ordinary button cannot receive a combo menu request");
        Check([s enqueueNode:@"field" revision:@1 operation:@"showMenu" value:nil now:1], "combo can request its real native menu");
        e[@"snapshot"][@"revision"] = @2; field[@"combo"] = @NO;
        Check([s exchange:e now:2][@"action"] == nil, "changing the control family retires a pending combo menu action");
        field[@"combo"] = @YES; e[@"snapshot"][@"revision"] = @3;
        [s exchange:e now:3];
        Check(![s enqueueNode:@"button" revision:@3 operation:@"dismissMenu" value:nil now:3], "ordinary button cannot receive combo cancellation");
        Check([s enqueueNode:@"field" revision:@3 operation:@"dismissMenu" value:nil now:3], "combo cancellation uses the guarded action queue");
        field[@"combo"] = @NO; e[@"snapshot"][@"revision"] = @4;
        Check([s exchange:e now:4][@"action"] == nil, "changing the control family retires pending combo cancellation");
        field[@"combo"] = @YES; field[@"multiline"] = @YES;
        Check(AXBValidateEnvelope(e) != nil, "combo cannot masquerade as a multiline editor");
        field[@"multiline"] = @NO; field[@"combo"] = @"yes";
        Check(AXBValidateEnvelope(e) != nil, "combo capability must be Boolean");
        e = MutableCopy(Envelope(1));
        NSMutableDictionary *checkbox = e[@"snapshot"][@"nodes"][0];
        checkbox[@"role"] = @"checkbox"; checkbox[@"value"] = @2;
        Check(AXBValidateEnvelope(e) == nil, "checkbox preserves the native mixed state");
        s = [[AXBSession alloc] initWithIdentifier:@"mixed-checkbox" windowID:1];
        [s exchange:e now:0];
        Check([s enqueueNode:@"button" revision:@1 operation:@"press" value:nil now:1], "mixed checkbox uses the normal activation path");
        NSString *checkboxAction = s.activity[@"id"];
        Check(checkboxAction.length > 0, "asynchronous feedback can identify the exact queued action without exposing its value");
        e[@"snapshot"][@"revision"] = @2; checkbox[@"value"] = @YES;
        Check([s exchange:e now:2][@"action"] == nil, "mixed-to-checked refresh invalidates an old activation");
        Check(!s.activity[@"id"] && [s.activity[@"result"][@"id"] isEqual:checkboxAction] && [s.activity[@"result"][@"status"] isEqual:@"rejected"], "cancelled feedback retains its rejection identity and clears the pending action");
        for (id invalid in @[@-1, @3, @1.5, @"mixed", NSNull.null]) {
            checkbox[@"value"] = invalid;
            Check(AXBValidateEnvelope(e) != nil, "checkbox rejects an invalid mixed-state value");
        }
        checkbox[@"role"] = @"radio"; checkbox[@"value"] = @2;
        Check(AXBValidateEnvelope(e) != nil, "radio button cannot claim mixed state");
        NSDictionary *observed = Envelope(1);
        e = MutableCopy(Envelope(2)); e[@"snapshot"][@"nodes"][1][@"value"] = @"Unrelated update";
        s = [[AXBSession alloc] initWithIdentifier:@"native-refresh" windowID:1];
        [s exchange:observed now:0]; [s exchange:e now:1];
        Check([s enqueueNode:@"button" revision:@1 operation:@"press" value:nil observedSnapshot:observed[@"snapshot"] now:2], "native refresh lag can rebase an unchanged target");
        action = [s exchange:e now:2][@"action"];
        Check([action[@"revision"] isEqual:@2] && [action[@"requestedRevision"] isEqual:@1], "rebased native action retains both observed and checked revisions");
        for (NSString *key in @[@"label", @"value", @"frame", @"enabled", @"visible", @"focus"]) {
            s = [[AXBSession alloc] initWithIdentifier:@"native-refresh-guard" windowID:1];
            [s exchange:observed now:0]; e = MutableCopy(Envelope(2));
            if ([key isEqual:@"focus"]) e[@"snapshot"][@"nodes"][1][@"focused"] = @YES;
            else e[@"snapshot"][@"nodes"][0][key] = [key isEqual:@"frame"] ? @[@20, @20, @120, @30] :
                [@[@"enabled", @"visible"] containsObject:key] ? (id)@NO : @"Changed";
            [s exchange:e now:1];
            Check(![s enqueueNode:@"button" revision:@1 operation:@"press" value:nil observedSnapshot:observed[@"snapshot"] now:2], "native refresh lag never authorizes a changed target or focus");
        }
        for (NSString *kind in @[@"slider", @"stepper", @"callback", @"keyboardStepper"]) {
            NSString *role = [kind isEqual:@"slider"] || [kind isEqual:@"callback"] ? @"slider" : @"stepper";
            NSString *route = [kind isEqual:@"stepper"] ? @"pointer" : [kind isEqual:@"callback"] ? @"callback" : @"keyboard";
            NSMutableDictionary *adjustable = MutableCopy(Envelope(1));
            NSMutableDictionary *control = adjustable[@"snapshot"][@"nodes"][0];
            control[@"role"] = role; control[@"value"] = @4; control[@"min"] = @0; control[@"max"] = @10;
            control[@"step"] = @2; control[@"adjustable"] = @YES;
            control[@"adjustment"] = route; control[@"vertical"] = @NO;
            Check(AXBValidateEnvelope(adjustable) == nil, "adjustable controls expose actual range and step");
            control[@"vertical"] = @1;
            Check(AXBValidateEnvelope(adjustable) != nil, "adjustment orientation must be Boolean");
            control[@"vertical"] = @NO;
            control[@"adjustment"] = @YES;
            Check(AXBValidateEnvelope(adjustable) != nil, "adjustment route must name a supported mechanism");
            control[@"adjustment"] = route;
            for (id invalid in @[@0, @-1, @YES, @"2"]) {
                control[@"step"] = invalid;
                Check(AXBValidateEnvelope(adjustable) != nil, "adjustable controls reject invalid step values");
            }
            control[@"step"] = @2;
            s = [[AXBSession alloc] initWithIdentifier:role windowID:1];
            [s exchange:adjustable now:0];
            Check([s enqueueNode:@"button" revision:@1 operation:@"increment" value:nil now:1], "adjustable control accepts increment");
            NSDictionary *adjustAction = [s exchange:adjustable now:1][@"action"];
            NSDictionary *input = @{@"action": adjustAction[@"id"]};
            adjustable[@"controlInput"] = input;
            NSDictionary *delivery = [s exchange:adjustable now:1];
            if ([route isEqual:@"pointer"]) {
                Check([delivery[@"controlInput"] isEqual:input], "stepper requests exactly one native activation");
                Check([s exchange:adjustable now:1][@"controlInput"] == nil, "stepper input replay cannot duplicate a click");
                Check([s controlInputNode:input] != nil, "native stepper delivery requires the live target");
                [s finishControlInput:input accepted:YES];
                Check([[s exchange:adjustable now:1][@"controlInputResult"][@"accepted"] boolValue], "native stepper delivery has an exact acknowledgement");
            } else Check(![delivery[@"ok"] boolValue], "keyboard and controller actions cannot inject a stepper click");
            [adjustable removeObjectForKey:@"controlInput"];
            adjustable[@"receipt"] = @{@"id": adjustAction[@"id"], @"status": @"completed", @"message": @"done"};
            [s exchange:adjustable now:2];
            Check([s controlInputNode:input] == nil, "completed action cannot inject another click");
            [adjustable removeObjectForKey:@"receipt"];
            control[@"adjustable"] = @NO; adjustable[@"snapshot"][@"revision"] = @2;
            [s exchange:adjustable now:3];
            Check(![s enqueueNode:@"button" revision:@2 operation:@"decrement" value:nil now:3], "read-only adjustable rejects mutation");
        }
        NSMutableDictionary *dateStepper = MutableCopy(Envelope(1));
        NSMutableDictionary *dateNode = dateStepper[@"snapshot"][@"nodes"][0];
        dateNode[@"role"] = @"stepper"; dateNode[@"value"] = @"September 24, 2026";
        dateNode[@"step"] = @2; dateNode[@"adjustable"] = @YES;
        Check(AXBValidateEnvelope(dateStepper) == nil, "date stepper has a formatted value without a fictitious numeric range");
        s = [[AXBSession alloc] initWithIdentifier:@"date-stepper" windowID:1];
        [s exchange:dateStepper now:0];
        Check([s enqueueNode:@"button" revision:@1 operation:@"decrement" value:nil now:1], "date stepper accepts decrement");
        NSDictionary *dateAction = [s exchange:dateStepper now:1][@"action"];
        dateStepper[@"controlInput"] = @{@"action": dateAction[@"id"]};
        [s exchange:dateStepper now:1];
        [dateStepper removeObjectForKey:@"controlInput"];
        dateStepper[@"snapshot"][@"revision"] = @2; dateNode[@"value"] = @"September 25, 2026";
        [s exchange:dateStepper now:2];
        Check([s controlInputNode:@{@"action": dateAction[@"id"]}] == nil, "target change after host delivery cancels native activation");

        printf("PASS: %d checks, malformed-JSON shape checks, 200 concurrent requests\n", checks);
    }
}
