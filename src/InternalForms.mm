#import "InternalForms.h"
#import "DrawnText.h"
#import "InternalTable.h"
#import "BridgePrivate.h"
#include <initializer_list>

static NSString *Joined(NSArray<NSString *> *texts) {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *text in texts) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length && ![parts containsObject:trimmed]) [parts addObject:trimmed];
    }
    return [parts componentsJoinedByString:@" "];
}

CALayer *AXBInternalFormChild(CALayer *context, NSString *name) {
    for (CALayer *layer in context.sublayers) if ([layer.name isEqual:name]) return layer;
    return nil;
}

CALayer *AXBInternalFormContext(NSView *view) {
    for (CALayer *layer in view.layer.sublayers) if ([layer.name isEqual:@"formContext"]) return layer;
    return nil;
}

NSView *AXBInternalFormView(NSWindow *window) {
    NSMutableArray<NSView *> *pending = window.contentView ? [NSMutableArray arrayWithObject:window.contentView] : [NSMutableArray new];
    NSView *form = nil;
    NSUInteger visited = 0;
    while (pending.count && visited++ < 64) {
        NSView *view = pending.firstObject; [pending removeObjectAtIndex:0];
        if ([view isKindOfClass:AXBWindowView.class]) return nil; // An integrated form owns its window.
        if (!form && AXBInternalFormContext(view)) form = view;
        [pending addObjectsFromArray:view.subviews];
    }
    return pending.count ? nil : form; // Too many views to rule out an integrated form.
}

NSArray<NSDictionary *> *AXBInternalListItems(CALayer *list, NSString *prefix, NSString *role) {
    NSArray<NSString *> *texts = AXBDrawnTextForLayer(list);
    NSArray<NSValue *> *origins = AXBDrawnTextOriginsForLayer(list);
    if (!texts.count || origins.count != texts.count) return nil;
    // The line height is the smallest step between baselines; a single item uses a usual one.
    NSMutableArray<NSNumber *> *baselines = [NSMutableArray new];
    for (NSValue *origin in origins) if (!isnan(origin.pointValue.y)) [baselines addObject:@(origin.pointValue.y)];
    [baselines sortUsingSelector:@selector(compare:)];
    CGFloat height = 0;
    for (NSUInteger i = 1; i < baselines.count; i++) {
        CGFloat step = baselines[i].doubleValue - baselines[i - 1].doubleValue;
        if (step > 4 && (!height || step < height)) height = step;
    }
    if (!height) height = 18;
    NSMutableArray *entries = [NSMutableArray new];
    NSCountedSet *seen = [NSCountedSet new];
    [texts enumerateObjectsUsingBlock:^(NSString *text, NSUInteger index, BOOL *stop) {
        (void)stop;
        NSPoint origin = origins[index].pointValue;
        NSString *label = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (isnan(origin.y) || !label.length) return;
        // The baseline, measured from the image's top, sits about a quarter of a line above
        // the line's bottom; the area is measured from the image's bottom.
        NSRect area = NSMakeRect(0, NSHeight(list.bounds) - origin.y - height / 4, NSWidth(list.bounds), height);
        if (NSMaxY(area) <= 0 || NSMinY(area) >= NSHeight(list.bounds)) return;
        [seen addObject:label];
        NSString *key = [seen countForObject:label] > 1 ? [NSString stringWithFormat:@"%@%@/%lu", prefix, label, (unsigned long)[seen countForObject:label]] : [prefix stringByAppendingString:label];
        [entries addObject:[@{@"key": key, @"layer": list, @"role": role, @"text": label, @"area": [NSValue valueWithRect:area], @"originX": @(origin.x)} mutableCopy]];
    }];
    return entries;
}

CALayer *AXBInternalSubformContext(CALayer *subform) { return AXBInternalFormChild(subform, @"formContext"); }

