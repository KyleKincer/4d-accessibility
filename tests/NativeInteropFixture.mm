// Disposable AppKit/WebKit host for external AX interoperability tests.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "Bridge.h"

@interface Fixture : NSObject <WKNavigationDelegate>
@property NSWindow *window;
@property NSTextField *firstEditor;
@property NSTextField *secondEditor;
@property NSTextField *bridgeEditor;
@property NSButton *button;
@property NSButton *lateButton;
@property WKWebView *web;
@property NSString *directory;
@property NSString *session;
@property NSInteger command;
@property NSInteger revision;
@property NSInteger presses;
@property BOOL attached;
@property BOOL proxyFocused;
@property BOOL ready;
- (void)tick;
@end

@implementation Fixture
- (void)pressed:(id)sender { (void)sender; self.presses++; }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView; (void)navigation; self.ready = YES;
}
- (void)publish {
    NSDictionary *button = @{@"id": @"proxy", @"role": @"button", @"label": @"Bridge action", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@440, @20, @150, @32]};
    NSDictionary *editor = @{@"id": @"editor", @"role": @"textfield", @"label": @"Bridge editor", @"value": self.bridgeEditor.stringValue, @"enabled": @YES, @"visible": @YES, @"focusable": @YES, @"focused": @(self.proxyFocused), @"editable": @YES, @"selection": @[@(self.bridgeEditor.stringValue.length), @0], @"frame": @[@440, @68, @180, @28]};
    NSDictionary *table = @{@"id": @"table", @"role": @"table", @"label": @"Bridge table", @"value": @"", @"enabled": @YES, @"visible": @YES, @"frame": @[@440, @130, @180, @80]};
    NSDictionary *row = @{@"id": @"row", @"parent": @"table", @"role": @"row", @"label": @"Bridge row", @"value": @"Row summary", @"enabled": @YES, @"visible": @YES, @"index": @0, @"selected": @NO, @"frame": @[@440, @130, @180, @28]};
    // Deliberately put the parent last: hierarchy, not snapshot order, owns hits.
    NSDictionary *snapshot = @{@"version": @1, @"revision": @(++self.revision), @"label": @"Interop bridge", @"enabled": @YES, @"nodes": @[button, editor, row, table]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"snapshot": snapshot} options:0 error:nil];
    NSString *reply = AXBExchange(101, 1, (__bridge void *)self.window, self.session, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    if (![[NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil][@"ok"] boolValue]) { NSLog(@"Invalid fixture snapshot: %@", reply); abort(); }
}
- (void)writeState:(NSInteger)command {
    [self.web evaluateJavaScript:@"document.querySelector('#count').textContent" completionHandler:^(id value, NSError *error) {
        (void)error;
        NSDictionary *state = @{@"command": @(command), @"pid": @(NSProcessInfo.processInfo.processIdentifier), @"ready": @(self.ready), @"presses": @(self.presses), @"webPresses": value ?: @"", @"first": self.firstEditor.stringValue, @"second": self.secondEditor.stringValue, @"session": self.session};
        NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];
        [data writeToFile:[self.directory stringByAppendingPathComponent:@"state.json"] atomically:YES];
    }];
}
- (void)tick {
    NSData *data = [NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"command.json"]];
    NSDictionary *request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSInteger command = [request[@"id"] integerValue];
    if (!request || command <= self.command || !self.ready) return;
    self.command = command;
    NSString *operation = request[@"operation"];
    if ([operation isEqual:@"attach"]) { self.attached = YES; [self publish]; }
    if ([operation isEqual:@"refresh"]) [self publish];
    if ([operation isEqual:@"focusProxy"]) {
        [self.window makeFirstResponder:self.bridgeEditor]; self.proxyFocused = YES; [self publish];
    }
    if ([operation isEqual:@"nativeFocus"]) { self.proxyFocused = NO; [self publish]; }
    if ([operation isEqual:@"editProxy"]) { self.bridgeEditor.stringValue = @"Updated proxy value"; [self publish]; }
    if ([operation isEqual:@"lateChild"]) {
        self.lateButton = [NSButton buttonWithTitle:@"Late native action" target:self action:@selector(pressed:)];
        self.lateButton.frame = NSMakeRect(220, 520, 170, 32);
        self.lateButton.accessibilityIdentifier = @"native.late";
        [self.window.contentView addSubview:self.lateButton];
    }
    if ([operation isEqual:@"move"]) [self.window setFrameOrigin:NSMakePoint(250, 180)];
    if ([operation isEqual:@"detach"]) { AXBDetach(self.session); self.attached = NO; }
    if ([operation isEqual:@"quit"]) { AXBShutdown(); [NSApp terminate:nil]; return; }
    // Publish after queued provider refreshes have committed.
    dispatch_async(dispatch_get_main_queue(), ^{ [self writeState:command]; });
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        Fixture *fixture = [Fixture new];
        fixture.directory = @(argv[1]);
        fixture.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 680, 580) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        fixture.window.title = @"AXB native interoperability fixture";
        fixture.session = [NSJSONSerialization JSONObjectWithData:[AXBOpen(101, 1, (__bridge void *)fixture.window) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil][@"session"];
        fixture.window.releasedWhenClosed = NO;
        // Like a drawn 4D form, this physical view handles hits but has no
        // native accessibility elements for its rendered controls.
        NSView *canvas = [[NSView alloc] initWithFrame:NSMakeRect(430, 100, 240, 470)];
        [fixture.window.contentView addSubview:canvas];
        fixture.button = [NSButton buttonWithTitle:@"Native action" target:fixture action:@selector(pressed:)];
        fixture.button.frame = NSMakeRect(20, 520, 170, 32); fixture.button.accessibilityIdentifier = @"native.button";
        [fixture.window.contentView addSubview:fixture.button];
        NSArray *editors = @[[NSTextField textFieldWithString:@"First native value"], [NSTextField textFieldWithString:@"Second native value"], [NSTextField textFieldWithString:@"Proxy value"]];
        for (NSUInteger index = 0; index < editors.count; index++) {
            NSTextField *editor = editors[index];
            editor.frame = NSMakeRect(20 + 210 * index, 484, 180, 28);
            editor.accessibilityIdentifier = @[@"native.first", @"native.second", @"native.backing"][index];
            if (index == 2) {
                editor.frame = [canvas convertRect:editor.frame fromView:fixture.window.contentView];
                [canvas addSubview:editor];
            } else [fixture.window.contentView addSubview:editor];
        }
        fixture.firstEditor = editors[0]; fixture.secondEditor = editors[1]; fixture.bridgeEditor = editors[2];
        fixture.web = [[WKWebView alloc] initWithFrame:NSMakeRect(20, 100, 380, 330)];
        fixture.web.navigationDelegate = fixture;
        [fixture.window.contentView addSubview:fixture.web];
        [fixture.web loadHTMLString:@"<!doctype html><html lang='en'><head><title>Native web fixture</title></head><body><button id='action' onclick=\"document.querySelector('#count').textContent=Number(document.querySelector('#count').textContent)+1\">Web action</button><p>Web presses: <span id='count'>0</span></p><label>Web name <input value='Web value'></label></body></html>" baseURL:nil];
        [fixture.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { (void)timer; [fixture tick]; }];
        [NSApp run];
    }
    return 0;
}
