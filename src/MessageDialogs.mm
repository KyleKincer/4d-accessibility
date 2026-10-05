#import "MessageDialogs.h"
#import "DrawnText.h"
#import "BridgePrivate.h"
#import <QuartzCore/QuartzCore.h>
#include <initializer_list>

// Object names of 4D's standard message forms on 4D 20.8. Any other object means the
// window is not one of them, and it is left untouched.
static NSSet<NSString *> *MessageNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"main", @"comment", @"additional", @"ok", @"cancel", @"box", @"icon", @"badge"]]; });
    return names;
}

@class AXBMessageView;

@interface AXBMessageElement : NSAccessibilityElement
@property(nonatomic, weak) AXBMessageView *owner;
@property(nonatomic, weak) CALayer *layer;
@property(nonatomic, copy) NSString *objectName;
@property(nonatomic, copy) NSString *publishedText;
// The Request field's caret as last inferred from its edits; 4D starts with the answer selected.
@property(nonatomic) NSRange selection;
- (NSRange)clampedSelection;
- (void)publishEditFrom:(NSString *)previous to:(NSString *)text;
@end

@interface AXBMessageView : NSView
@property(nonatomic, weak) NSView *formView;
@property(nonatomic, weak) CALayer *formLayer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBMessageElement *> *elements;
@property(nonatomic, copy) NSArray<NSString *> *order;
@property(nonatomic, weak) AXBMessageElement *placedFocus;
@property(nonatomic) NSTimeInterval publishedAt;
- (void)whenSettled:(dispatch_block_t)block;
- (BOOL)update;
- (NSRect)screenFrameForLayer:(CALayer *)layer;
- (BOOL)clickLayer:(CALayer *)layer;
- (BOOL)typeText:(NSString *)text;
- (NSString *)textForLayer:(CALayer *)layer;
@end

static NSString *Joined(NSArray<NSString *> *texts) {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *text in texts) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length && ![parts containsObject:trimmed]) [parts addObject:trimmed];
    }
    return [parts componentsJoinedByString:@" "];
}

