// Owned AppKit window for the focus-replacement VoiceOver case. No external application is controlled.
// A host mode change makes the focused read-only note and its sibling fields editable in one refresh.
#import <Cocoa/Cocoa.h>
#import "Bridge.h"
#import "BridgePrivate.h"

static NSString *Directory;
static NSWindow *Window;
static NSString *Session;
static NSMutableDictionary *Snapshot;
static NSInteger Handled;

static void Exchange(void) {
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:@{@"snapshot": Snapshot} options:0 error:nil];
    AXBExchange(9041, 1, (__bridge void *)Window, Session, [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]);
}

static void Publish(BOOL editable) {
    NSMutableArray *nodes = [NSMutableArray new];
    [nodes addObject:@{@"id": @"search", @"role": @"textfield", @"label": @"Quick search", @"value": @"", @"editable": @YES,
                       @"focusable": @YES, @"focused": @NO, @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @20, @200, @24]}];
    [nodes addObject:@{@"id": @"note", @"role": @"textfield", @"label": @"Latest note", @"value": @"First line\rsecond line",
                       @"multiline": @YES, @"selection": @[@22, @0], @"editable": @(editable), @"focusable": @YES, @"focused": @YES,
                       @"enabled": @YES, @"visible": @YES, @"frame": @[@20, @60, @360, @60]}];
    for (NSInteger row = 1; row <= 40; row++)
        [nodes addObject:@{@"id": [NSString stringWithFormat:@"row%ld", (long)row], @"role": @"textfield",
                           @"label": [NSString stringWithFormat:@"Earlier note %ld", (long)row], @"value": @"Earlier", @"editable": @(editable),
                           @"focusable": @YES, @"focused": @NO, @"enabled": @YES, @"visible": @YES,
                           @"frame": @[@20, @(130 + row * 2), @360, @2]}];
    Snapshot[@"nodes"] = nodes;
    Snapshot[@"revision"] = @([Snapshot[@"revision"] integerValue] + 1);
    Exchange();
}

static void WriteState(void) {
    NSDictionary *state = @{@"pid": @(NSProcessInfo.processInfo.processIdentifier), @"command": @(Handled),
                            @"key": @(Window.isKeyWindow), @"active": @(NSApp.isActive)};
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    NSString *temporary = [Directory stringByAppendingPathComponent:@"state.tmp"];
    [bytes writeToFile:temporary atomically:NO];
    rename(temporary.fileSystemRepresentation, [Directory stringByAppendingPathComponent:@"state.json"].fileSystemRepresentation);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 2;
        Directory = @(argv[1]);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        Window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 420, 260)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        Window.releasedWhenClosed = NO;
        Window.title = @"AXB focus replacement fixture";
        [NSApp activateIgnoringOtherApps:YES];
        [Window makeKeyAndOrderFront:nil];
        NSString *reply = AXBOpen(9041, 1, (__bridge void *)Window);
        Session = [NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil][@"session"];
        Snapshot = [@{@"version": @1, @"revision": @0, @"label": @"Customers", @"enabled": @YES} mutableCopy];
        Publish(argc > 2 && !strcmp(argv[2], "--editable"));
        WriteState();
        NSString *commandPath = [Directory stringByAppendingPathComponent:@"command.json"];
        while (true) {
            @autoreleasepool {
                NSEvent *event;
                while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                                                      inMode:NSDefaultRunLoopMode dequeue:YES]))
                    [NSApp sendEvent:event];
                Exchange();
                NSData *bytes = [NSData dataWithContentsOfFile:commandPath];
                NSDictionary *command = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
                if (command && [command[@"id"] integerValue] > Handled) {
                    NSString *operation = command[@"operation"];
                    if ([operation isEqual:@"quit"]) break;
                    if ([operation isEqual:@"editable"]) Publish(YES);
                    if ([operation isEqual:@"readonly"]) Publish(NO);
                    Handled = [command[@"id"] integerValue];
                }
                WriteState();
            }
        }
        [Window close];
    }
    return 0;
}
