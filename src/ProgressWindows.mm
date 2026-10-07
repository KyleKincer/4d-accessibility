#import "ProgressWindows.h"
#import "MessageDialogs.h"
#import "DrawnText.h"
#import <QuartzCore/QuartzCore.h>
#include <initializer_list>

// Object names of the Progress component's progress form on 4D 20.8. A form context
// holding Message1 and ThermoProgress is one progress.
static NSSet<NSString *> *ProgressNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"Message1", @"Message2", @"ThermoProgress", @"StopButton", @"ProgressValue"]]; });
    return names;
}

static NSString *Joined(NSArray<NSString *> *texts) {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *text in texts) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length && ![parts containsObject:trimmed]) [parts addObject:trimmed];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *LayerText(CALayer *layer) { return layer ? Joined(AXBDrawnTextForLayer(layer) ?: @[]) : @""; }

static CALayer *Child(CALayer *context, NSString *name) {
    for (CALayer *layer in context.sublayers) if ([layer.name isEqual:name]) return layer;
    return nil;
}

// The progress as the component stores it: a fraction from 0 to 1, or -1 while it is
// indeterminate. 4D draws the stored number with the system's decimal separator.
static BOOL ProgressFraction(NSString *text, double *fraction) {
    NSString *plain = [[text stringByReplacingOccurrencesOfString:@"," withString:@"."] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:plain];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double value;
    if (!plain.length || ![scanner scanDouble:&value] || !scanner.isAtEnd) return NO;
    *fraction = value;
    return YES;
}

@class AXBProgressView;

@interface AXBProgressElement : NSAccessibilityElement
@property(nonatomic, weak) AXBProgressView *owner;
@property(nonatomic, weak) CALayer *layer;
// The title drawn above an indicator, which its frame includes so it reads first, as it is seen.
@property(nonatomic, weak) CALayer *titleLayer;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *label;
@property(nonatomic, strong) id value;
@end

@interface AXBProgressView : NSView
@property(nonatomic, weak) NSView *formView;
@property(nonatomic, weak) CALayer *formLayer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBProgressElement *> *elements;
@property(nonatomic, copy) NSArray<NSString *> *order;
- (BOOL)update;
- (NSRect)screenFrameForLayer:(CALayer *)layer;
- (BOOL)clickLayer:(CALayer *)layer;
@end