@implementation AXBMessageElement
- (NSRect)accessibilityFrame { CALayer *layer = self.layer; return layer ? [self.owner screenFrameForLayer:layer] : NSZeroRect; }
- (id)accessibilityParent { return self.owner; }
- (NSString *)accessibilityIdentifier { return [@"axb/message/" stringByAppendingString:self.objectName]; }
- (BOOL)isAccessibilityElement { return self.layer != nil && !self.layer.hidden; }
- (BOOL)isAccessibilityEnabled { return YES; }
- (NSString *)accessibilityLabel {
    if ([self.accessibilityRole isEqual:NSAccessibilityButtonRole]) return [self.owner textForLayer:self.layer];
    return nil;
}
- (id)accessibilityValue {
    if ([self.accessibilityRole isEqual:NSAccessibilityButtonRole]) return nil;
    return [self.owner textForLayer:self.layer] ?: @"";
}
- (BOOL)accessibilityPerformPress {
    if (![self.accessibilityRole isEqual:NSAccessibilityButtonRole]) return NO;
    return [self.owner clickLayer:self.layer];
}
- (void)setAccessibilityValue:(id)value {
    if ([self.objectName isEqual:@"box"] && [value isKindOfClass:NSString.class]) (void)[self.owner typeText:value];
}
- (NSInteger)accessibilityNumberOfCharacters { return (NSInteger)[self.accessibilityValue length]; }
- (NSRange)accessibilitySelectedTextRange { return [self.objectName isEqual:@"box"] ? [self clampedSelection] : NSMakeRange(0, 0); }
- (NSString *)accessibilitySelectedText {
    NSString *value = self.accessibilityValue;
    return [self.objectName isEqual:@"box"] ? [value substringWithRange:[self clampedSelection]] : nil;
}
- (BOOL)isAccessibilityFocused { return NSApp.accessibilityApplicationFocusedUIElement == self && self.owner.window.isKeyWindow; }
// The Request field is a single line.
- (NSRange)accessibilityVisibleCharacterRange { return NSMakeRange(0, [self.accessibilityValue length]); }
- (NSInteger)accessibilityInsertionPointLineNumber { return 0; }
- (NSInteger)accessibilityLineForIndex:(NSInteger)index { return index >= 0 && (NSUInteger)index <= [self.accessibilityValue length] ? 0 : NSNotFound; }
- (NSRange)accessibilityRangeForLine:(NSInteger)line { return line == 0 ? NSMakeRange(0, [self.accessibilityValue length]) : NSMakeRange(NSNotFound, 0); }
- (NSString *)accessibilityStringForRange:(NSRange)range {
    NSString *value = self.accessibilityValue;
    return range.location <= value.length && range.length <= value.length - range.location ? [value substringWithRange:range] : nil;
}
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    NSString *text = [self accessibilityStringForRange:range];
    return text ? [[NSAttributedString alloc] initWithString:text] : nil;
}
- (NSRange)clampedSelection {
    NSUInteger length = [self.accessibilityValue length];
    NSUInteger location = MIN(self.selection.location, length);
    return NSMakeRange(location, MIN(self.selection.length, length - location));
}
// Announce a Request edit as typing, the way AppKit and WebKit fields describe it, so
// VoiceOver echoes the characters. The caret follows the end of the changed text.
- (void)publishEditFrom:(NSString *)previous to:(NSString *)text {
    NSUInteger prefix = 0, suffix = 0;
    while (prefix < previous.length && prefix < text.length && [previous characterAtIndex:prefix] == [text characterAtIndex:prefix]) prefix++;
    while (suffix < previous.length - prefix && suffix < text.length - prefix &&
           [previous characterAtIndex:previous.length - 1 - suffix] == [text characterAtIndex:text.length - 1 - suffix]) suffix++;
    NSString *inserted = [text substringWithRange:NSMakeRange(prefix, text.length - prefix - suffix)];
    NSString *removed = [previous substringWithRange:NSMakeRange(prefix, previous.length - prefix - suffix)];
    self.selection = NSMakeRange(prefix + inserted.length, 0);
    NSMutableArray *changes = [NSMutableArray new];
    if (removed.length) [changes addObject:@{@"AXTextEditType": @1, @"AXTextChangeValue": removed}];
    if (inserted.length) [changes addObject:@{@"AXTextEditType": @3, @"AXTextChangeValue": inserted}];
    NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityValueChangedNotification,
                                                @{@"AXTextStateChangeType": @1, @"AXTextChangeValues": changes, @"AXTextChangeElement": self});
    NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return [self.accessibilityRole isEqual:NSAccessibilityButtonRole];
    if (selector == @selector(setAccessibilityValue:)) return [self.objectName isEqual:@"box"] && self.isAccessibilityElement;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

static CALayer *FormContext(NSView *view) {
    for (CALayer *layer in view.layer.sublayers) if ([layer.name isEqual:@"formContext"]) return layer;
    return nil;
}

static NSMapTable<NSWindow *, AXBMessageView *> *Overlays;

static NSView *MessageFormView(NSWindow *window) {
    NSMutableArray<NSView *> *pending = window.contentView ? [NSMutableArray arrayWithObject:window.contentView] : [NSMutableArray new];
    NSView *form = nil;
    NSUInteger visited = 0;
    while (pending.count && visited++ < 64) {
        NSView *view = pending.firstObject; [pending removeObjectAtIndex:0];
        if ([view isKindOfClass:AXBWindowView.class]) return nil; // An integrated form owns its window.
        if (!form && FormContext(view)) form = view;
        [pending addObjectsFromArray:view.subviews];
    }
    return pending.count ? nil : form; // Too many views to rule out an integrated form.
}

// Return the application's focus to AppKit when it still names one of this window's elements.
static void ReleaseFocus(AXBMessageView *overlay) {
    id focused = NSApp.accessibilityApplicationFocusedUIElement;
    if (focused && [overlay.elements.allValues containsObject:focused]) NSApp.accessibilityApplicationFocusedUIElement = nil;
}

static void RemoveOverlay(NSWindow *window, AXBMessageView *overlay) {
    if (!overlay) return;
    ReleaseFocus(overlay);
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
}

static id KeyObserver, CloseObserver;