@implementation AXBInternalFormElement
- (BOOL)isButton {
    return [@[NSAccessibilityButtonRole, NSAccessibilityRadioButtonRole, NSAccessibilityCheckBoxRole, NSAccessibilityDisclosureTriangleRole] containsObject:self.accessibilityRole];
}
- (BOOL)isRadio { return [self.accessibilityRole isEqual:NSAccessibilityRadioButtonRole]; }
- (BOOL)isPopup { return [self.accessibilityRole isEqual:NSAccessibilityPopUpButtonRole]; }
- (BOOL)isField { return [self.accessibilityRole isEqual:NSAccessibilityTextFieldRole]; }
- (NSRect)screenFrame {
    CALayer *layer = self.layer;
    if (!layer) return NSZeroRect;
    if (NSIsEmptyRect(self.area)) return [self.owner screenFrameForLayer:layer inset:self.inset];
    return [self.owner screenFrameForArea:self.area inLayer:layer];
}
- (NSString *)currentText {
    NSString *text = self.text ?: [self.owner textForLayer:self.layer];
    // An empty field draws its placeholder instead of a value.
    return [self.placeholders containsObject:text] ? @"" : text;
}
- (NSString *)accessibilityPlaceholderValue {
    NSString *text = self.text ?: [self.owner textForLayer:self.layer];
    return [self.placeholders containsObject:text] ? text : nil;
}
- (NSRect)accessibilityFrame { return [self screenFrame]; }
- (id)accessibilityParent { return self.owner; }
- (NSString *)accessibilityIdentifier { return [self.owner.identifierPrefix stringByAppendingString:self.key]; }
- (BOOL)isAccessibilityElement { return self.layer != nil && !self.layer.hidden; }
- (BOOL)isAccessibilityEnabled { return YES; }
- (NSString *)accessibilityLabel {
    if (self.isButton) return self.label.length ? self.label : [self currentText];
    return self.label;
}
- (id)accessibilityValue {
    // A state 4D draws only as an image is not known; such a control reports no value.
    if (self.isRadio || [@[NSAccessibilityCheckBoxRole, NSAccessibilityDisclosureTriangleRole] containsObject:self.accessibilityRole]) return self.stateUnknown ? nil : @(self.checked);
    if (self.isButton) return nil;
    return [self currentText] ?: @"";
}
- (BOOL)accessibilityPerformPress {
    if (!self.isButton && !self.isPopup) return NO;
    return [self.owner clickElement:self];
}
- (BOOL)accessibilityPerformShowMenu { return self.isPopup && [self.owner clickElement:self]; }
- (void)setAccessibilityValue:(id)value {
    if (self.isField && self.editable && [value isKindOfClass:NSString.class]) (void)[self.owner replaceText:value inElement:self];
}
- (NSInteger)accessibilityNumberOfCharacters { return (NSInteger)[self.accessibilityValue length]; }
- (NSRange)accessibilitySelectedTextRange { return self.isField ? [self clampedSelection] : NSMakeRange(0, 0); }
- (NSArray<NSValue *> *)accessibilitySelectedTextRanges { return self.isField ? @[[NSValue valueWithRange:[self clampedSelection]]] : nil; }
- (NSString *)accessibilitySelectedText {
    NSString *value = self.accessibilityValue;
    return self.isField ? [value substringWithRange:[self clampedSelection]] : nil;
}
- (BOOL)isAccessibilityFocused { return NSApp.accessibilityApplicationFocusedUIElement == self && self.owner.window.isKeyWindow; }
// Focusing a field gives it 4D's keyboard focus with an ordinary click at its end, so the
// keys a user then types reach it, as after clicking it with the mouse.
- (void)setAccessibilityFocused:(BOOL)focused {
    if (!focused || !self.isField || !self.editable || self.caret) return;
    if (![self.owner focusField:self]) return;
    NSApp.accessibilityApplicationFocusedUIElement = self;
    NSAccessibilityPostNotification(self, NSAccessibilityFocusedUIElementChangedNotification);
}
// 4D's single-line fields.
- (NSRange)accessibilityVisibleCharacterRange { return NSMakeRange(0, [self.accessibilityValue length]); }
- (NSInteger)accessibilityInsertionPointLineNumber { return 0; }
- (NSInteger)accessibilityLineForIndex:(NSInteger)index { return index >= 0 && (NSUInteger)index <= [self.accessibilityValue length] ? 0 : NSNotFound; }
- (NSRange)accessibilityRangeForLine:(NSInteger)line { return line == 0 ? NSMakeRange(0, [self.accessibilityValue length]) : NSMakeRange(NSNotFound, 0); }
- (NSString *)accessibilityStringForRange:(NSRange)range {
    NSString *value = self.accessibilityValue;
    return range.location <= value.length && range.length <= value.length - range.location ? [value substringWithRange:range] : nil;
}
// The text is plain: one style run, and composed characters for each index.
- (NSRange)accessibilityStyleRangeForIndex:(NSInteger)index {
    NSUInteger length = [self.accessibilityValue length];
    return index >= 0 && (NSUInteger)index <= length ? NSMakeRange(0, length) : NSMakeRange(NSNotFound, 0);
}
- (NSRange)accessibilityRangeForIndex:(NSInteger)index {
    NSString *value = self.accessibilityValue;
    return index >= 0 && (NSUInteger)index < value.length ? [value rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index] : NSMakeRange(NSNotFound, 0);
}
// 4D's editor reports where each character lies, as AppKit fields do.
- (NSRect)accessibilityFrameForRange:(NSRange)range {
    NSResponder *responder = self.owner.window.firstResponder;
    NSUInteger length = [self.accessibilityValue length];
    if (!self.caret || ![responder conformsToProtocol:@protocol(NSTextInputClient)] ||
        range.location > length || range.length > length - range.location) return NSZeroRect;
    NSRange actual = NSMakeRange(NSNotFound, 0);
    return [(id<NSTextInputClient>)responder firstRectForCharacterRange:range actualRange:&actual];
}
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    NSString *text = [self accessibilityStringForRange:range];
    return text ? [[NSAttributedString alloc] initWithString:text] : nil;
}
// 4D's editor for the focused field is the window's text-input client. Its selection
// is the actual caret, including moves by the arrow keys.
- (BOOL)nativeSelection:(NSRange *)range {
    NSResponder *responder = self.owner.window.firstResponder;
    if (!self.caret || ![responder conformsToProtocol:@protocol(NSTextInputClient)]) return NO;
    id<NSTextInputClient> client = (id<NSTextInputClient>)responder;
    NSRange selected = client.selectedRange;
    NSUInteger length = [self.accessibilityValue length];
    if (client.hasMarkedText || selected.location == NSNotFound || selected.location > length || selected.length > length - selected.location) return NO;
    *range = selected;
    return YES;
}
- (NSRange)clampedSelection {
    NSRange native;
    if ([self nativeSelection:&native]) return native;
    NSUInteger length = [self.accessibilityValue length];
    NSUInteger location = MIN(self.selection.location, length);
    return NSMakeRange(location, MIN(self.selection.length, length - location));
}
- (void)noticeCaret {
    NSRange native;
    if (![self nativeSelection:&native] || NSEqualRanges(native, self.announcedSelection)) return;
    self.announcedSelection = native;
    // An AppKit field announces a caret move with this notification alone.
    NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
}
// Announce an edit as typing, the way AppKit and WebKit fields describe it, so
// VoiceOver echoes the characters. The caret follows the end of the changed text.
- (void)publishEditFrom:(NSString *)previous to:(NSString *)text {
    NSUInteger prefix = 0, suffix = 0;
    while (prefix < previous.length && prefix < text.length && [previous characterAtIndex:prefix] == [text characterAtIndex:prefix]) prefix++;
    while (suffix < previous.length - prefix && suffix < text.length - prefix &&
           [previous characterAtIndex:previous.length - 1 - suffix] == [text characterAtIndex:text.length - 1 - suffix]) suffix++;
    NSString *inserted = [text substringWithRange:NSMakeRange(prefix, text.length - prefix - suffix)];
    NSString *removed = [previous substringWithRange:NSMakeRange(prefix, previous.length - prefix - suffix)];
    self.selection = NSMakeRange(prefix + inserted.length, 0);
    NSRange native;
    self.announcedSelection = [self nativeSelection:&native] ? native : self.selection;
    NSMutableArray *changes = [NSMutableArray new];
    if (removed.length) [changes addObject:@{@"AXTextEditType": @1, @"AXTextChangeValue": removed}];
    if (inserted.length) [changes addObject:@{@"AXTextEditType": @3, @"AXTextChangeValue": inserted}];
    NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityValueChangedNotification,
                                                @{@"AXTextStateChangeType": @1, @"AXTextChangeValues": changes, @"AXTextChangeElement": self});
    NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.isButton || self.isPopup;
    if (selector == @selector(accessibilityPerformShowMenu)) return self.isPopup;
    if (selector == @selector(setAccessibilityValue:)) return self.isField && self.editable && self.isAccessibilityElement;
    if (selector == @selector(setAccessibilityFocused:)) return self.isField && self.editable && !self.caret && self.isAccessibilityElement;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@implementation AXBInternalFormOverlay