@implementation AXBProgressElement
- (NSRect)accessibilityFrame {
    CALayer *layer = self.layer, *title = self.titleLayer;
    if (!layer) return NSZeroRect;
    NSRect frame = [self.owner screenFrameForLayer:layer];
    return title && !title.hidden ? NSUnionRect(frame, [self.owner screenFrameForLayer:title]) : frame;
}
- (id)accessibilityParent { return self.owner; }
- (NSString *)accessibilityIdentifier { return self.identifier; }
- (BOOL)isAccessibilityElement { return self.layer != nil && !self.layer.hidden; }
- (BOOL)isAccessibilityEnabled { return YES; }
- (NSString *)accessibilityLabel { return [self.accessibilityRole isEqual:NSAccessibilityStaticTextRole] ? nil : self.label; }
- (id)accessibilityValue { return [self.accessibilityRole isEqual:NSAccessibilityButtonRole] ? nil : self.value; }
- (id)accessibilityMinValue { return [self.accessibilityRole isEqual:NSAccessibilityProgressIndicatorRole] && self.value ? @0 : nil; }
- (id)accessibilityMaxValue { return [self.accessibilityRole isEqual:NSAccessibilityProgressIndicatorRole] && self.value ? @100 : nil; }
- (NSAccessibilityOrientation)accessibilityOrientation {
    return [self.accessibilityRole isEqual:NSAccessibilityProgressIndicatorRole] ? NSAccessibilityOrientationHorizontal : NSAccessibilityOrientationUnknown;
}
- (BOOL)accessibilityPerformPress {
    if (![self.accessibilityRole isEqual:NSAccessibilityButtonRole]) return NO;
    return [self.owner clickLayer:self.layer];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return [self.accessibilityRole isEqual:NSAccessibilityButtonRole];
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

static NSMapTable<NSWindow *, AXBProgressView *> *Overlays;
static id CloseObserver;

static void RemoveOverlay(NSWindow *window, AXBProgressView *overlay) {
    if (!overlay) return;
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
}

// Every form context under this one that holds a progress, top to bottom.
static void CollectProgresses(CALayer *context, NSMutableArray<CALayer *> *found, NSUInteger depth) {
    if (depth > 4) return;
    if (Child(context, @"Message1") && Child(context, @"ThermoProgress")) { [found addObject:context]; return; }
    for (CALayer *layer in context.sublayers)
        for (CALayer *inner in layer.sublayers)
            if ([inner.name isEqual:@"formContext"]) CollectProgresses(inner, found, depth + 1);
}

@implementation AXBProgressView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren {
    NSMutableArray *children = [NSMutableArray new];
    for (NSString *key in self.order) {
        AXBProgressElement *element = self.elements[key];
        if (element.isAccessibilityElement) [children addObject:element];
    }
    return children;
}
- (NSRect)screenFrameForLayer:(CALayer *)layer {
    NSView *view = self.formView;
    if (!view.window || !layer) return NSZeroRect;
    NSRect inView = [layer.superlayer convertRect:layer.frame toLayer:view.layer];
    if (view.layer.geometryFlipped != view.isFlipped) inView.origin.y = NSHeight(view.bounds) - NSMaxY(inView);
    return [view.window convertRectToScreen:[view convertRect:inView toView:nil]];
}
- (BOOL)clickLayer:(CALayer *)layer {
    NSWindow *window = self.formView.window;
    if (!window.isVisible || !layer || layer.hidden) return NO;
    NSRect frame = [self screenFrameForLayer:layer];
    NSPoint center = [window convertPointFromScreen:NSMakePoint(NSMidX(frame), NSMidY(frame))];
    // Queue an ordinary click so 4D handles it exactly as for the mouse.
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    for (NSEventType type : {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp}) {
        NSEvent *event = [NSEvent mouseEventWithType:type location:center modifierFlags:0 timestamp:now windowNumber:window.windowNumber
                                             context:nil eventNumber:0 clickCount:1 pressure:type == NSEventTypeLeftMouseDown ? 1.0 : 0.0];
        if (event) [NSApp postEvent:event atStart:NO];
    }
    CFRunLoopWakeUp(CFRunLoopGetMain());
    return YES;
}
// Publish, change or retire one element, and report whether the tree changed.
- (BOOL)place:(NSString *)key role:(NSString *)role layer:(CALayer *)layer label:(NSString *)label value:(id)value order:(NSMutableArray *)order {
    AXBProgressElement *element = self.elements[key];
    if (!layer || layer.hidden) {
        if (!element) return NO;
        [self.elements removeObjectForKey:key];
        NSAccessibilityPostNotification(element, NSAccessibilityUIElementDestroyedNotification);
        return YES;
    }
    [order addObject:key];
    if (!element) {
        element = [AXBProgressElement new];
        element.owner = self; element.identifier = key; element.accessibilityRole = role;
        element.layer = layer; element.label = label; element.value = value;
        self.elements[key] = element;
        return YES;
    }
    element.layer = layer;
    if (!(label == element.label || [label isEqual:element.label])) {
        element.label = label;
        NSAccessibilityPostNotification(element, NSAccessibilityTitleChangedNotification);
    }
    if (!(value == element.value || [value isEqual:element.value])) {
        element.value = value;
        NSAccessibilityPostNotification(element, NSAccessibilityValueChangedNotification);
    }
    return NO;
}
- (BOOL)update {
    NSView *view = self.formView;
    CALayer *form = AXBInternalFormContext(view);
    if (!view.window || !form) return NO;
    NSMutableArray<CALayer *> *progresses = [NSMutableArray new];
    CollectProgresses(form, progresses, 0);
    if (!progresses.count) return NO;
    [progresses sortUsingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
        CGFloat ya = NSMaxY([self screenFrameForLayer:a]), yb = NSMaxY([self screenFrameForLayer:b]);
        return ya > yb ? NSOrderedAscending : ya < yb ? NSOrderedDescending : NSOrderedSame;
    }];
    BOOL changed = NO;
    NSMutableArray *order = [NSMutableArray new];
    NSString *stop = [[NSBundle bundleForClass:AXBProgressView.class] localizedStringForKey:@"Stop" value:@"Stop" table:@"AccessibilityBridge"];
    for (NSUInteger index = 0; index < progresses.count; index++) {
        CALayer *context = progresses[index];
        // Elements follow their progress's own layers, so a progress that finishes above
        // another leaves that one's elements in place; identifiers give the current position.
        NSString *prefix = [NSString stringWithFormat:@"%p/", (void *)context];
        NSString *position = [NSString stringWithFormat:@"axb/progress/%lu/", (unsigned long)index + 1];
        NSString *title = LayerText(Child(context, @"Message1")), *message = LayerText(Child(context, @"Message2"));
        double fraction = 0;
        BOOL known = ProgressFraction(LayerText(Child(context, @"ProgressValue")), &fraction);
        // An indeterminate progress has no value, as AppKit's indicators report it.
        id value = known && fraction >= 0 ? @(round(MIN(fraction, 1.0) * 1000) / 10) : nil;
        changed |= [self place:[prefix stringByAppendingString:@"progress"] role:NSAccessibilityProgressIndicatorRole layer:Child(context, @"ThermoProgress")
                         label:title.length ? title : nil value:value order:order];
        self.elements[[prefix stringByAppendingString:@"progress"]].titleLayer = title.length ? Child(context, @"Message1") : nil;
        changed |= [self place:[prefix stringByAppendingString:@"message"] role:NSAccessibilityStaticTextRole layer:message.length ? Child(context, @"Message2") : nil
                         label:nil value:message order:order];
        changed |= [self place:[prefix stringByAppendingString:@"stop"] role:NSAccessibilityButtonRole layer:Child(context, @"StopButton")
                         label:stop value:nil order:order];
        for (NSString *part in @[@"progress", @"message", @"stop"])
            self.elements[[prefix stringByAppendingString:part]].identifier = [position stringByAppendingString:part];
    }
    for (NSString *key in self.elements.allKeys)
        if (![order containsObject:key]) {
            NSAccessibilityPostNotification(self.elements[key], NSAccessibilityUIElementDestroyedNotification);
            [self.elements removeObjectForKey:key];
            changed = YES;
        }
    if (![order isEqual:self.order]) { self.order = order; changed = YES; }
    if (changed) NSAccessibilityPostNotification(view.window, NSAccessibilityLayoutChangedNotification);
    return self.order.count > 0;
}
@end