@implementation AXBMessageView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren {
    NSMutableArray *children = [NSMutableArray new];
    for (NSString *name in self.order) {
        AXBMessageElement *element = self.elements[name];
        if (element.isAccessibilityElement) [children addObject:element];
    }
    return children;
}
- (NSString *)textForLayer:(CALayer *)layer { return Joined(AXBDrawnTextForLayer(layer) ?: @[]); }
- (NSRect)screenFrameForLayer:(CALayer *)layer {
    NSView *view = self.formView;
    if (!view.window || !layer) return NSZeroRect;
    NSRect inView = [layer.superlayer convertRect:layer.frame toLayer:view.layer];
    if (view.layer.geometryFlipped != view.isFlipped) inView.origin.y = NSHeight(view.bounds) - NSMaxY(inView);
    return [view.window convertRectToScreen:[view convertRect:inView toView:nil]];
}
// 4D discards input that arrives before its modal loop has started, shortly after the
// window is drawn: an immediate press was lost in half of the trials, one 250 ms later
// in none. Hold input until the window has been published for twice that long, then
// deliver it through every run-loop mode, including 4D's own.
static const NSTimeInterval SettleInterval = 0.5;
- (void)whenSettled:(dispatch_block_t)block {
    NSTimeInterval wait = self.publishedAt + SettleInterval - NSProcessInfo.processInfo.systemUptime;
    if (wait <= 0) { block(); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFRunLoopRef main = CFRunLoopGetMain();
        CFArrayRef modes = CFRunLoopCopyAllModes(main);
        if (!modes) return;
        CFRunLoopPerformBlock(main, modes, block);
        CFRelease(modes);
        CFRunLoopWakeUp(main);
    });
}
- (BOOL)clickLayer:(CALayer *)layer {
    NSView *view = self.formView;
    NSWindow *window = view.window;
    if (!window || !layer || layer.hidden || !window.isVisible) return NO;
    __weak AXBMessageView *weakSelf = self;
    __weak CALayer *weakLayer = layer;
    [self whenSettled:^{
        AXBMessageView *strongSelf = weakSelf;
        CALayer *target = weakLayer;
        NSWindow *current = strongSelf.formView.window;
        if (!strongSelf || !target || target.hidden || !current.isVisible) return;
        NSRect frame = [strongSelf screenFrameForLayer:target];
        NSPoint center = [current convertPointFromScreen:NSMakePoint(NSMidX(frame), NSMidY(frame))];
        // Queue an ordinary click so 4D's own modal loop handles it, exactly as for the mouse.
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        for (NSEventType type : {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp}) {
            NSEvent *event = [NSEvent mouseEventWithType:type location:center modifierFlags:0 timestamp:now windowNumber:current.windowNumber
                                                 context:nil eventNumber:0 clickCount:1 pressure:type == NSEventTypeLeftMouseDown ? 1.0 : 0.0];
            if (event) [NSApp postEvent:event atStart:NO];
        }
    }];
    return YES;
}
- (BOOL)typeText:(NSString *)text {
    NSWindow *window = self.formView.window;
    if (!window.isVisible || !window.isKeyWindow) return NO;
    // The Request field owns keyboard focus. Select its text, then type each character as
    // an ordinary key event so 4D's own editor applies it. Line breaks would end entry.
    for (NSUInteger i = 0; i < text.length; i++)
        if ([NSCharacterSet.controlCharacterSet characterIsMember:[text characterAtIndex:i]]) return NO;
    NSString *answer = [text copy];
    __weak NSWindow *weakWindow = window;
    [self whenSettled:^{
        NSWindow *current = weakWindow;
        if (!current.isVisible || !current.isKeyWindow) return;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        void (^post)(NSString *, NSString *, NSEventModifierFlags, unsigned short) = ^(NSString *characters, NSString *plain, NSEventModifierFlags flags, unsigned short code) {
            for (NSEventType type : {NSEventTypeKeyDown, NSEventTypeKeyUp}) {
                NSEvent *event = [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:now windowNumber:current.windowNumber
                                                   context:nil characters:characters charactersIgnoringModifiers:plain isARepeat:NO keyCode:code];
                if (event) [NSApp postEvent:event atStart:NO];
            }
        };
        post(@"a", @"a", NSEventModifierFlagCommand, 0);
        [answer enumerateSubstringsInRange:NSMakeRange(0, answer.length) options:NSStringEnumerationByComposedCharacterSequences
                                usingBlock:^(NSString *character, NSRange r1, NSRange r2, BOOL *stop) { (void)r1; (void)r2; (void)stop; post(character, character, 0, 0); }];
        if (!answer.length) post(@"\x7f", @"\x7f", 0, 51);
    }];
    return YES;
}
- (BOOL)update {
    NSView *view = self.formView;
    CALayer *form = FormContext(view);
    if (!view.window || !form) return NO;
    NSMutableDictionary<NSString *, CALayer *> *layers = [NSMutableDictionary new];
    for (CALayer *layer in form.sublayers) {
        if (![MessageNames() containsObject:layer.name]) return NO;
        layers[layer.name] = layer;
    }
    if (!layers[@"main"] || !layers[@"ok"]) return NO;
    BOOL changed = NO;
    NSMutableArray *order = [NSMutableArray new];
    // Message text, then the Request field, then the buttons in reading order.
    NSDictionary *roles = @{@"comment": NSAccessibilityStaticTextRole, @"main": NSAccessibilityStaticTextRole, @"additional": NSAccessibilityStaticTextRole,
                            @"box": NSAccessibilityTextFieldRole, @"cancel": NSAccessibilityButtonRole, @"ok": NSAccessibilityButtonRole};
    for (NSString *name in @[@"main", @"comment", @"additional", @"box", @"cancel", @"ok"]) {
        CALayer *layer = layers[name];
        NSString *text = layer ? [self textForLayer:layer] : nil;
        AXBMessageElement *element = self.elements[name];
        // An empty Request answer is still a field; other objects without text are not shown.
        if (!layer || layer.hidden || (!text.length && ![name isEqual:@"box"])) {
            if (element) {
                if (NSApp.accessibilityApplicationFocusedUIElement == element) NSApp.accessibilityApplicationFocusedUIElement = nil;
                [self.elements removeObjectForKey:name];
                NSAccessibilityPostNotification(element, NSAccessibilityUIElementDestroyedNotification);
                changed = YES;
            }
            continue;
        }
        if (!element) {
            element = [AXBMessageElement new];
            element.owner = self; element.layer = layer; element.objectName = name;
            element.accessibilityRole = roles[name];
            element.publishedText = text;
            element.selection = NSMakeRange(0, text.length);
            self.elements[name] = element;
            changed = YES;
            [order addObject:name];
            continue;
        }
        // 4D can replace an object's layer while redrawing it, as the Request field does on
        // each keystroke. The object keeps its element, so assistive focus and echo survive.
        element.layer = layer;
        if (![element.publishedText isEqual:text]) {
            NSString *previous = element.publishedText;
            element.publishedText = text;
            if ([name isEqual:@"box"]) [element publishEditFrom:previous to:text];
            else NSAccessibilityPostNotification(element, [roles[name] isEqual:NSAccessibilityButtonRole] ? NSAccessibilityTitleChangedNotification : NSAccessibilityValueChangedNotification);
        }
        [order addObject:name];
    }
    if (![order isEqual:self.order]) { self.order = order; changed = YES; }
    if (changed) NSAccessibilityPostNotification(view.window, NSAccessibilityLayoutChangedNotification);
    return self.order.count > 0;
}
@end

