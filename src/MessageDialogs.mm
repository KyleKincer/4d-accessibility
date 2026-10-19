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

// Object names of 4D's error window on 4D 20.8, which shows a method's error when no error
// handler takes it: its message, the failing line, Details and the buttons that end it.
static NSSet<NSString *> *ErrorNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"_icon", @"application.icon", @"Texte1", @"Text", @"MES_C_mess1", @"Expand_Btn", @"Expand_Label",
        @"bEdit", @"bTrace", @"bContinue", @"bAbort", @"Plus.Error.bSave", @"Plus.Error.bCopy", @"Plus.Error.List", @"Plus.Error.process"]]; });
    return names;
}
static NSSet<NSString *> *ObservedNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [MessageNames() setByAddingObjectsFromSet:ErrorNames()]; });
    return names;
}
// A compiled application cannot be edited or traced, and 4D draws those two buttons dimmed.
static BOOL HostCompiled;
void AXBMessagesSetCompiled(BOOL compiled) { HostCompiled = compiled; }

static NSMapTable<NSWindow *, AXBInternalFormOverlay *> *Overlays;
// Error windows whose error has been announced.
static NSHashTable<NSWindow *> *Announced;

// 4D's modal loops do not drain the main dispatch queue: run the block after a delay in every
// mode the main run loop knows, including 4D's own.
static void AfterDelay(NSTimeInterval delay, dispatch_block_t block) {
    CFRunLoopRef main = CFRunLoopGetMain();
    CFArrayRef modes = CFRunLoopCopyAllModes(main);
    if (!modes) return;
    CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0, ^(CFRunLoopTimerRef fired) {
        CFRunLoopTimerInvalidate(fired);
        block();
    });
    for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) CFRunLoopAddTimer(main, timer, (CFStringRef)CFArrayGetValueAtIndex(modes, i));
    CFRelease(timer);
    CFRelease(modes);
}

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

// A layer's drawn strings without the line breaks 4D draws around them, skipping those drawn
// highest when the layer draws several lines, as a list draws its column titles.
static NSString *DrawnText(CALayer *layer, NSString *separator, BOOL skipTitles) {
    NSArray<NSString *> *texts = AXBDrawnTextForLayer(layer);
    NSArray<NSValue *> *origins = AXBDrawnTextOriginsForLayer(layer);
    CGFloat top = INFINITY, bottom = -INFINITY;
    if (skipTitles && origins.count == texts.count)
        for (NSValue *origin in origins) { top = MIN(top, origin.pointValue.y); bottom = MAX(bottom, origin.pointValue.y); }
    NSMutableArray *parts = [NSMutableArray new];
    for (NSUInteger i = 0; i < texts.count; i++) {
        if (skipTitles && bottom > top && origins.count == texts.count && origins[i].pointValue.y == top) continue;
        NSString *text = [texts[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) [parts addObject:text];
    }
    return [parts componentsJoinedByString:separator];
}

// The message, its description and the failing line, Details, and, while Details is open, the
// process and the list of errors with their buttons; then the buttons that end the error, in
// reading order. Nil when any object is not one of the error window's, or it has no message or
// Abort. The parts of Details lie outside the form while it is closed.
static NSArray<NSDictionary *> *ErrorEntries(CALayer *form) {
    NSMutableDictionary<NSString *, CALayer *> *layers = [NSMutableDictionary new];
    for (CALayer *layer in form.sublayers) {
        if (![ErrorNames() containsObject:layer.name]) return nil;
        layers[layer.name] = layer;
    }
    if (!layers[@"Texte1"] || !layers[@"bAbort"]) return nil;
    auto shown = [&](NSString *name) { CALayer *layer = layers[name]; return layer && NSContainsRect(NSInsetRect(form.bounds, -1, -1), layer.frame); };
    NSMutableArray *entries = [NSMutableArray new];
    auto text = [&](NSString *key, NSString *name, NSString *value) {
        if (shown(name) && value.length) [entries addObject:@{@"key": key, @"layer": layers[name], @"role": NSAccessibilityStaticTextRole, @"text": value}];
    };
    text(@"message", @"Texte1", DrawnText(layers[@"Texte1"], @" ", NO));
    text(@"description", @"Text", DrawnText(layers[@"Text"], @" ", NO));
    text(@"line", @"MES_C_mess1", DrawnText(layers[@"MES_C_mess1"], @"\n", NO));
    BOOL expanded = shown(@"Plus.Error.List");
    if (shown(@"Expand_Btn")) {
        NSString *label = layers[@"Expand_Label"] ? DrawnText(layers[@"Expand_Label"], @" ", NO) : @"";
        [entries addObject:@{@"key": @"details", @"layer": layers[@"Expand_Btn"], @"role": NSAccessibilityDisclosureTriangleRole,
                             @"label": label.length ? label : @"Details", @"checked": @(expanded)}];
    }
    if (expanded) {
        text(@"process", @"Plus.Error.process", DrawnText(layers[@"Plus.Error.process"], @" ", NO));
        text(@"errors", @"Plus.Error.List", DrawnText(layers[@"Plus.Error.List"], @", ", YES));
        for (NSString *name in @[@"Plus.Error.bSave", @"Plus.Error.bCopy"])
            if (shown(name)) [entries addObject:@{@"key": [name substringFromIndex:@"Plus.Error.".length], @"layer": layers[name], @"role": NSAccessibilityButtonRole}];
    }
    // While Option is held, 4D draws Continue as Ignore. A VoiceOver user holds it to move, and a
    // press is an unmodified click, so Continue keeps the title it has without Option.
    static NSMapTable<CALayer *, NSString *> *ContinueTitles;
    if (!ContinueTitles) ContinueTitles = [NSMapTable weakToStrongObjectsMapTable];
    NSString *title = layers[@"bContinue"] ? DrawnText(layers[@"bContinue"], @" ", NO) : nil;
    if (title.length && !(CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState) & kCGEventFlagMaskAlternate)) [ContinueTitles setObject:title forKey:form];
    for (NSString *name in @[@"bEdit", @"bTrace", @"bContinue", @"bAbort"]) {
        if (!shown(name)) continue;
        NSMutableDictionary *entry = [@{@"key": name, @"layer": layers[name], @"role": NSAccessibilityButtonRole,
                                        @"disabled": @(HostCompiled && [@[@"bEdit", @"bTrace"] containsObject:name])} mutableCopy];
        if ([name isEqual:@"bContinue"] && [ContinueTitles objectForKey:form]) entry[@"label"] = [ContinueTitles objectForKey:form];
        [entries addObject:entry];
    }
    return entries;
}