BOOL AXBProgressRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBProgressView *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    if (!view) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBProgressView alloc] initWithFrame:view.bounds];
        overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        overlay.formView = view; overlay.formLayer = AXBInternalFormContext(view);
        overlay.elements = [NSMutableDictionary new]; overlay.order = @[];
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
    return YES;
}

// The window whose form draws this layer, found through its form context.
static NSWindow *WindowForLayer(CALayer *layer) {
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) {
        CALayer *form = [Overlays objectForKey:window].formLayer;
        for (CALayer *ancestor = layer.superlayer; ancestor; ancestor = ancestor.superlayer) if (ancestor == form) return window;
    }
    for (NSWindow *window in NSApp.windows) {
        NSView *view = window.isVisible ? AXBInternalFormView(window) : nil;
        CALayer *form = view ? AXBInternalFormContext(view) : nil;
        for (CALayer *ancestor = form ? layer.superlayer : nil; ancestor; ancestor = ancestor.superlayer) if (ancestor == form) return window;
    }
    return nil;
}

static void ObserveWindows(void) {
    if (CloseObserver) return;
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
}

void AXBProgressInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(@"progress", ProgressNames(), ^(CALayer *layer) {
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBProgressRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBProgressShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(@"progress", nil, nil);
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    CloseObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBProgressEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