BOOL AXBMessagesRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBMessageView *overlay = [Overlays objectForKey:window];
    NSView *view = MessageFormView(window);
    if (!view) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBMessageView alloc] initWithFrame:view.bounds];
        overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        overlay.formView = view; overlay.formLayer = FormContext(view);
        overlay.elements = [NSMutableDictionary new]; overlay.order = @[];
        overlay.publishedAt = NSProcessInfo.processInfo.systemUptime;
        created = YES;
    }
    if (![overlay update]) {
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
    AXBMessageElement *focus = overlay.elements[@"box"] ?: overlay.elements[@"ok"];
    AXBMessageElement *placed = overlay.placedFocus;
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
        NSView *view = window.isVisible ? MessageFormView(window) : nil;
        if (view && FormContext(view) == form) return window;
    }
    return nil;
}

static void ObserveWindows(void) {
    if (KeyObserver) return;
    KeyObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil
                                                              usingBlock:^(NSNotification *note) { AXBMessagesRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
}

void AXBMessagesInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(MessageNames(), ^(CALayer *layer) {
        if (![layer.superlayer.name isEqual:@"formContext"]) return;
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBMessagesRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBMessagesShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(nil, nil);
    if (KeyObserver) [NSNotificationCenter.defaultCenter removeObserver:KeyObserver];
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    KeyObserver = CloseObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBMessagesEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
