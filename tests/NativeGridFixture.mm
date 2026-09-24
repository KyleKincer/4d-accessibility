// Disposable native host for complete-grid AX transport and asynchronous values.
// It uses the production provider and session, with synthetic owning-form data.
#import <Cocoa/Cocoa.h>
#import "Bridge.h"

@interface GridFixture : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *directory, *session;
@property(nonatomic, strong) NSMutableDictionary *grid;
@property(nonatomic, strong) NSMutableArray *requests;
@property(nonatomic) NSInteger revision, command, pages, valueVersion;
@property(nonatomic) NSInteger firstRow, firstColumn;
@property(nonatomic, strong) NSDictionary *receipt;
- (void)tick;
@end
@implementation GridFixture
- (NSDictionary *)snapshot {
    return @{@"version": @1, @"revision": @(self.revision), @"label": @"Complete grid fixture", @"enabled": @YES, @"nodes": @[
        @{@"id": @"grid", @"role": @"table", @"label": @"All 50000 rows and 24 columns", @"value": @"", @"visible": @YES, @"enabled": @YES,
          @"frame": @[@20, @20, @720, @370], @"grid": self.grid}]};
}
- (void)geometry {
    self.firstRow = MAX(0, MIN(self.firstRow, (NSInteger)[self.grid[@"rows"] count] - 12));
    self.firstColumn = MAX(0, MIN(self.firstColumn, (NSInteger)[self.grid[@"columns"] count] - 3));
    NSMutableDictionary *frames = [NSMutableDictionary new], *headers = [NSMutableDictionary new];
    NSMutableArray *visible = [NSMutableArray new];
    for (NSInteger r = self.firstRow; r < self.firstRow + 12; r++) {
        NSString *key = self.grid[@"rows"][r]; [visible addObject:key];
        NSMutableDictionary *cells = [NSMutableDictionary new];
        for (NSInteger c = self.firstColumn; c < self.firstColumn + 3; c++) cells[[NSString stringWithFormat:@"column-%ld", (long)c]] = @[@(20 + (c-self.firstColumn) * 240), @(50 + (r-self.firstRow) * 28), @240, @28];
        frames[key] = cells;
    }
    for (NSInteger c = self.firstColumn; c < self.firstColumn + 3; c++) headers[[NSString stringWithFormat:@"column-%ld", (long)c]] = @[@(20 + (c-self.firstColumn) * 240), @20, @240, @28];
    self.grid[@"visible"] = visible; self.grid[@"frames"] = frames; self.grid[@"headers"] = headers;
    NSMutableArray *rowLayout = [NSMutableArray new], *columnLayout = [NSMutableArray new];
    for (NSInteger r = 0; r < (NSInteger)[self.grid[@"rows"] count]; r++) [rowLayout addObject:@[@(50 + (r-self.firstRow) * 28), @28]];
    for (NSInteger c = 0; c < (NSInteger)[self.grid[@"columns"] count]; c++) [columnLayout addObject:@[@(20 + (c-self.firstColumn) * 240), @240]];
    self.grid[@"layout"] = @{@"rows": rowLayout, @"columns": columnLayout};
}
- (NSDictionary *)page:(NSDictionary *)request {
    if (![request[@"generation"] isEqual:self.grid[@"generation"]] || ![request[@"order"] isEqual:self.grid[@"order"]]) return nil;
    NSMutableArray *rows = [NSMutableArray new];
    NSUInteger start = [request[@"row"] unsignedIntegerValue], column = [request[@"column"] unsignedIntegerValue];
    for (NSUInteger r = start; r < start + [request[@"rowCount"] unsignedIntegerValue]; r++) {
        NSMutableArray *cells = [NSMutableArray new]; NSString *key = self.grid[@"rows"][r];
        for (NSUInteger c = column; c < column + [request[@"columnCount"] unsignedIntegerValue]; c++) {
            NSString *value = [NSString stringWithFormat:@"%@ / column-%lu / value-%ld", key, c, (long)self.valueVersion];
            [cells addObject:@{@"column": self.grid[@"columns"][c][@"id"], @"value": value, @"enabled": @YES, @"editable": @NO}];
        }
        [rows addObject:@{@"id": key, @"cells": cells}];
    }
    NSMutableDictionary *page = [request mutableCopy]; page[@"rows"] = rows; self.pages++;
    return page;
}
- (void)tick {
    NSData *commandData = [NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"command.json"]];
    NSDictionary *command = commandData ? [NSJSONSerialization JSONObjectWithData:commandData options:0 error:nil] : nil;
    if ([command[@"id"] integerValue] > self.command) {
        self.command = [command[@"id"] integerValue];
        NSString *operation = command[@"operation"];
        if ([operation isEqual:@"quit"]) { AXBShutdown(); [self.window close]; [NSApp terminate:nil]; return; }
        if ([operation isEqual:@"sort"]) {
            self.grid[@"rows"] = [[self.grid[@"rows"] reverseObjectEnumerator] allObjects];
            self.grid[@"order"] = @([self.grid[@"order"] integerValue] + 1); [self geometry]; self.revision++;
        }
        if ([operation isEqual:@"replace"]) { self.grid[@"generation"] = NSUUID.UUID.UUIDString; self.grid[@"order"] = @1; self.revision++; }
        if ([operation isEqual:@"values"]) self.valueVersion++;
        if ([operation isEqual:@"remove"]) {
            NSMutableArray *rows = [self.grid[@"rows"] mutableCopy]; [rows removeObject:@"row-49999"];
            self.grid[@"rows"] = rows; self.grid[@"order"] = @([self.grid[@"order"] integerValue] + 1); [self geometry]; self.revision++;
        }
    }
    NSMutableArray *pages = [NSMutableArray new];
    // Simulate a bounded provider. Requests observed on one cycle arrive on
    // later cycles; AX reads cannot synthesize their own values synchronously.
    for (NSUInteger n = 0; n < 2 && self.requests.count; n++) {
        NSDictionary *request = self.requests.firstObject; [self.requests removeObjectAtIndex:0];
        NSDictionary *page = [self page:request]; if (page) [pages addObject:page];
    }
    NSMutableDictionary *envelope = [@{@"snapshot": [self snapshot], @"gridPages": pages} mutableCopy];
    if (self.receipt) envelope[@"receipt"] = self.receipt;
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    NSString *json = AXBExchange(301, 1, (__bridge void *)self.window, self.session, [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]);
    NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![reply[@"ok"] boolValue]) { NSLog(@"Grid fixture error: %@", reply); abort(); }
    self.receipt = nil;
    NSDictionary *action = reply[@"action"];
    if (action) {
        NSDictionary *target = action[@"value"];
        NSUInteger row = [self.grid[@"rows"] indexOfObject:target[@"row"]], column = [[self.grid[@"columns"] valueForKey:@"id"] indexOfObject:target[@"column"]];
        BOOL allowed = [action[@"operation"] isEqual:@"gridReveal"] && [target[@"generation"] isEqual:self.grid[@"generation"]] && row != NSNotFound && column != NSNotFound;
        if (allowed) { self.firstRow = row; self.firstColumn = column; [self geometry]; self.revision++; }
        self.receipt = @{@"id": action[@"id"], @"status": allowed ? @"completed" : @"rejected", @"message": allowed ? @"Cell is visible" : @"Unavailable cell"};
    }
    [self.requests addObjectsFromArray:reply[@"gridRequests"] ?: @[]];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *state = @{@"pid": @(NSProcessInfo.processInfo.processIdentifier), @"session": self.session, @"command": @(self.command), @"pages": @(self.pages), @"revision": @(self.revision), @"generation": self.grid[@"generation"], @"firstRow": @(self.firstRow), @"firstColumn": @(self.firstColumn)};
        [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:[self.directory stringByAppendingPathComponent:@"state.json"] atomically:YES];
    });
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; [NSApp finishLaunching];
        GridFixture *fixture = [GridFixture new]; fixture.directory = @(argv[1]); fixture.revision = 1;
        fixture.requests = [NSMutableArray new];
        NSMutableArray *rows = [NSMutableArray new], *columns = [NSMutableArray new];
        for (NSUInteger row = 0; row < 50000; row++) [rows addObject:[NSString stringWithFormat:@"row-%05lu", row]];
        for (NSUInteger c = 0; c < 24; c++) [columns addObject:@{@"id": [NSString stringWithFormat:@"column-%lu", c], @"label": [NSString stringWithFormat:@"Column %lu", c + 1], @"enabled": @YES, @"editable": @NO}];
        fixture.grid = [@{@"generation": NSUUID.UUID.UUIDString, @"order": @1, @"rows": rows, @"columns": columns, @"selected": @[], @"actions": @{@"select": @NO, @"edit": @NO, @"reveal": @YES}} mutableCopy];
        [fixture geometry];
        fixture.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 160, 760, 420) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        fixture.session = [NSJSONSerialization JSONObjectWithData:[AXBOpen(301, 1, (__bridge void *)fixture.window) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil][@"session"];
        fixture.window.releasedWhenClosed = NO; fixture.window.title = @"AXB complete logical grid fixture";
        [fixture.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { (void)timer; [fixture tick]; }];
        [NSApp run];
    }
    return 0;
}
