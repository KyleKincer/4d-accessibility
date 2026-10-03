// Owned AppKit host for the production outline provider. No 4D adapter is used.
#import <Cocoa/Cocoa.h>
#import "Bridge.h"

@interface OutlineFixture : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *directory, *runID, *session;
@property(nonatomic, strong) NSMutableDictionary *grid;
@property(nonatomic, strong) NSMutableArray *requests;
@property(nonatomic) NSInteger revision, command, pages;
@property(nonatomic) BOOL expanded, selectionKnown;
- (void)describe;
- (void)tick;
@end
@implementation OutlineFixture
- (void)describe {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@"first"];
    if (self.expanded) [rows addObjectsFromArray:@[@"nested", @"leaf/1", @"leaf/2"]];
    [rows addObject:@"later"];
    for (NSInteger n = 0; n < 20; n++) [rows addObject:[NSString stringWithFormat:@"root/%ld", (long)n]];
    NSMutableDictionary *outline = [NSMutableDictionary new], *frames = [NSMutableDictionary new];
    NSMutableArray *layout = [NSMutableArray new], *visible = [NSMutableArray new];
    for (NSUInteger n = 0; n < rows.count; n++) {
        NSString *key = rows[n];
        NSString *parent = [key isEqual:@"nested"] ? @"first" : [key hasPrefix:@"leaf/"] ? @"nested" : @"";
        NSNumber *level = parent.length ? @([parent isEqual:@"nested"] ? 2 : 1) : @0;
        NSMutableDictionary *item = [@{@"parent": parent, @"level": level, @"kind": @"leaf"} mutableCopy];
        NSArray *frame = @[@20, @(20 + n * 28), @500, @28];
        BOOL group = [@[@"first", @"nested", @"later"] containsObject:key];
        if (group) {
            item[@"kind"] = @"group"; item[@"label"] = [key isEqual:@"nested"] ? @"Nested group" : @"Repeated group";
            item[@"expanded"] = @(![key isEqual:@"later"] && self.expanded); item[@"frame"] = frame;
        }
        outline[key] = item;
        [layout addObject:@[@(20 + n * 28), @28]];
        if (n < 10) {
            [visible addObject:key];
            frames[key] = group ? @{@"label": frame} : @{@"label": @[@20, @(20 + n * 28), @300, @28], @"value": @[@320, @(20 + n * 28), @200, @28]};
        }
    }
    self.grid[@"rows"] = rows; self.grid[@"outline"] = outline;
    self.grid[@"visible"] = visible; self.grid[@"frames"] = frames;
    self.grid[@"layout"] = @{@"rows": layout, @"columns": @[@[@20, @300], @[@320, @200]]};
    self.grid[@"selectionKnown"] = @(self.selectionKnown);
    if (self.selectionKnown) self.grid[@"selected"] = @[@"later"];
    else [self.grid removeObjectForKey:@"selected"];
}
- (NSDictionary *)page:(NSDictionary *)request {
    if (![request[@"generation"] isEqual:self.grid[@"generation"]] || ![request[@"order"] isEqual:self.grid[@"order"]]) return nil;
    NSMutableArray *rows = [NSMutableArray new];
    NSUInteger start = [request[@"row"] unsignedIntegerValue], column = [request[@"column"] unsignedIntegerValue];
    for (NSUInteger r = start; r < start + [request[@"rowCount"] unsignedIntegerValue]; r++) {
        NSString *key = self.grid[@"rows"][r]; NSDictionary *item = self.grid[@"outline"][key];
        NSMutableArray *cells = [NSMutableArray new];
        for (NSUInteger c = column; c < column + [request[@"columnCount"] unsignedIntegerValue]; c++) {
            NSString *value;
            if ([item[@"kind"] isEqual:@"group"]) value = c == 0 ? item[@"label"] : @"";
            else if (c == 0) value = [key isEqual:@"root/19"] ? @"Distant leaf" : [NSString stringWithFormat:@"Item %@", key];
            else value = [NSString stringWithFormat:@"Value %@", key];
            [cells addObject:@{@"column": self.grid[@"columns"][c][@"id"], @"value": value, @"enabled": @YES, @"editable": @NO}];
        }
        [rows addObject:@{@"id": key, @"cells": cells}];
    }
    NSMutableDictionary *page = [request mutableCopy]; page[@"rows"] = rows; self.pages++;
    return page;
}
- (void)tick {
    NSData *data = [NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"command.json"]];
    NSDictionary *command = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([command[@"id"] integerValue] > self.command && [command[@"runID"] isEqual:self.runID]) {
        self.command = [command[@"id"] integerValue]; NSString *operation = command[@"operation"];
        if ([operation isEqual:@"quit"]) {
            AXBShutdown();
            [[NSJSONSerialization dataWithJSONObject:@{@"runID": self.runID, @"pid": @(NSProcessInfo.processInfo.processIdentifier)} options:0 error:nil]
                writeToFile:[self.directory stringByAppendingPathComponent:@"closed.json"] atomically:YES];
            [self.window close]; [NSApp terminate:nil]; return;
        }
        if ([operation isEqual:@"collapse"]) self.expanded = NO;
        if ([operation isEqual:@"expand"]) self.expanded = YES;
        if ([operation isEqual:@"knownSelection"]) self.selectionKnown = YES;
        if ([operation isEqual:@"unknownSelection"]) self.selectionKnown = NO;
        if ([operation isEqual:@"replace"]) self.grid[@"generation"] = NSUUID.UUID.UUIDString;
        self.grid[@"order"] = @([self.grid[@"order"] integerValue] + 1); self.revision++; [self describe];
    }
    NSMutableArray *pages = [NSMutableArray new];
    for (NSUInteger n = 0; n < 2 && self.requests.count; n++) {
        NSDictionary *request = self.requests.firstObject; [self.requests removeObjectAtIndex:0];
        NSDictionary *page = [self page:request]; if (page) [pages addObject:page];
    }
    NSDictionary *snapshot = @{@"version": @1, @"revision": @(self.revision), @"label": @"Outline fixture", @"enabled": @YES,
        @"nodes": @[@{@"id": @"outline", @"role": @"table", @"label": @"Grouped items", @"value": @"", @"visible": @YES,
            @"enabled": @YES, @"frame": @[@20, @20, @500, @280], @"grid": self.grid}]};
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:@{@"snapshot": snapshot, @"gridPages": pages} options:0 error:nil];
    NSString *json = AXBExchange(811, 1, (__bridge void *)self.window, self.session, [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]);
    NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![reply[@"ok"] boolValue] || reply[@"action"]) { NSLog(@"Outline fixture error: %@", reply); abort(); }
    [self.requests addObjectsFromArray:reply[@"gridRequests"] ?: @[]];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *state = @{@"runID": self.runID, @"pid": @(NSProcessInfo.processInfo.processIdentifier), @"command": @(self.command),
            @"pages": @(self.pages), @"revision": @(self.revision), @"expanded": @(self.expanded), @"rows": self.grid[@"rows"], @"selectionKnown": @(self.selectionKnown)};
        [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:[self.directory stringByAppendingPathComponent:@"state.json"] atomically:YES];
    });
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; [NSApp finishLaunching];
        OutlineFixture *fixture = [OutlineFixture new]; fixture.directory = @(argv[1]); fixture.runID = @(argv[2]);
        fixture.revision = 1; fixture.expanded = YES; fixture.requests = [NSMutableArray new];
        fixture.grid = [@{@"generation": @"outline-a", @"order": @1, @"columns": @[
            @{@"id": @"label", @"label": @"Item", @"enabled": @YES, @"editable": @NO},
            @{@"id": @"value", @"label": @"Value", @"enabled": @YES, @"editable": @NO}],
            @"actions": @{@"select": @NO, @"edit": @NO, @"reveal": @NO}} mutableCopy];
        [fixture describe];
        fixture.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 560, 340)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        fixture.window.releasedWhenClosed = NO; fixture.window.title = @"AXB native outline fixture";
        [fixture.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        NSDictionary *opened = [NSJSONSerialization JSONObjectWithData:[AXBOpen(811, 1, (__bridge void *)fixture.window) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![opened[@"ok"] boolValue]) return 3; fixture.session = opened[@"session"];
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { (void)timer; [fixture tick]; }];
        [NSApp run];
    }
    return 0;
}
