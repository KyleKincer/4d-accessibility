#import "MessageDialogs.h"
#import "InternalForms.h"
#import "DrawnText.h"
#import "BridgePrivate.h"
#import <QuartzCore/QuartzCore.h>

// Object names of 4D's standard message forms on 4D 20.8. Any other object means the
// window is not one of them, and it is left untouched.
static NSSet<NSString *> *MessageNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"main", @"comment", @"additional", @"ok", @"cancel", @"box", @"icon", @"badge"]]; });
    return names;
}

static NSMapTable<NSWindow *, AXBInternalFormOverlay *> *Overlays;

static void RemoveOverlay(NSWindow *window, AXBInternalFormOverlay *overlay) {
    if (!overlay) return;
    [overlay releaseFocus];
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
}

// The message text, then the Request field, then the buttons in reading order; nil
// when any object is not a standard message object or the message has no text or OK.
static NSArray<NSDictionary *> *MessageEntries(CALayer *form) {
    NSMutableDictionary<NSString *, CALayer *> *layers = [NSMutableDictionary new];
    for (CALayer *layer in form.sublayers) {
        if (![MessageNames() containsObject:layer.name]) return nil;
        layers[layer.name] = layer;
    }
    if (!layers[@"main"] || !layers[@"ok"]) return nil;
    NSMutableArray *entries = [NSMutableArray new];
    for (NSString *name in @[@"main", @"comment", @"additional"])
        if (layers[name]) [entries addObject:@{@"key": name, @"layer": layers[name], @"role": NSAccessibilityStaticTextRole}];
    if (layers[@"box"]) [entries addObject:@{@"key": @"box", @"layer": layers[@"box"], @"role": NSAccessibilityTextFieldRole, @"editable": @YES, @"caret": @YES}];
    for (NSString *name in @[@"cancel", @"ok"])
        if (layers[name]) [entries addObject:@{@"key": name, @"layer": layers[name], @"role": NSAccessibilityButtonRole}];
    return entries;
}

static id KeyObserver, CloseObserver, UpdateObserver;

BOOL AXBMessagesRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    NSArray *entries = view ? MessageEntries(AXBInternalFormContext(view)) : nil;
    if (!entries) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:@"axb/message/"];
        created = YES;
    }
    if (![overlay updateWithEntries:entries]) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    if (created) {
        [view addSubview:overlay];
        [Overlays setObject:overlay forKey:window];
    }
    // Keyboard focus starts on the Request field, or on the default button, once the
    // message is the key window. Its text can be drawn before it becomes key, and the
    // field can be drawn after the buttons; it then takes the focus placed on the button.
    AXBInternalFormElement *focus = overlay.elements[@"box"] ?: overlay.elements[@"ok"];
    AXBInternalFormElement *placed = overlay.placedFocus;
    BOOL replace = placed && placed != focus && NSApp.accessibilityApplicationFocusedUIElement == placed;
    if ((!placed || replace) && focus && window.isKeyWindow) {
        overlay.placedFocus = focus;
        NSApp.accessibilityApplicationFocusedUIElement = focus;
        NSAccessibilityPostNotification(focus, NSAccessibilityFocusedUIElementChangedNotification);
    }
    return YES;
}

// 4D's root layers are not necessarily delegated to their views, so find the window
// through the form layer it draws in: a published overlay first, then any open window.
static NSWindow *WindowForLayer(CALayer *layer) {
    CALayer *form = layer.superlayer;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) if ([Overlays objectForKey:window].formLayer == form) return window;
    for (NSWindow *window in NSApp.windows) {
        NSView *view = window.isVisible ? AXBInternalFormView(window) : nil;
        if (view && AXBInternalFormContext(view) == form) return window;
    }
    return nil;
}

static void ObserveWindows(void) {
    if (KeyObserver) return;
    KeyObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil
                                                              usingBlock:^(NSNotification *note) { AXBMessagesRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
    // A caret move changes no drawn text; check the Request field after each window update.
    UpdateObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        AXBInternalFormOverlay *view = [Overlays objectForKey:note.object];
        if (view && ((NSWindow *)note.object).isKeyWindow) [view.elements[@"box"] noticeCaret];
    }];
}

void AXBMessagesInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(@"messages", MessageNames(), ^(CALayer *layer) {
        if (![layer.superlayer.name isEqual:@"formContext"]) return;
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBMessagesRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBMessagesShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(@"messages", nil, nil);
    if (KeyObserver) [NSNotificationCenter.defaultCenter removeObserver:KeyObserver];
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    if (UpdateObserver) [NSNotificationCenter.defaultCenter removeObserver:UpdateObserver];
    KeyObserver = CloseObserver = UpdateObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBMessagesEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