- (instancetype)initWithFormView:(NSView *)view prefix:(NSString *)prefix {
    if (!(self = [super initWithFrame:view.bounds])) return nil;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _formView = view;
    for (CALayer *layer in view.layer.sublayers) if ([layer.name isEqual:@"formContext"]) _formLayer = layer;
    _identifierPrefix = [prefix copy];
    _elements = [NSMutableDictionary new];
    _order = @[];
    _publishedAt = NSProcessInfo.processInfo.systemUptime;
    return self;
}
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren {
    NSMutableArray *children = [NSMutableArray new];
    for (NSString *key in self.order) {
        AXBInternalFormElement *element = self.elements[key];
        if (element.isAccessibilityElement) [children addObject:element];
    }
    return children;
}
- (NSString *)textForLayer:(CALayer *)layer { return layer ? Joined(AXBDrawnTextForLayer(layer) ?: @[]) : @""; }
// The part of a rectangle (in the form view's layer) that the layer's ancestors show: a subform
// clips the objects of its own form to its bounds, as the form does to the window.
static NSRect Visible(NSRect rect, CALayer *layer, CALayer *form) {
    for (CALayer *ancestor = layer.superlayer; ancestor && ancestor != form; ancestor = ancestor.superlayer)
        rect = NSIntersectionRect(rect, [ancestor convertRect:ancestor.bounds toLayer:form]);
    return NSIntersectionRect(rect, form.bounds);
}
- (NSRect)screenFrameForLayer:(CALayer *)layer inset:(CGFloat)inset {
    NSView *view = self.formView;
    if (!view.window || !layer) return NSZeroRect;
    // The object within its layer's margin, then the part of it that is shown.
    NSRect inView = [layer.superlayer convertRect:layer.frame toLayer:view.layer];
    if (inset > 0 && NSWidth(inView) > 2 * inset && NSHeight(inView) > 2 * inset) inView = NSInsetRect(inView, inset, inset);
    inView = Visible(inView, layer, view.layer);
    if (NSIsEmptyRect(inView)) return NSZeroRect;
    if (view.layer.geometryFlipped != view.isFlipped) inView.origin.y = NSHeight(view.bounds) - NSMaxY(inView);
    return [view.window convertRectToScreen:[view convertRect:inView toView:nil]];
}
- (NSRect)screenFrameForArea:(NSRect)area inLayer:(CALayer *)layer {
    // An item's area within its layer's image, from the image's bottom left; the layer can
    // show its image flipped.
    if (layer.contentsAreFlipped) area.origin.y = NSHeight(layer.bounds) - NSMaxY(area);
    CALayer *form = self.formView.layer;
    NSView *view = self.formView;
    if (!view.window || !form || !layer) return NSZeroRect;
    NSRect inView = Visible([layer convertRect:area toLayer:form], layer, form);
    if (NSIsEmptyRect(inView)) return NSZeroRect;
    if (form.geometryFlipped != view.isFlipped) inView.origin.y = NSHeight(view.bounds) - NSMaxY(inView);
    return [view.window convertRectToScreen:[view convertRect:inView toView:nil]];
}
- (void)releaseFocus {
    id focused = NSApp.accessibilityApplicationFocusedUIElement;
    if (focused && [self.elements.allValues containsObject:focused]) NSApp.accessibilityApplicationFocusedUIElement = nil;
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
static void PostClick(NSWindow *window, NSPoint point, NSInteger clicks = 1, BOOL secondary = NO) {
    // An ordinary click, double click or secondary click, queued so 4D's own loop handles it
    // exactly as for the mouse.
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSEventType down = secondary ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown, up = secondary ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;
    for (NSInteger count = 1; count <= MAX(clicks, 1); count++)
        for (NSEventType type : {down, up}) {
            NSEvent *event = [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:now windowNumber:window.windowNumber
                                                 context:nil eventNumber:0 clickCount:count pressure:type == down ? 1.0 : 0.0];
            if (event) [NSApp postEvent:event atStart:NO];
        }
}
static void PostKey(NSWindow *window, NSString *characters, NSEventModifierFlags flags, unsigned short code) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    for (NSEventType type : {NSEventTypeKeyDown, NSEventTypeKeyUp}) {
        NSEvent *event = [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:now windowNumber:window.windowNumber
                                           context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
        if (event) [NSApp postEvent:event atStart:NO];
    }
}
- (BOOL)clickElement:(AXBInternalFormElement *)element {
    NSWindow *window = self.formView.window;
    if (!window || !element.layer || element.layer.hidden || !window.isVisible) return NO;
    __weak AXBInternalFormOverlay *weakSelf = self;
    __weak AXBInternalFormElement *weakElement = element;
    [self whenSettled:^{
        AXBInternalFormOverlay *strongSelf = weakSelf;
        AXBInternalFormElement *target = weakElement;
        NSWindow *current = strongSelf.formView.window;
        if (!strongSelf || !target.layer || target.layer.hidden || !current.isVisible) return;
        CALayer *press = target.pressLayer;
        NSRect frame = press ? [strongSelf screenFrameForLayer:press inset:target.pressInset]
                     : !NSIsEmptyRect(target.pressArea) ? [strongSelf screenFrameForArea:target.pressArea inLayer:target.layer] : [target screenFrame];
        if (NSIsEmptyRect(frame)) return; // Nothing of it is shown to click.
        PostClick(current, [current convertPointFromScreen:NSMakePoint(NSMidX(frame), NSMidY(frame))], target.clicks);
    }];
    return YES;
}
// Run a block with the window and the area's center in it, once the form has settled, while
// the layer is still shown.
- (BOOL)atArea:(NSRect)area inLayer:(CALayer *)layer perform:(void (^)(NSWindow *window, NSPoint point))block {
    NSWindow *window = self.formView.window;
    if (!window || !layer || layer.hidden || !window.isVisible) return NO;
    __weak AXBInternalFormOverlay *weakSelf = self;
    __weak CALayer *weakLayer = layer;
    [self whenSettled:^{
        AXBInternalFormOverlay *strongSelf = weakSelf;
        CALayer *target = weakLayer;
        NSWindow *current = strongSelf.formView.window;
        if (!strongSelf || !target || target.hidden || !current.isVisible) return;
        NSRect frame = [strongSelf screenFrameForArea:area inLayer:target];
        if (NSIsEmptyRect(frame)) return;
        block(current, [current convertPointFromScreen:NSMakePoint(NSMidX(frame), NSMidY(frame))]);
    }];
    return YES;
}
// Move the pointer to a point of the window, and back where it was once the action is over:
// after a moment, outside a menu's tracking.
static void MovePointer(NSWindow *window, NSPoint point) {
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
    NSPoint from = NSEvent.mouseLocation, to = [window convertPointToScreen:point];
    CGWarpMouseCursorPosition(CGPointMake(to.x, top - to.y));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{ CGWarpMouseCursorPosition(CGPointMake(from.x, top - from.y)); });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    });
}
- (BOOL)clickArea:(NSRect)area inLayer:(CALayer *)layer {
    return [self clickArea:area inLayer:layer secondary:NO movingPointer:NO];
}
- (BOOL)clickArea:(NSRect)area inLayer:(CALayer *)layer secondary:(BOOL)secondary movingPointer:(BOOL)pointer {
    return [self atArea:area inLayer:layer perform:^(NSWindow *window, NSPoint point) {
        if (pointer) MovePointer(window, point);
        PostClick(window, point, 1, secondary);
    }];
}
- (BOOL)editText:(NSString *)text inArea:(NSRect)area ofLayer:(CALayer *)layer movingPointer:(BOOL)pointer {
    // Line breaks and tabs would end or move the edit.
    for (NSUInteger i = 0; i < text.length; i++)
        if ([NSCharacterSet.controlCharacterSet characterIsMember:[text characterAtIndex:i]]) return NO;
    NSString *answer = [text copy];
    return [self atArea:area inLayer:layer perform:^(NSWindow *window, NSPoint point) {
        if (!window.isKeyWindow) return;
        if (pointer) MovePointer(window, point);
        PostClick(window, point, 2);
        PostKey(window, @"a", NSEventModifierFlagCommand, 0);
        if (!answer.length) PostKey(window, @"\x7f", 0, 51);
        [answer enumerateSubstringsInRange:NSMakeRange(0, answer.length) options:NSStringEnumerationByComposedCharacterSequences
                                usingBlock:^(NSString *character, NSRange r1, NSRange r2, BOOL *stop) { (void)r1; (void)r2; (void)stop; PostKey(window, character, 0, 0); }];
        PostKey(window, @"\t", 0, 48);
    }];
}
// 4D moved its keyboard focus, for example with Tab: the newly focused object becomes the
// application's focused element, and assistive technologies are told, as AppKit does.
- (void)noteFocus:(BOOL)focused ofElement:(AXBInternalFormElement *)element {
    if (element.keyboardFocused == focused) return;
    element.keyboardFocused = focused;
    if (!focused || !self.formView.window.isKeyWindow || NSApp.accessibilityApplicationFocusedUIElement == element) return;
    NSApp.accessibilityApplicationFocusedUIElement = element;
    NSAccessibilityPostNotification(element, NSAccessibilityFocusedUIElementChangedNotification);
}
- (BOOL)focusField:(AXBInternalFormElement *)element {
    NSWindow *window = self.formView.window;
    if (!window.isVisible || !window.isKeyWindow || !element.layer) return NO;
    __weak NSWindow *weakWindow = window;
    __weak AXBInternalFormElement *weakElement = element;
    [self whenSettled:^{
        NSWindow *current = weakWindow;
        AXBInternalFormElement *field = weakElement;
        if (!current.isVisible || !current.isKeyWindow || !field.layer) return;
        NSRect frame = [field screenFrame];
        if (NSIsEmptyRect(frame)) return;
        PostClick(current, [current convertPointFromScreen:NSMakePoint(NSMaxX(frame) - MIN(4, NSWidth(frame) / 4), NSMidY(frame))]);
    }];
    return YES;
}
- (BOOL)replaceText:(NSString *)text inElement:(AXBInternalFormElement *)element {
    NSWindow *window = self.formView.window;
    if (!window.isVisible || !window.isKeyWindow || !element.layer) return NO;
    // Type each character as an ordinary key event so 4D's own editor applies it.
    // Line breaks would end entry.
    for (NSUInteger i = 0; i < text.length; i++)
        if ([NSCharacterSet.controlCharacterSet characterIsMember:[text characterAtIndex:i]]) return NO;
    NSString *answer = [text copy];
    __weak NSWindow *weakWindow = window;
    __weak AXBInternalFormOverlay *weakSelf = self;
    __weak AXBInternalFormElement *weakElement = element;
    [self whenSettled:^{
        NSWindow *current = weakWindow;
        AXBInternalFormOverlay *strongSelf = weakSelf;
        AXBInternalFormElement *field = weakElement;
        if (!current.isVisible || !current.isKeyWindow || !strongSelf || !field.layer) return;
        NSUInteger length = [field.accessibilityValue length];
        NSString *right = [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey];
        NSRange selected;
        if (field.caret) {
            // The focused field: replace the whole text. 4D starts with it selected; after a
            // caret move, go to its end with the Right arrow and delete it, as a keyboard user would.
            if (![field nativeSelection:&selected]) PostKey(current, @"a", NSEventModifierFlagCommand, 0);
            else if (selected.location != 0 || selected.length != length) {
                NSUInteger moves = (selected.length ? 1 : 0) + length - NSMaxRange(selected);
                for (NSUInteger i = 0; i < moves; i++) PostKey(current, right, NSEventModifierFlagFunction | NSEventModifierFlagNumericPad, 124);
                for (NSUInteger i = 0; i < length; i++) PostKey(current, @"\x7f", 0, 51);
            }
        } else {
            // Another field: click inside it near its end, as the mouse focuses it, then go to
            // its end and delete its text, so its own events run as for the keyboard.
            NSRect frame = [field screenFrame];
            // Without a visible part to click, the keys would reach another field.
            if (NSIsEmptyRect(frame)) return;
            NSPoint end = NSMakePoint(NSMaxX(frame) - MIN(4, NSWidth(frame) / 4), NSMidY(frame));
            PostClick(current, [current convertPointFromScreen:end]);
            for (NSUInteger i = 0; i < length; i++) PostKey(current, right, NSEventModifierFlagFunction | NSEventModifierFlagNumericPad, 124);
            for (NSUInteger i = 0; i < length; i++) PostKey(current, @"\x7f", 0, 51);
        }
        [answer enumerateSubstringsInRange:NSMakeRange(0, answer.length) options:NSStringEnumerationByComposedCharacterSequences
                                usingBlock:^(NSString *character, NSRange r1, NSRange r2, BOOL *stop) { (void)r1; (void)r2; (void)stop; PostKey(current, character, 0, 0); }];
        if (field.caret && !answer.length) PostKey(current, @"\x7f", 0, 51);
    }];
    return YES;
}
- (BOOL)updateWithEntries:(NSArray<NSDictionary *> *)entries {
    NSView *view = self.formView;
    if (!view.window) return NO;
    BOOL changed = NO;
    NSMutableArray *order = [NSMutableArray new];
    for (NSDictionary *entry in entries) {
        NSString *key = entry[@"key"], *role = entry[@"role"], *label = entry[@"label"];
        CALayer *layer = entry[@"layer"];
        NSString *text = entry[@"text"] ?: (layer ? [self textForLayer:layer] : nil);
        if ([entry[@"placeholders"] containsObject:text]) text = @"";
        NSRect area = entry[@"area"] ? [entry[@"area"] rectValue] : NSZeroRect;
        AXBInternalFormElement *element = self.elements[key];
        // An empty text field or table is still one.
        BOOL field = [role isEqual:NSAccessibilityTextFieldRole] || [role isEqual:NSAccessibilityTableRole];
        // An empty text field is still a field; other objects need text or a fixed label.
        if (!layer || layer.hidden || (!text.length && !label.length && !field)) continue;
        if (element && ![element.accessibilityRole isEqual:role]) {
            [self.elements removeObjectForKey:key];
            NSAccessibilityPostNotification(element, NSAccessibilityUIElementDestroyedNotification);
            element = nil;
        }
        [order addObject:key];
        BOOL table = [role isEqual:NSAccessibilityTableRole];
        if (!element) {
            element = table ? [AXBInternalTable new] : [AXBInternalFormElement new];
            element.owner = self; element.layer = layer; element.key = key; element.accessibilityRole = role;
            element.label = label; element.editable = [entry[@"editable"] boolValue]; element.caret = [entry[@"caret"] boolValue];
            element.inset = [entry[@"inset"] doubleValue];
            element.area = area; element.text = entry[@"text"]; element.placeholders = entry[@"placeholders"];
            element.pressLayer = entry[@"press"]; element.pressInset = [entry[@"pressInset"] doubleValue];
            element.pressArea = entry[@"pressArea"] ? [entry[@"pressArea"] rectValue] : NSZeroRect;
            element.clicks = [entry[@"clicks"] integerValue];
            element.checked = [entry[@"checked"] boolValue];
            element.stateUnknown = entry[@"checked"] == nil;
            element.publishedText = text;
            element.selection = NSMakeRange(0, text.length);
            self.elements[key] = element;
            [self noteFocus:[entry[@"focused"] boolValue] ofElement:element];
            if (table) [(AXBInternalTable *)element updateWithModel:entry[@"table"]];
            changed = YES;
            continue;
        }
        if (table) [(AXBInternalTable *)element updateWithModel:entry[@"table"]];
        // 4D can replace an object's layer while redrawing it, as a field does on each
        // keystroke. The object keeps its element, so assistive focus and echo survive.
        element.layer = layer;
        element.editable = [entry[@"editable"] boolValue];
        element.caret = [entry[@"caret"] boolValue];
        element.area = area; element.text = entry[@"text"]; element.placeholders = entry[@"placeholders"];
        element.pressLayer = entry[@"press"]; element.pressInset = [entry[@"pressInset"] doubleValue];
        element.pressArea = entry[@"pressArea"] ? [entry[@"pressArea"] rectValue] : NSZeroRect;
        element.clicks = [entry[@"clicks"] integerValue];
        element.stateUnknown = entry[@"checked"] == nil;
        if (element.checked != [entry[@"checked"] boolValue]) {
            element.checked = [entry[@"checked"] boolValue];
            NSAccessibilityPostNotification(element, NSAccessibilityValueChangedNotification);
        }
        [self noteFocus:[entry[@"focused"] boolValue] ofElement:element];
        if (!(label == element.label || [label isEqual:element.label])) {
            element.label = label;
            NSAccessibilityPostNotification(element, NSAccessibilityTitleChangedNotification);
        }
        if (![element.publishedText isEqual:text]) {
            NSString *previous = element.publishedText;
            element.publishedText = text;
            if ([role isEqual:NSAccessibilityTextFieldRole]) [element publishEditFrom:previous ?: @"" to:text];
            else if (!table) NSAccessibilityPostNotification(element, [role isEqual:NSAccessibilityButtonRole] && !label.length ? NSAccessibilityTitleChangedNotification : NSAccessibilityValueChangedNotification);
        }
    }
    for (NSString *key in self.elements.allKeys) {
        if ([order containsObject:key]) continue;
        AXBInternalFormElement *element = self.elements[key];
        if (NSApp.accessibilityApplicationFocusedUIElement == element) NSApp.accessibilityApplicationFocusedUIElement = nil;
        [self.elements removeObjectForKey:key];
        NSAccessibilityPostNotification(element, NSAccessibilityUIElementDestroyedNotification);
        changed = YES;
    }
    if (![order isEqual:self.order]) { self.order = order; changed = YES; }
    if (changed) NSAccessibilityPostNotification(view.window, NSAccessibilityLayoutChangedNotification);
    return self.order.count > 0;
}
@end