static id KeyObserver, CloseObserver, UpdateObserver;

BOOL AXBMessagesRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    CALayer *form = view ? AXBInternalFormContext(view) : nil;
    NSArray *entries = form ? MessageEntries(form) : nil;
    NSString *prefix = @"axb/message/";
    if (!entries && form && (entries = ErrorEntries(form))) prefix = @"axb/error/";
    if (!entries) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view || ![overlay.identifierPrefix isEqual:prefix]) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:prefix];
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
    AXBInternalFormElement *focus = overlay.elements[@"box"] ?: overlay.elements[@"ok"] ?: overlay.elements[@"bAbort"];
    AXBInternalFormElement *placed = overlay.placedFocus;
    BOOL replace = placed && placed != focus && NSApp.accessibilityApplicationFocusedUIElement == placed;
    if ((!placed || replace) && focus && window.isKeyWindow) {
        overlay.placedFocus = focus;
        NSApp.accessibilityApplicationFocusedUIElement = focus;
        NSAccessibilityPostNotification(focus, NSAccessibilityFocusedUIElementChangedNotification);
    }
    // VoiceOver reads a new dialog's text only if the text is there as it arrives, and 4D can draw
    // the error's text after that. The error is what the user must hear: it is announced once,
    // after VoiceOver has named the dialog, even if VoiceOver has read it too.
    AXBInternalFormElement *message = overlay.elements[@"message"], *description = overlay.elements[@"description"];
    if ([prefix isEqual:@"axb/error/"] && window.isKeyWindow && message && description && ![Announced containsObject:window]) {
        if (!Announced) Announced = [NSHashTable weakObjectsHashTable];
        [Announced addObject:window];
        NSString *text = [NSString stringWithFormat:@"%@ %@", message.currentText, description.currentText];
        __weak NSWindow *weakWindow = window;
        AfterDelay(1.2, ^{
            if (weakWindow.isVisible)
                NSAccessibilityPostNotificationWithUserInfo(weakWindow, NSAccessibilityAnnouncementRequestedNotification,
                    @{NSAccessibilityAnnouncementKey: text, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh)});
        });
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
                                                              usingBlock:^(NSNotification *note) {
        AXBMessagesRefreshWindow(note.object);
        // 4D keeps its own modifier state and can miss a release, as when VoiceOver's keys are let
        // go while the window before closes or before this one is key; it then draws an error's
        // Continue as Ignore. Give a newly key error window the keyboard's actual modifiers, and
        // again once keys held as it opened are likely let go.
        AXBInternalFormOverlay *overlay = [Overlays objectForKey:note.object];
        if ([overlay.identifierPrefix isEqual:@"axb/error/"]) {
            __weak NSWindow *weakWindow = note.object;
            dispatch_block_t sync = ^{
                NSWindow *window = weakWindow;
                if (!window.isKeyWindow) return;
                NSEventModifierFlags held = NSEvent.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand);
                NSEvent *flags = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:held timestamp:NSProcessInfo.processInfo.systemUptime
                                              windowNumber:window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:58];
                if (flags) [NSApp postEvent:flags atStart:NO];
            };
            sync();
            AfterDelay(0.3, sync);
            AfterDelay(1.0, sync);
        }
    }];
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
    AXBDrawnTextSetObserver(@"messages", ObservedNames(), ^(CALayer *layer) {
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
