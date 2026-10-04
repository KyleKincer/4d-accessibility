#import <Cocoa/Cocoa.h>
#import "Bridge.h"
#import "Session.h"
#import "BridgePrivate.h"
#import "Identifiers.h"
#include "Limits.h"
#import "NativeLayout.h"
#import <objc/runtime.h>

static NSMutableDictionary<NSString *, AXBSession *> *sessions;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *bindings;
static NSMutableSet<NSString *> *refreshPending;
static NSObject *registryLock;
static BOOL stopped;
@class AXBWindowView;
static NSMutableDictionary<NSString *, AXBWindowView *> *views; // Main thread only.

static void Init(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        registryLock = [NSObject new]; sessions = [NSMutableDictionary new];
        bindings = [NSMutableDictionary new]; refreshPending = [NSMutableSet new];
    });
}
static NSString *JSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static NSTimeInterval Now(void) { return NSProcessInfo.processInfo.systemUptime; }

static NSDictionary *ConfirmedControlFeedback(NSDictionary *feedback, NSDictionary *activity, NSTimeInterval now) {
    NSDictionary *result = activity[@"result"];
    if (!feedback[@"control"] || feedback[@"result"] || ![feedback[@"id"] isEqual:result[@"id"]] ||
        ![result[@"status"] isEqual:@"completed"]) return feedback;
    NSMutableDictionary *confirmed = [feedback mutableCopy];
    confirmed[@"result"] = result;
    confirmed[@"deadline"] = feedback[@"deadline"] ?: @(now+2);
    return confirmed;
}

// Form-local coordinates stay fixed while a scroll container reveals a child.
// Keep that reading order instead of letting screen geometry reorder siblings.
static NSArray *NavigationChildren(NSArray *children) {
    for (id child in children)
        if (![child isKindOfClass:AXBNode.class] || !((AXBNode *)child).data[@"navigation"]) return nil;
    return [children sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(AXBNode *a, AXBNode *b) {
        NSArray *left = a.data[@"navigation"], *right = b.data[@"navigation"];
        for (NSUInteger i = 0; i < MIN(left.count, right.count); i++) {
            NSComparisonResult result = [left[i] compare:right[i]];
            if (result != NSOrderedSame) return result;
        }
        return left.count < right.count ? NSOrderedAscending : left.count > right.count ? NSOrderedDescending : NSOrderedSame;
    }];
}

// External AppKit mutability queries use implemented setters even when the
// modern allowed-selector method rejects them. Advertise only live operations
// that our virtual elements actually implement. Native host views are untouched.
BOOL AXBAttributeIsSettable(id<NSAccessibility> element, NSString *attribute) {
    if (!element.isAccessibilityElement || !element.isAccessibilityEnabled) return NO;
    NSString *role = element.accessibilityRole;
    SEL selector = nil;
    if ([attribute isEqual:NSAccessibilityFocusedAttribute]) selector = @selector(setAccessibilityFocused:);
    else if ([attribute isEqual:NSAccessibilityValueAttribute] && [@[NSAccessibilityTextFieldRole, NSAccessibilityTextAreaRole, NSAccessibilityComboBoxRole, NSAccessibilityCellRole] containsObject:role]) selector = @selector(setAccessibilityValue:);
    else if ([attribute isEqual:NSAccessibilitySelectedAttribute] && [role isEqual:NSAccessibilityRowRole]) selector = @selector(setAccessibilitySelected:);
    else if ([attribute isEqual:NSAccessibilityDisclosingAttribute] && [role isEqual:NSAccessibilityRowRole]) selector = @selector(setAccessibilityDisclosed:);
    else if ([attribute isEqual:NSAccessibilitySelectedRowsAttribute] && [@[NSAccessibilityTableRole, NSAccessibilityOutlineRole] containsObject:role]) selector = @selector(setAccessibilitySelectedRows:);
    else if ([role isEqual:NSAccessibilityTextFieldRole] || [role isEqual:NSAccessibilityTextAreaRole] || [role isEqual:NSAccessibilityComboBoxRole]) {
        if ([attribute isEqual:NSAccessibilitySelectedTextAttribute]) selector = @selector(setAccessibilitySelectedText:);
        if ([attribute isEqual:NSAccessibilitySelectedTextRangeAttribute]) selector = @selector(setAccessibilitySelectedTextRange:);
    }
    return selector && [element isAccessibilitySelectorAllowed:selector];
}

NSString *AXBNativeFocus(void *nativeWindow) {
    if (!NSThread.isMainThread) return JSON(@{@"ok": @NO, @"error": @"notMainThread"});
    NSWindow *window = nil;
    for (NSWindow *candidate in NSApp.windows) if ((__bridge void *)candidate == nativeWindow) { window = candidate; break; }
    if (!window.contentView || !window.isKeyWindow || !NSApp.isActive) return JSON(@{@"ok": @NO, @"error": @"inactiveWindow"});
    NSResponder *responder = window.firstResponder;
    NSMutableDictionary *result = [@{@"ok": @YES, @"textInput": @([responder conformsToProtocol:@protocol(NSTextInputClient)])} mutableCopy];
    result[@"viewport"] = @[@0, @0, @(NSWidth(window.contentView.bounds)), @(NSHeight(window.contentView.bounds))];
    for (AXBWindowView *view in views.allValues) if (view.window == window && view.live) {
        [view refreshComboPopup];
        result[@"comboExpanded"] = @(view.comboOwner != nil && view.comboList.window.isVisible);
    }
    if ([responder isKindOfClass:NSView.class] && ((NSView *)responder).window == window) {
        NSView *view = (NSView *)responder;
        NSRect frame = [view convertRect:view.bounds toView:window.contentView];
        if (!window.contentView.isFlipped) frame.origin.y = NSMaxY(window.contentView.bounds) - NSMaxY(frame);
        result[@"frame"] = @[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)];
    }
    if ([responder conformsToProtocol:@protocol(NSTextInputClient)]) {
        id<NSTextInputClient> client = (id<NSTextInputClient>)responder;
        NSRange selected = client.selectedRange;
        if (selected.location != NSNotFound) {
            NSRange actual = NSMakeRange(NSNotFound, 0);
            NSRect screen = [client firstRectForCharacterRange:NSMakeRange(selected.location, 0) actualRange:&actual];
            NSRect rect = [window.contentView convertRect:[window convertRectFromScreen:screen] fromView:nil];
            if (!window.contentView.isFlipped) rect.origin.y = NSMaxY(window.contentView.bounds) - NSMaxY(rect);
            result[@"caret"] = @[@(rect.origin.x), @(rect.origin.y), @(rect.size.width), @(rect.size.height)];
            result[@"selection"] = @[@(selected.location), @(selected.length)];
        }
    }
    return JSON(result);
}

@interface AXBComboButton : NSAccessibilityElement
@property(nonatomic, weak) AXBNode *combo;
@end
@implementation AXBComboButton
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { (void)attribute; return NO; }
- (BOOL)isAccessibilityElement { return self.combo.isAccessibilityElement; }
- (NSString *)accessibilityRole { return NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel { return @"Show choices"; }
- (NSString *)accessibilityIdentifier { return [self.combo.accessibilityIdentifier stringByAppendingString:@"/choices"]; }
- (id)accessibilityParent { return self.combo; }
- (id)accessibilityWindow { return self.combo.accessibilityWindow; }
- (id)accessibilityTopLevelUIElement { return self.combo.accessibilityTopLevelUIElement; }
- (BOOL)isAccessibilityEnabled { return self.combo.isAccessibilityEnabled; }
- (NSRect)accessibilityFrame {
    NSRect frame = self.combo.accessibilityFrame;
    if (NSIsEmptyRect(frame)) return NSZeroRect;
    CGFloat width = MIN(24, NSWidth(frame));
    return NSMakeRect(NSMaxX(frame) - width, NSMinY(frame), width, NSHeight(frame));
}
- (BOOL)accessibilityPerformPress { return [self.combo accessibilityPerformShowMenu]; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityElement && self.isAccessibilityEnabled;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

static id DeepestHit(id element, NSPoint point);
static id DeepestFormHit(AXBWindowView *view, NSPoint point);
static NSArray *TopLevelNodes(AXBWindowView *view);

@implementation AXBNode
- (id)accessibilityHitTest:(NSPoint)point {
    return self.owner.rootContainer && !self.data[@"parent"] ? DeepestFormHit(self.owner, point) : DeepestHit(self, point);
}
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { return AXBAttributeIsSettable(self, attribute); }
- (void)invalidate {
    if (!self.live) return;
    self.live = NO;
    NSAccessibilityPostNotification(self, NSAccessibilityUIElementDestroyedNotification);
}
- (BOOL)isAccessibilityElement { return self.live && [self.data[@"visible"] boolValue]; }
- (NSString *)accessibilityIdentifier { return self.identifier; }
- (NSString *)accessibilityLabel {
    // VoiceOver reads an image's label, not AXValue. Include its current text
    // alternative while preserving the stable identifier and raw value for AX.
    if ([self.data[@"role"] isEqual:@"image"] && [self.data[@"value"] length])
        return [self.data[@"label"] length] ? [NSString stringWithFormat:@"%@: %@", self.data[@"label"], self.data[@"value"]] : self.data[@"value"];
    return self.data[@"label"];
}
- (NSString *)accessibilityRole {
    if ([self.data[@"combo"] boolValue]) return NSAccessibilityComboBoxRole;
    if ([self.data[@"role"] isEqual:@"textfield"] && [self.data[@"multiline"] boolValue] && ![self.data[@"protected"] boolValue]) return NSAccessibilityTextAreaRole;
    return @{@"button": NSAccessibilityButtonRole, @"checkbox": NSAccessibilityCheckBoxRole,
        @"radio": NSAccessibilityRadioButtonRole, @"popup": NSAccessibilityPopUpButtonRole,
        @"textfield": NSAccessibilityTextFieldRole, @"text": NSAccessibilityStaticTextRole,
        @"table": NSAccessibilityTableRole, @"row": NSAccessibilityRowRole, @"cell": NSAccessibilityCellRole,
        @"group": NSAccessibilityGroupRole, @"tabgroup": NSAccessibilityTabGroupRole, @"tab": NSAccessibilityRadioButtonRole,
        @"image": NSAccessibilityImageRole, @"progress": NSAccessibilityProgressIndicatorRole, @"slider": NSAccessibilitySliderRole, @"stepper": NSAccessibilityIncrementorRole}[self.data[@"role"]];
}
- (NSString *)accessibilitySubrole {
    if ([self.data[@"protected"] boolValue]) return NSAccessibilitySecureTextFieldSubrole;
    return [self.data[@"role"] isEqual:@"tab"] ? NSAccessibilityTabButtonSubrole : nil;
}
- (NSString *)accessibilityPlaceholderValue { return self.data[@"placeholder"]; }
- (BOOL)isAccessibilityExpanded { return self.live && self.owner.comboOwner == self && self.owner.comboList.window.isVisible; }
- (NSArray *)accessibilityLinkedUIElements {
    if ([self.data[@"combo"] boolValue]) return self.isAccessibilityExpanded ? @[self.owner.comboList] : @[];
    NSMutableArray *linked = [NSMutableArray new];
    NSMutableDictionary *byID = [NSMutableDictionary new];
    for (AXBNode *node in self.owner.nodes) if (node.isAccessibilityElement) byID[node.data[@"id"]] = node;
    for (NSString *identifier in self.data[@"linked"])
        if (byID[identifier]) [linked addObject:byID[identifier]];
    return linked;
}
- (id)accessibilityTitleUIElement {
    for (AXBNode *node in self.owner.nodes) if ([node.data[@"id"] isEqual:self.data[@"labelledBy"]]) return node;
    return nil;
}
- (BOOL)isAccessibilityFocused { return self.live && [self.data[@"focused"] boolValue] && self.owner.window.isKeyWindow; }
- (void)setAccessibilityFocused:(BOOL)focused { if (focused) (void)[self queue:@"focus" value:@YES]; }
- (id)accessibilityParent {
    if (self.data[@"parent"]) for (AXBNode *node in self.owner.nodes) if ([node.data[@"id"] isEqual:self.data[@"parent"]]) return node;
    return self.owner.rootContainer ?: self.owner.element;
}
- (NSArray *)accessibilityChildren {
    if ([self.data[@"combo"] boolValue] && self.live) {
        if (!self.comboButton) {
            AXBComboButton *button = [AXBComboButton new]; button.combo = self; self.comboButton = button;
        }
        NSScrollView *popup = self.owner.comboList.enclosingScrollView;
        return self.isAccessibilityExpanded && popup ? @[self.comboButton, popup] : @[self.comboButton];
    }
    NSMutableArray *children = [NSMutableArray new];
    for (AXBNode *node in self.owner.nodes) if (node.isAccessibilityElement && [node.data[@"parent"] isEqual:self.data[@"id"]]) [children addObject:node];
    return children;
}
- (id)accessibilityTopLevelUIElement { return self.owner.window; }
- (NSArray *)accessibilityChildrenInNavigationOrder { return NavigationChildren(self.accessibilityChildren); }
- (id)accessibilityWindow { return self.owner.window; }
- (NSArray *)accessibilityTabs { return [self.data[@"role"] isEqual:@"tabgroup"] ? self.accessibilityChildren : nil; }
- (NSArray *)accessibilitySelectedChildren {
    if (![self.data[@"role"] isEqual:@"tabgroup"]) return nil;
    NSMutableArray *selected = [NSMutableArray new];
    for (AXBNode *tab in self.accessibilityChildren) if ([tab.data[@"value"] boolValue]) [selected addObject:tab];
    return selected;
}
- (id)accessibilityValue {
    if ([self.data[@"role"] isEqual:@"tabgroup"]) return self.accessibilitySelectedChildren.firstObject;
    return self.data[@"value"] == NSNull.null ? nil : self.data[@"value"];
}
- (NSString *)accessibilityValueDescription { return self.data[@"valueDescription"]; }
- (NSAccessibilityOrientation)accessibilityOrientation {
    if (![@[@"slider", @"progress"] containsObject:self.data[@"role"]]) return NSAccessibilityOrientationUnknown;
    return [self.data[@"vertical"] boolValue] ? NSAccessibilityOrientationVertical : NSAccessibilityOrientationHorizontal;
}
- (id)accessibilityMinValue { return [@[@"progress", @"slider", @"stepper"] containsObject:self.data[@"role"]] && ![self.data[@"indeterminate"] boolValue] ? self.data[@"min"] : nil; }
- (id)accessibilityMaxValue { return [@[@"progress", @"slider", @"stepper"] containsObject:self.data[@"role"]] && ![self.data[@"indeterminate"] boolValue] ? self.data[@"max"] : nil; }
- (BOOL)isAccessibilityEnabled { return self.live && [self.data[@"enabled"] boolValue] && [self.owner canAct]; }
- (NSRect)accessibilityFrame {
    if ([self.data[@"revealable"] boolValue] && self.live && self.owner.window) {
        NSArray *f = self.data[@"frame"];
        NSRect local = NSMakeRect([f[0] doubleValue], [f[1] doubleValue], [f[2] doubleValue], [f[3] doubleValue]);
        return [self.owner.window convertRectToScreen:[self.owner convertRect:local toView:nil]];
    }
    return self.hitFrame;
}
- (NSRect)hitFrame {
    if (!self.live || !self.owner.window) return NSZeroRect;
    NSArray *f = self.data[@"frame"];
    NSRect local = NSMakeRect([f[0] doubleValue], [f[1] doubleValue], [f[2] doubleValue], [f[3] doubleValue]);
    NSArray *clip = self.data[@"clip"];
    if (clip) local = NSIntersectionRect(local, NSMakeRect([clip[0] doubleValue], [clip[1] doubleValue], [clip[2] doubleValue], [clip[3] doubleValue]));
    NSRect clipped = NSIntersectionRect(local, self.owner.bounds);
    if (self.data[@"parent"]) {
        AXBNode *parent = self.accessibilityParent;
        if (![parent.data[@"role"] isEqual:@"group"])
            return NSIntersectionRect([self.owner.window convertRectToScreen:[self.owner convertRect:clipped toView:nil]], parent.hitFrame);
    }
    return [self.owner.window convertRectToScreen:[self.owner convertRect:clipped toView:nil]];
}
- (BOOL)queue:(NSString *)operation value:(id)value {
    BOOL readable = [operation isEqual:@"reveal"] && [self.owner canAct];
    if (!NSThread.isMainThread || (!self.isAccessibilityEnabled && !readable) || ![self isAccessibilityElement]) return NO;
    AXBSession *session = self.owner.session;
    BOOL accepted;
    NSDictionary *activity;
    // Capture the accepted request and preceding result under the session's
    // monitor. A host exchange can complete the new request before AppKit's
    // queued refresh runs, replacing that result. No AppKit calls hold the lock.
    @synchronized(session) {
        accepted = [session enqueueNode:self.data[@"id"] revision:self.revision operation:operation value:value observedSnapshot:self.owner.publishedSnapshot now:Now()];
        activity = accepted ? session.activity : nil;
    }
    if (accepted) {
        if (AXBGridRevealMatchesElement(self.owner.actionFeedback[@"control"], activity))
            self.owner.actionFeedback = ConfirmedControlFeedback(self.owner.actionFeedback, activity, Now());
        else
            self.owner.actionFeedback = nil;
        // VoiceOver can read the old value before 4D applies an action. These
        // controls need feedback after the exact host completion receipt.
        NSString *action = activity[@"id"];
        BOOL checkbox = [operation isEqual:@"press"] && [self.data[@"role"] isEqual:@"checkbox"] && ![self.data[@"focusable"] boolValue];
        BOOL tab = [operation isEqual:@"press"] && [self.data[@"role"] isEqual:@"tab"];
        BOOL slider = [@[@"increment", @"decrement"] containsObject:operation] && [self.data[@"role"] isEqual:@"slider"];
        if (action && (checkbox || slider || tab))
            self.owner.actionFeedback = @{@"id": action, @"node": self.data[@"id"], @"role": self.data[@"role"], @"label": self.data[@"label"], @"value": self.data[@"value"]};
    }
    return accepted;
}
// Keep complete logical bounds for navigation, but reveal through the owning
// 4D form. Screen-position lookup continues using the clipped hit rectangle.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray *)accessibilityActionNames {
    NSMutableArray *actions = [NSMutableArray new];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)]) [actions addObject:NSAccessibilityPressAction];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformIncrement)]) [actions addObject:NSAccessibilityIncrementAction];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformDecrement)]) [actions addObject:NSAccessibilityDecrementAction];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformShowMenu)]) [actions addObject:NSAccessibilityShowMenuAction];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformConfirm)]) [actions addObject:NSAccessibilityConfirmAction];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformCancel)]) [actions addObject:NSAccessibilityCancelAction];
    if (@available(macOS 26.0, *)) {
        if ([self.data[@"revealable"] boolValue] && self.isAccessibilityElement && [self.owner canAct])
            [actions addObject:NSAccessibilityScrollToVisibleAction];
    }
    return actions;
}
- (void)accessibilityPerformAction:(NSString *)action {
    if (@available(macOS 26.0, *)) {
        if ([action isEqual:NSAccessibilityScrollToVisibleAction]) {
            (void)[self queue:@"reveal" value:nil];
            return;
        }
    }
    [super accessibilityPerformAction:action];
}
#pragma clang diagnostic pop
- (BOOL)accessibilityPerformPress { return [self queue:[self.data[@"combo"] boolValue] ? @"showMenu" : @"press" value:nil]; }
- (BOOL)accessibilityPerformIncrement { return [self queue:@"increment" value:nil]; }
- (BOOL)accessibilityPerformDecrement { return [self queue:@"decrement" value:nil]; }
- (BOOL)accessibilityPerformShowMenu {
    if (!self.isAccessibilityElement || !self.isAccessibilityEnabled) return NO;
    [self.owner refreshComboPopup];
    return self.isAccessibilityExpanded || [self queue:@"showMenu" value:nil];
}
- (BOOL)accessibilityPerformConfirm {
    [self.owner refreshComboPopup];
    return self.isAccessibilityExpanded && [self queue:@"confirm" value:nil];
}
- (BOOL)accessibilityPerformCancel {
    [self.owner refreshComboPopup];
    return self.isAccessibilityExpanded && [self queue:@"dismissMenu" value:nil];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformIncrement) || selector == @selector(accessibilityPerformDecrement))
        return [@[@"slider", @"stepper"] containsObject:self.data[@"role"]] && [self.data[@"adjustable"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(setAccessibilityFocused:)) return [self.data[@"focusable"] boolValue] && self.isAccessibilityEnabled;
    if (selector == @selector(setAccessibilityValue:)) return [self.data[@"role"] isEqual:@"textfield"] && (!self.data[@"editable"] || [self.data[@"editable"] boolValue]) && self.isAccessibilityEnabled;
    if (selector == @selector(accessibilityPerformPress)) return ([@[@"button", @"checkbox", @"radio", @"popup", @"tab"] containsObject:self.data[@"role"]] || [self.data[@"combo"] boolValue]) && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformShowMenu)) return [self.data[@"combo"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformConfirm)) return [self.data[@"combo"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformCancel)) return [self.data[@"combo"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(isAccessibilityExpanded)) return [self.data[@"combo"] boolValue] && self.isAccessibilityElement;
    if (selector == @selector(accessibilityLinkedUIElements)) return ([self.data[@"combo"] boolValue] || self.data[@"linked"]) && self.isAccessibilityElement;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

// Row adapters describe one permitted summary, rather than editable grid cells.
// VoiceOver navigates table contents through cells, so provide a stable read-only
// cell for rows without explicit children. Its only action is row selection.
@interface AXBSummaryCell : NSAccessibilityElement
@property(nonatomic, weak) AXBNode *row;
@property(nonatomic, copy) NSString *identifier;
@end
@implementation AXBSummaryCell
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { (void)attribute; return NO; }
- (BOOL)isAccessibilityElement { return self.row.isAccessibilityElement; }
- (NSString *)accessibilityIdentifier { return self.identifier; }
- (NSString *)accessibilityRole { return NSAccessibilityCellRole; }
- (NSString *)accessibilityLabel { return self.row.accessibilityLabel; }
- (id)accessibilityValue { return self.row.accessibilityValue; }
- (id)accessibilityParent { return self.row; }
- (id)accessibilityWindow { return self.row.accessibilityWindow; }
- (id)accessibilityTopLevelUIElement { return self.row.accessibilityTopLevelUIElement; }
- (NSRect)accessibilityFrame { return self.row.isAccessibilityElement ? self.row.accessibilityFrame : NSZeroRect; }
- (BOOL)isAccessibilityEnabled { return self.row.isAccessibilityEnabled; }
- (BOOL)isAccessibilitySelected { return [self.row.data[@"selected"] boolValue]; }
- (NSRange)accessibilityColumnIndexRange { return NSMakeRange(0, 1); }
- (NSRange)accessibilityRowIndexRange {
    if (!self.row.isAccessibilityElement) return NSMakeRange(NSNotFound, 0);
    id table = self.row.accessibilityParent;
    NSArray *rows = [table accessibilityRows];
    NSUInteger index = [rows indexOfObjectIdenticalTo:self.row];
    return NSMakeRange(index, index == NSNotFound ? 0 : 1);
}
- (BOOL)accessibilityPerformPress { return [self.row accessibilityPerformPress]; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityValue:) || selector == @selector(setAccessibilitySelected:) || selector == @selector(setAccessibilityFocused:)) return NO;
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityEnabled && self.isAccessibilityElement;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@interface AXBTableNode : AXBNode
@end
@implementation AXBTableNode
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    // NSAccessibilityElement asks accessibilityIsAttributeSettable again for
    // this setter. Answer here so the two compatibility APIs cannot recurse.
    if (selector == @selector(setAccessibilitySelectedRows:)) return self.isAccessibilityElement && self.isAccessibilityEnabled;
    return [super isAccessibilitySelectorAllowed:selector];
}
- (NSArray *)accessibilityRows { return self.accessibilityChildren; }
- (NSInteger)accessibilityRowCount { return self.accessibilityRows.count; }
- (NSInteger)accessibilityColumnCount {
    NSUInteger count = 0;
    for (AXBNode *row in self.accessibilityRows) count = MAX(count, row.accessibilityChildren.count);
    return count;
}
- (id)accessibilityCellForColumn:(NSInteger)column row:(NSInteger)row {
    NSArray *rows = self.accessibilityRows;
    if (row < 0 || (NSUInteger)row >= rows.count || column < 0) return nil;
    NSArray *cells = [rows[row] accessibilityChildren];
    return (NSUInteger)column < cells.count ? cells[column] : nil;
}
- (NSArray *)accessibilityVisibleRows {
    NSMutableArray *rows = [NSMutableArray new];
    for (AXBNode *row in self.accessibilityRows) if (!NSIsEmptyRect(row.accessibilityFrame)) [rows addObject:row];
    return rows;
}
- (NSArray *)accessibilitySelectedRows {
    NSMutableArray *rows = [NSMutableArray new];
    for (AXBNode *row in self.accessibilityRows) if ([row.data[@"selected"] boolValue]) [rows addObject:row];
    return rows;
}
- (void)setAccessibilitySelectedRows:(NSArray *)rows {
    if (![rows isKindOfClass:NSArray.class]) return;
    NSMutableArray *ids = [NSMutableArray new];
    for (id row in rows) {
        if (![row isKindOfClass:AXBNode.class] || ![[self accessibilityRows] containsObject:row]) return;
        AXBNode *node = row;
        [ids addObject:node.data[@"id"]];
    }
    (void)[self queue:@"selectRows" value:ids];
}
@end

@interface AXBRowNode : AXBNode
@property(nonatomic, strong) AXBSummaryCell *summaryCell;
@end
@implementation AXBRowNode
- (void)invalidate {
    if (!self.live) return;
    [super invalidate];
    if (self.summaryCell) NSAccessibilityPostNotification(self.summaryCell, NSAccessibilityUIElementDestroyedNotification);
}
- (NSArray *)accessibilityChildren {
    if (!self.isAccessibilityElement) return @[];
    NSArray *explicitCells = [super accessibilityChildren];
    if (explicitCells.count) return explicitCells;
    if (!self.summaryCell) {
        self.summaryCell = [AXBSummaryCell new]; self.summaryCell.row = self;
        self.summaryCell.identifier = [self.accessibilityIdentifier stringByAppendingString:@"/summary"];
    }
    return @[self.summaryCell];
}
- (BOOL)isAccessibilitySelected { return [self.data[@"selected"] boolValue]; }
- (NSInteger)accessibilityIndex { return [self.data[@"index"] integerValue]; }
- (BOOL)accessibilityPerformPress {
    if (!self.live || !self.isAccessibilityEnabled) return NO;
    AXBTableNode *table = self.accessibilityParent;
    return [table queue:@"selectRows" value:@[self.data[@"id"]]];
}
- (void)setAccessibilitySelected:(BOOL)selected {
    AXBTableNode *table = self.accessibilityParent;
    if (selected) { (void)[self accessibilityPerformPress]; return; }
    NSMutableArray *remaining = [table.accessibilitySelectedRows mutableCopy];
    [remaining removeObject:self];
    [table setAccessibilitySelectedRows:remaining];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress) || selector == @selector(setAccessibilitySelected:)) return self.isAccessibilityEnabled;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@implementation AXBTextNode
- (NSInteger)accessibilityNumberOfCharacters { return [self.accessibilityValue length]; }
- (NSRange)accessibilitySelectedTextRange {
    NSArray *range = self.data[@"selection"];
    return range ? NSMakeRange([range[0] unsignedIntegerValue], [range[1] unsignedIntegerValue]) : NSMakeRange(0, 0);
}
- (NSString *)accessibilityStringForRange:(NSRange)range {
    NSString *text = self.accessibilityValue;
    if ([self.data[@"protected"] boolValue] || !AXBTextRangeValid(text, range)) return nil;
    return [text substringWithRange:range];
}
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    NSString *text = [self accessibilityStringForRange:range];
    return text ? [[NSAttributedString alloc] initWithString:text] : nil;
}
- (NSString *)accessibilitySelectedText { return [self accessibilityStringForRange:self.accessibilitySelectedTextRange]; }
- (NSInteger)accessibilityLineForIndex:(NSInteger)index {
    NSString *text = self.accessibilityValue;
    if (index < 0 || (NSUInteger)index > text.length) return NSNotFound;
    NSUInteger line = 0, start = 0, end = 0;
    while (start < (NSUInteger)index) {
        [text getLineStart:NULL end:&end contentsEnd:NULL forRange:NSMakeRange(start, 0)];
        if (end > (NSUInteger)index || end <= start) break;
        line++; start = end;
    }
    return line;
}
- (NSRange)accessibilityRangeForLine:(NSInteger)line {
    NSString *text = self.accessibilityValue;
    if (line < 0) return NSMakeRange(NSNotFound, 0);
    NSUInteger start = 0, end = 0;
    for (NSInteger index = 0; index <= line; index++) {
        if (start >= text.length) {
            if (index == line && (text.length == 0 || [@"\r\n\u2028\u2029" rangeOfString:[text substringFromIndex:text.length - 1]].location != NSNotFound)) return NSMakeRange(start, 0);
            return NSMakeRange(NSNotFound, 0);
        }
        [text getLineStart:NULL end:&end contentsEnd:NULL forRange:NSMakeRange(start, 0)];
        if (index == line) return NSMakeRange(start, end - start);
        start = end;
    }
    return NSMakeRange(NSNotFound, 0);
}
- (NSInteger)accessibilityInsertionPointLineNumber { return [self accessibilityLineForIndex:self.accessibilitySelectedTextRange.location]; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilitySelectedText:) || selector == @selector(setAccessibilitySelectedTextRange:))
        return [self.data[@"editable"] boolValue] && ![self.data[@"protected"] boolValue] && self.isAccessibilityEnabled;
    // Exact glyph geometry is a separate capability. Do not report the whole
    // control as if it were the bounds of each character range.
    if (selector == @selector(accessibilityFrameForRange:) || selector == @selector(accessibilityRangeForPosition:)) return NO;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

// AppKit determines external mutability from the implemented setters. Keep
// read-only elements free of editor setters, in addition to checking requests.
@implementation AXBEditableTextNode
- (void)setAccessibilityValue:(id)value { (void)[self queue:@"setValue" value:value]; }
- (void)setAccessibilitySelectedTextRange:(NSRange)range {
    (void)[self queue:@"setSelection" value:@[@(range.location), @(range.length)]];
}
- (void)setAccessibilitySelectedText:(NSString *)text { (void)[self queue:@"replaceSelection" value:text]; }
@end

static id DeepestChildrenHit(NSArray *children, NSPoint point) {
    id caption = nil;
    for (id child in [children reverseObjectEnumerator]) {
        id found = DeepestHit(child, point);
        if (!found) continue;
        // Static captions and grouping boxes do not intercept 4D mouse input.
        // Match the host's overlap check, while retaining these reading stops
        // when no control occupies the point. Other controls remain obstacles.
        if ([found isKindOfClass:AXBNode.class] &&
            [@[@"text", @"group"] containsObject:((AXBNode *)found).data[@"role"]]) {
            if (!caption) caption = found;
            continue;
        }
        return found;
    }
    return caption;
}

static id DeepestHit(id element, NSPoint point) {
    NSRect frame = [element isKindOfClass:AXBNode.class] ? [(AXBNode *)element hitFrame] : [element accessibilityFrame];
    if (![element isAccessibilityElement] || !NSPointInRect(point, frame)) return nil;
    if ([element isKindOfClass:AXBGridNode.class]) return [element accessibilityHitTest:point];
    return DeepestChildrenHit([element accessibilityChildren], point) ?: element;
}

static NSArray *TopLevelNodes(AXBWindowView *view) {
    if (!view.live) return @[];
    return [view.nodes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(AXBNode *node, NSDictionary *bindings) {
        (void)bindings; return node.isAccessibilityElement && !node.data[@"parent"];
    }]];
}

static id DeepestFormHit(AXBWindowView *view, NSPoint point) {
    if (!view.live || !view.session.snapshot || !NSPointInRect(point, view.accessibilityFrame)) return nil;
    return DeepestChildrenHit(TopLevelNodes(view), point) ?: (view.rootContainer ?: view.element);
}

static BOOL IsNativeControl(NSView *view) {
    return [view isKindOfClass:NSControl.class] || [view isKindOfClass:NSClassFromString(@"WKWebView")] || view.isAccessibilityElement;
}

// AppKit starts AX position lookup at the physical view beneath the point.
// Put virtual children under the common native drawing container, rather than
// beside it, so an opaque form view cannot hide them from that lookup.
static NSView *NativeContainer(NSWindow *window, NSDictionary *snapshot, NSView *managedRoot) {
    NSView *content = window.contentView;
    NSView *common = nil;
    for (NSDictionary *data in snapshot[@"nodes"]) {
        if (![data[@"visible"] boolValue]) continue;
        NSArray *f = data[@"frame"];
        NSRect frame = NSMakeRect([f[0] doubleValue], [f[1] doubleValue], [f[2] doubleValue], [f[3] doubleValue]);
        NSArray *clip = data[@"clip"];
        if (clip) frame = NSIntersectionRect(frame, NSMakeRect([clip[0] doubleValue], [clip[1] doubleValue], [clip[2] doubleValue], [clip[3] doubleValue]));
        frame = NSIntersectionRect(frame, NSMakeRect(0, 0, NSWidth(content.bounds), NSHeight(content.bounds)));
        if (NSIsEmptyRect(frame)) continue;
        NSPoint point = NSMakePoint(NSMinX(content.bounds) + NSMidX(frame),
            content.isFlipped ? NSMinY(content.bounds) + NSMidY(frame) : NSMaxY(content.bounds) - NSMidY(frame));
        NSView *hit = [content hitTest:[content convertPoint:point toView:content.superview]];
        if (!hit || ![hit isDescendantOf:content]) continue;
        if (!common) common = hit;
        while (common && ![hit isDescendantOf:common]) common = common.superview;
    }
    // Never turn a native control into the parent of a second representation.
    while (common && common != content && common != managedRoot && IsNativeControl(common)) common = common.superview;
    return common ?: content;
}

// Keep the transparent hit-test anchor under the original drawing container.
// A separate common ancestor can group its virtual children with native web
// views without moving any host view or replacing WebKit's accessibility tree.
static NSView *NativeWebContainer(NSView *anchor) {
    NSView *content = anchor.window.contentView;
    if (!content) return nil;
    NSView *common = anchor;
    BOOL hasWeb = NO;
    NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:content];
    NSUInteger visited = 0;
    while (pending.count && visited++ < 4096) {
        NSView *view = pending.lastObject; [pending removeLastObject];
        if (view.hiddenOrHasHiddenAncestor) continue;
        if ([view isKindOfClass:NSClassFromString(@"WKWebView")]) {
            if (NSIsEmptyRect(NSIntersectionRect([view convertRect:view.bounds toView:content], content.bounds))) continue;
            hasWeb = YES;
            while (common && ![view isDescendantOf:common]) common = common.superview;
        } else [pending addObjectsFromArray:view.subviews];
    }
    // Partial or excessively large view trees keep the original separate root.
    if (!hasWeb || pending.count || !common || [common isKindOfClass:NSControl.class]) return nil;
    return NSEqualRects([common convertRect:common.bounds toView:content], content.bounds) ? common : nil;
}

// Only an ignored NSView using inherited accessibility behavior is composed.
// Restore that role value explicitly, never with nil. Other nullable metadata
// can have computed defaults that no public setter restores. Keep labels,
// identifiers and action receipts on the bridge-owned status element.
@interface AXBNativeRoot : NSObject
@property(nonatomic, weak) NSView *container;
@property(nonatomic, weak) NSView *yieldedContainer;
@property(nonatomic, strong) NSArray *writtenOrder;
- (BOOL)attachTo:(NSView *)container;
- (BOOL)validateChildren:(NSArray *)nodes;
- (BOOL)writeOrder:(NSArray *)order;
- (void)restore;
@end

static BOOL InheritsViewMethod(NSView *view, SEL selector) {
    Method base = class_getInstanceMethod(NSView.class, selector);
    Method actual = class_getInstanceMethod(object_getClass(view), selector);
    return base && actual && method_getImplementation(base) == method_getImplementation(actual);
}

@implementation AXBNativeRoot
- (void)restore {
    NSView *container = self.container;
    if (container) {
        if (self.writtenOrder && [container.accessibilityChildrenInNavigationOrder isEqual:self.writtenOrder])
            container.accessibilityChildrenInNavigationOrder = nil;
        if (container.isAccessibilityElement) container.accessibilityElement = NO;
        if ([container.accessibilityRole isEqual:NSAccessibilityGroupRole])
            container.accessibilityRole = NSAccessibilityUnknownRole;
    }
    self.container = nil; self.writtenOrder = nil;
}
- (BOOL)validateChildren:(NSArray *)nodes {
    NSView *container = self.container;
    if (!container) return NO;
    NSArray *children = container.accessibilityChildren ?: @[];
    NSSet *childSet = [NSSet setWithArray:children];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id legacyChildren = [container accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
#pragma clang diagnostic pop
    BOOL compatible = [legacyChildren isKindOfClass:NSArray.class] &&
        [[NSSet setWithArray:legacyChildren] isEqual:childSet] && childSet.count == children.count;
    id parent = container.accessibilityParent;
    compatible = compatible && [parent respondsToSelector:@selector(accessibilityChildren)] &&
        [[parent accessibilityChildren] containsObject:container];
    for (id node in nodes) if (![childSet containsObject:node]) compatible = NO;
    for (id child in children) {
        if (![child respondsToSelector:@selector(accessibilityParent)] || [child accessibilityParent] != container ||
            ![child respondsToSelector:@selector(accessibilityFrame)]) compatible = NO;
    }
    if (!compatible) { self.yieldedContainer = container; [self restore]; }
    return compatible;
}
- (BOOL)attachTo:(NSView *)container {
    if (container != self.container) {
        [self restore];
        // Inspect actual methods, including an observation subclass, without
        // replacing a host class or depending on any private class name.
        if (!container || container == self.yieldedContainer ||
            container.isAccessibilityElement || ![container.accessibilityRole isEqual:NSAccessibilityUnknownRole]) return NO;
        static BOOL defaultRoleUnknown;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ defaultRoleUnknown = [[[NSView new] accessibilityRole] isEqual:NSAccessibilityUnknownRole]; });
        if (!defaultRoleUnknown) return NO;
        // Custom providers keep their original integration path. In particular,
        // an explicit legacy ignored getter can disagree with the modern BOOL.
        NSArray<NSString *> *selectors = @[@"isAccessibilityElement", @"setAccessibilityElement:",
            @"accessibilityRole", @"setAccessibilityRole:", @"accessibilityRoleDescription", @"accessibilityChildren",
            @"accessibilityChildrenInNavigationOrder", @"accessibilityIsIgnored",
            @"setAccessibilityChildrenInNavigationOrder:", @"accessibilityAttributeValue:", @"accessibilityAttributeNames"];
        for (NSString *name in selectors) if (!InheritsViewMethod(container, NSSelectorFromString(name))) return NO;
        NSArray *original = container.accessibilityChildrenInNavigationOrder;
        // NSView's navigation setter accepts nil as a return to computed order.
        // This fixed policy is checked by the baseline and dynamic-child tests.
        container.accessibilityChildrenInNavigationOrder = nil;
        NSArray *computed = container.accessibilityChildrenInNavigationOrder;
        if (original && ![original isEqual:computed]) {
            container.accessibilityChildrenInNavigationOrder = original;
            self.yieldedContainer = container;
            return NO;
        }
        self.container = container;
        container.accessibilityRole = NSAccessibilityGroupRole;
        container.accessibilityElement = YES;
        if (!container.isAccessibilityElement || ![container.accessibilityRole isEqual:NSAccessibilityGroupRole]) {
            self.yieldedContainer = container; [self restore]; return NO;
        }
    }
    return container != nil;
}
- (BOOL)writeOrder:(NSArray *)order {
    NSView *container = self.container;
    if (!container) return NO;
    if (!container.isAccessibilityElement || ![container.accessibilityRole isEqual:NSAccessibilityGroupRole] || (self.writtenOrder &&
        ![container.accessibilityChildrenInNavigationOrder isEqual:self.writtenOrder])) {
        self.yieldedContainer = container;
        [self restore];
        return NO;
    }
    if (![order isEqual:self.writtenOrder]) {
        container.accessibilityChildrenInNavigationOrder = order;
        self.writtenOrder = order;
        if (![container.accessibilityChildrenInNavigationOrder isEqual:order]) {
            self.yieldedContainer = container; [self restore]; return NO;
        }
    }
    return YES;
}
@end

static NSArray *MixedNavigationChildren(NSArray *children, NSWindow *window) {
    NSArray *(^position)(id) = ^NSArray *(id child) {
        if ([child isKindOfClass:AXBNode.class]) {
            AXBNode *node = child;
            NSArray *navigation = node.data[@"navigation"];
            return navigation.count >= 2 ? navigation : @[node.data[@"frame"][1], node.data[@"frame"][0]];
        }
        NSRect frame = [window.contentView convertRect:[window convertRectFromScreen:[child accessibilityFrame]] fromView:nil];
        CGFloat top = window.contentView.isFlipped ? NSMinY(frame) - NSMinY(window.contentView.bounds) : NSMaxY(window.contentView.bounds) - NSMaxY(frame);
        return @[@(top), @(NSMinX(frame) - NSMinX(window.contentView.bounds))];
    };
    return [children sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
        NSArray *left = position(a), *right = position(b);
        for (NSUInteger i = 0; i < MIN(left.count, right.count); i++) {
            NSComparisonResult result = [left[i] compare:right[i]];
            if (result != NSOrderedSame) return result;
        }
        return left.count < right.count ? NSOrderedAscending : left.count > right.count ? NSOrderedDescending : NSOrderedSame;
    }];
}

@implementation AXBWindowElement
- (BOOL)isAccessibilityElement { return self.owner.live && self.owner.session.snapshot != nil; }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityIdentifier { return self.identifier; }
- (NSString *)accessibilityLabel { return self.owner.session.snapshot[@"label"]; }
- (id)accessibilityParent { return self.owner.superview ? NSAccessibilityUnignoredAncestor(self.owner.superview) : nil; }
- (id)accessibilityWindow { return self.owner.window; }
- (id)accessibilityTopLevelUIElement { return self.owner.window; }
- (NSRect)accessibilityFrame { return self.owner && !self.owner.rootContainer ? self.owner.accessibilityFrame : NSZeroRect; }
- (id)accessibilityFocusedUIElement { return [self.owner accessibilityFocusedUIElement]; }
- (NSString *)accessibilityHelp {
    NSDictionary *activity = self.owner.session.activity;
    if ([activity[@"busy"] boolValue]) return [activity[@"delivered"] boolValue] ? @"Waiting for the application to complete the action" : @"Action queued";
    return activity[@"result"][@"message"] ?: @"Ready";
}
- (NSArray *)accessibilityChildren {
    return self.owner.rootContainer ? @[] : TopLevelNodes(self.owner);
}
- (id)accessibilityHitTest:(NSPoint)point { return self.isAccessibilityElement ? DeepestFormHit(self.owner, point) : nil; }
- (NSArray *)accessibilityChildrenInNavigationOrder { return NavigationChildren(self.accessibilityChildren); }
@end

@implementation AXBWindowView
- (NSView *)rootContainer { return self.nativeRoot.container; }
- (void)refreshNativeRoot {
    if (!self.live || !self.session.snapshot || !self.window) return;
    NSView *previous = self.rootContainer;
    NSView *container = NativeWebContainer(self.superview);
    if (container && !self.nativeRoot) self.nativeRoot = [AXBNativeRoot new];
    if ([self.nativeRoot attachTo:container] &&
        [self.nativeRoot validateChildren:[@[self.element] arrayByAddingObjectsFromArray:TopLevelNodes(self)]]) {
        NSMutableArray *children = [container.accessibilityChildren mutableCopy] ?: [NSMutableArray new];
        // Keep the empty receipt group after all controls, while retaining the
        // complete child set required by AppKit's navigation-order contract.
        [children removeObjectIdenticalTo:self.element];
        [self.nativeRoot writeOrder:[MixedNavigationChildren(children, self.window) arrayByAddingObject:self.element]];
    }
    if (previous != self.rootContainer) NSAccessibilityPostNotification(self.window, NSAccessibilityLayoutChangedNotification);
}
- (void)expectCheckboxFrom:(id<NSAccessibility>)element previousValue:(NSNumber *)value {
    NSString *action = self.session.activity[@"id"];
    if (action && element && value)
        self.actionFeedback = @{@"id": action, @"control": element, @"value": value};
}
- (void)expectDisclosureFrom:(id<NSAccessibility>)element previousValue:(NSNumber *)value {
    NSString *action = self.session.activity[@"id"];
    if (action && element && value && [[element accessibilityRole] isEqual:NSAccessibilityDisclosureTriangleRole])
        self.actionFeedback = @{@"id": action, @"control": element, @"value": value,
            @"role": NSAccessibilityDisclosureTriangleRole, @"label": [element accessibilityLabel] ?: @""};
}
- (void)expectPopupFrom:(id)element {
    NSString *action = self.session.activity[@"id"];
    if (action) self.popupRequest = @{@"id": action, @"element": element};
}
- (void)adoptPopupMenu:(NSMenu *)menu {
    NSDictionary *request = self.popupRequest;
    self.popupRequest = nil;
    [self restorePopupMenu];
    id origin = request[@"element"];
    NSDictionary *activity = self.session.activity;
    // 4D attaches its drawn grid popup to the window. Adopt only the menu
    // opened by the verified native click for this still-live control.
    // Preserve native controls, the menu bar and menus from other windows.
    if (!self.window.isKeyWindow || !NSApp.isActive || !origin || ![origin isAccessibilityElement] ||
        ![request[@"nativeInput"] boolValue] || !AXBGridElementBelongsToView(origin, self) ||
        ![[origin accessibilityRole] isEqual:NSAccessibilityPopUpButtonRole] ||
        ![activity[@"busy"] boolValue] || ![activity[@"delivered"] boolValue] || ![activity[@"id"] isEqual:request[@"id"]] ||
        menu == NSApp.mainMenu || menu.supermenu || menu.accessibilityParent != self.window) return;
    self.menuNativeParent = menu.accessibilityParent;
    self.adoptedMenu = menu;
    menu.accessibilityParent = origin;
    [self.session noteMenuForControlInput:request[@"id"]];
}
- (void)restorePopupMenu {
    if (self.adoptedMenu && AXBGridElementBelongsToView(self.adoptedMenu.accessibilityParent, self))
        self.adoptedMenu.accessibilityParent = self.menuNativeParent;
    self.adoptedMenu = nil;
    self.menuNativeParent = nil;
}
- (void)restoreNativeFocus {
    id focused = NSApp.accessibilityApplicationFocusedUIElement;
    if (([focused isKindOfClass:AXBNode.class] && ((AXBNode *)focused).owner == self) || AXBGridElementBelongsToView(focused, self) || (self.menuFocus && focused == self.menuFocus)) {
        // The user may have moved into a different native editor while the
        // application AX focus override still points at our previous node.
        NSWindow *window = NSApp.keyWindow;
        id native = [window accessibilityFocusedUIElement];
        if ([native isKindOfClass:AXBNode.class] || AXBGridElementBelongsToView(native, self) || native == self || native == self.element || native == self.rootContainer || native == self.menuFocus) native = nil;
        if (!native && self.nativeFocus && self.nativeFocus != self.rootContainer &&
            [self.nativeFocus respondsToSelector:@selector(isAccessibilityElement)] && [self.nativeFocus isAccessibilityElement] &&
            [self.nativeFocus respondsToSelector:@selector(accessibilityWindow)] &&
            [self.nativeFocus accessibilityWindow] == window) native = self.nativeFocus;
        NSApp.accessibilityApplicationFocusedUIElement = native ?: window;
    }
    self.menuFocus = nil;
}
- (id)accessibilityFocusedUIElement {
    for (AXBNode *node in self.nodes) if (node.isAccessibilityFocused) return [node isKindOfClass:AXBGridNode.class] ? [node accessibilityFocusedUIElement] : node;
    return nil;
}
- (BOOL)isFlipped { return YES; }
// Keep physical mouse routing untouched. AppKit can hit-test a non-view
// accessibility child even though it skips this transparent geometry anchor.
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren {
    if (!self.live || !self.session.snapshot || !self.element) return @[];
    return self.rootContainer ? [@[self.element] arrayByAddingObjectsFromArray:TopLevelNodes(self)] : @[self.element];
}
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)canAct {
    if ([NSRunLoop.currentRunLoop.currentMode isEqual:NSEventTrackingRunLoopMode]) return NO;
    if (!(self.live && self.session.active && [self.session.snapshot[@"enabled"] boolValue] && self.window.isVisible &&
        !self.hidden && !self.window.attachedSheet && (!NSApp.modalWindow || NSApp.modalWindow == self.window))) return NO;
    // orderedWindows remains useful when the whole application is inactive.
    // A 4D dialog need not have entered an AppKit modal session to block its owner.
    for (NSWindow *window in NSApp.orderedWindows) if (window.isVisible && window.canBecomeKeyWindow) return window == self.window;
    return NO;
}
- (void)refreshComboPopup {
    // 4D's combo is drawn in its shared view. Its real choice list is a native
    // table in a non-key floating window, anchored to the focused combo edge.
    // Require one exact anchor and one native table; unrelated windows and
    // menus must never make a control appear expanded.
    AXBNode *owner = nil;
    NSTableView *list = nil;
    if (self.live && self.window.isKeyWindow && NSApp.isActive) {
        for (AXBNode *node in self.nodes) if ([node.data[@"combo"] boolValue] && [node.data[@"focused"] boolValue] && node.isAccessibilityElement) {
            NSRect field = node.accessibilityFrame;
            NSUInteger matches = 0;
            for (NSWindow *popup in NSApp.windows) {
                if (!popup.isVisible || !popup.contentView || popup == self.window || popup.canBecomeKeyWindow || popup.level <= self.window.level) continue;
                NSRect frame = popup.frame;
                if (fabs(NSMinX(frame) - NSMinX(field)) > 2 || fabs(NSWidth(frame) - NSWidth(field)) > 2 ||
                    (fabs(NSMaxY(frame) - NSMinY(field)) > 2 && fabs(NSMinY(frame) - NSMaxY(field)) > 2)) continue;
                NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:popup.contentView];
                while (pending.count) {
                    NSView *native = pending.lastObject; [pending removeLastObject];
                    if ([native isKindOfClass:NSTableView.class] && native.isAccessibilityElement) { list = (NSTableView *)native; matches++; }
                    else [pending addObjectsFromArray:native.subviews];
                }
            }
            if (matches == 1 && !owner) owner = node;
            else if (matches) { owner = nil; list = nil; break; }
        }
    }
    if (!owner) list = nil;
    AXBNode *previous = self.comboOwner;
    NSScrollView *previousScroll = self.comboList.enclosingScrollView;
    NSWindow *previousWindow = self.comboList.window;
    id nativeParent = self.comboNativeParent;
    NSArray *windowChildren = self.comboWindowChildren;
    BOOL windowAccessible = self.comboWindowAccessible;
    BOOL changed = previous != owner || self.comboList != list;
    self.comboOwner = owner; self.comboList = list;
    if (changed) {
        // Attach the native popup beneath its combo, matching AppKit's own
        // combo hierarchy. Keep the existing table/row providers and actions.
        // Restore both overrides on dismissal, focus loss or owner teardown.
        if (previousScroll.accessibilityParent == previous) previousScroll.accessibilityParent = nativeParent;
        if (previousWindow) {
            previousWindow.accessibilityChildren = windowChildren;
            previousWindow.accessibilityElement = windowAccessible;
        }
        self.comboNativeParent = nil;
        self.comboWindowChildren = nil;
        if (owner) {
            self.comboNativeParent = list.enclosingScrollView.accessibilityParent;
            self.comboWindowAccessible = list.window.isAccessibilityElement;
            self.comboWindowChildren = list.window.accessibilityChildren;
            list.enclosingScrollView.accessibilityParent = owner;
            list.window.accessibilityChildren = @[];
            list.window.accessibilityElement = NO;
        }
        if (previous) NSAccessibilityPostNotification(previous, NSAccessibilityValueChangedNotification);
        if (owner) NSAccessibilityPostNotification(owner, NSAccessibilityValueChangedNotification);
        if (self.window) NSAccessibilityPostNotification(self.window, NSAccessibilityLayoutChangedNotification);
    }
}
- (void)refresh {
    NSDictionary *snapshot = self.session.snapshot;
    if (!self.session.active) { [self invalidate]; return; }
    if (!snapshot) return;
    NSWindow *window = self.window;
    AXBLayoutObserve(window);
    NSView *container = NativeContainer(window, snapshot, self.rootContainer);
    if (container != self.superview) { [self.nativeRoot restore]; [self removeFromSuperview]; [container addSubview:self]; }
    self.frame = [container convertRect:window.contentView.bounds fromView:window.contentView];
    self.bounds = NSMakeRect(0, 0, NSWidth(window.contentView.bounds), NSHeight(window.contentView.bounds));
    NSMutableDictionary *old = [NSMutableDictionary new];
    NSMutableDictionary *oldTabs = [NSMutableDictionary new];
    for (AXBNode *node in self.nodes) {
        old[node.data[@"id"]] = node;
        if ([node.data[@"role"] isEqual:@"tabgroup"])
            oldTabs[node.data[@"id"]] = [node.accessibilitySelectedChildren valueForKeyPath:@"data.id"];
    }
    NSMutableArray *next = [NSMutableArray new];
    NSMutableArray<AXBNode *> *retired = [NSMutableArray new];
    NSMutableOrderedSet<AXBNode *> *changedValues = [NSMutableOrderedSet new];
    NSMutableOrderedSet<AXBNode *> *changedSelections = [NSMutableOrderedSet new];
    NSMutableOrderedSet<AXBNode *> *changedTextSelections = [NSMutableOrderedSet new];
    BOOL structureChanged = NO;
    for (NSDictionary *data in snapshot[@"nodes"]) {
        Class kind = @{@"textfield": AXBTextNode.class, @"table": AXBTableNode.class, @"row": AXBRowNode.class}[data[@"role"]] ?: AXBNode.class;
        if (data[@"grid"]) kind = AXBGridNode.class;
        if ([data[@"role"] isEqual:@"textfield"] && (!data[@"editable"] || [data[@"editable"] boolValue])) kind = AXBEditableTextNode.class;
        AXBNode *node = old[data[@"id"]];
        NSString *identifier = AXBNodeIdentifier(snapshot, data);
        if (node && (![node.identifier isEqual:identifier] || ![node.data[@"role"] isEqual:data[@"role"]] || [node.data[@"combo"] boolValue] != [data[@"combo"] boolValue] ||
            (node.data[@"grid"][@"outline"] != nil) != (data[@"grid"][@"outline"] != nil) || node.class != kind)) { [retired addObject:node]; node = nil; }
        if (!node) {
            node = [kind new]; node.owner = self; node.live = YES; structureChanged = YES;
        }
        BOOL valueChanged = node.data && (![node.data[@"value"] isEqual:data[@"value"]] ||
            ((node.data[@"valueDescription"] || data[@"valueDescription"]) && ![node.data[@"valueDescription"] isEqual:data[@"valueDescription"]]));
        BOOL gainedFocus = [data[@"focused"] boolValue] && ![node.data[@"focused"] boolValue];
        BOOL textSelectionChanged = node.data && ![node.data[@"selection"] isEqual:data[@"selection"]] && (node.data[@"selection"] || data[@"selection"]);
        BOOL selectionChanged = node.data && ![node.data[@"selected"] isEqual:data[@"selected"]] && [data[@"role"] isEqual:@"row"];
        for (NSString *key in @[@"visible", @"frame", @"clip", @"parent", @"index", @"label", @"labelledBy", @"linked", @"enabled"])
            if (node.data && (node.data[key] || data[key]) && ![node.data[key] isEqual:data[key]]) structureChanged = YES;
        node.data = data;
        node.identifier = identifier;
        node.revision = snapshot[@"revision"];
        if ([node isKindOfClass:AXBGridNode.class]) [(AXBGridNode *)node prepareGrid];
        [next addObject:node];
        [old removeObjectForKey:data[@"id"]];
        if (valueChanged) [changedValues addObject:node];
        if (selectionChanged) [changedSelections addObject:node];
        // Focus is announced below after the complete tree and application
        // focus are installed. Announcing a departing editor's cleared range
        // can otherwise speak over the button that just received focus.
        if (textSelectionChanged && [data[@"focused"] boolValue] && !gainedFocus)
            [changedTextSelections addObject:node];
    }
    for (AXBNode *node in old.allValues) {
        [retired addObject:node]; structureChanged = YES;
    }
    if (![self.nodes isEqualToArray:next]) structureChanged = YES;
    self.nodes = next;
    self.publishedSnapshot = snapshot;
    self.element.identifier = AXBRootIdentifier(snapshot);
    [self refreshComboPopup];
    id focused = self.accessibilityFocusedUIElement;
    BOOL focusChanged = NO;
    if (focused && self.window.isKeyWindow && NSApp.isActive && [self canAct]) {
        if (NSApp.accessibilityApplicationFocusedUIElement != focused) {
            id previous = NSApp.accessibilityApplicationFocusedUIElement;
            if (![previous isKindOfClass:AXBNode.class] && !AXBGridElementBelongsToView(previous, self) &&
                previous != self.menuFocus && previous != self.rootContainer && previous != self.element && previous != self &&
                [previous respondsToSelector:@selector(isAccessibilityElement)] && [previous isAccessibilityElement]) self.nativeFocus = previous;
            NSApp.accessibilityApplicationFocusedUIElement = focused;
            focusChanged = YES;
        }
    } else [self restoreNativeFocus];
    [self refreshNativeRoot];
    // Observers may read immediately. Install the entire tree and focus first,
    // then publish semantic changes without treating ordinary typing as layout.
    for (AXBNode *node in retired) [node invalidate];
    for (AXBNode *node in self.nodes) if ([node isKindOfClass:AXBGridNode.class]) [(AXBGridNode *)node refreshGrid];
    for (AXBNode *node in changedValues) {
        NSAccessibilityPostNotification(node, NSAccessibilityValueChangedNotification);
        if ([node isKindOfClass:AXBRowNode.class]) {
            AXBSummaryCell *cell = ((AXBRowNode *)node).summaryCell;
            if (cell) NSAccessibilityPostNotification(cell, NSAccessibilityValueChangedNotification);
        }
    }
    NSMutableOrderedSet *tables = [NSMutableOrderedSet new];
    for (AXBNode *node in changedSelections) if (node.accessibilityParent) [tables addObject:node.accessibilityParent];
    for (id table in tables) NSAccessibilityPostNotification(table, NSAccessibilitySelectedRowsChangedNotification);
    for (AXBNode *node in self.nodes) if ([node.data[@"role"] isEqual:@"tabgroup"] && oldTabs[node.data[@"id"]] &&
        ![oldTabs[node.data[@"id"]] isEqual:[node.accessibilitySelectedChildren valueForKeyPath:@"data.id"]]) {
        NSAccessibilityPostNotification(node, NSAccessibilitySelectedChildrenChangedNotification);
        NSAccessibilityPostNotification(node, NSAccessibilityValueChangedNotification);
    }
    for (AXBNode *node in changedTextSelections) NSAccessibilityPostNotification(node, NSAccessibilitySelectedTextChangedNotification);
    if (focusChanged) NSAccessibilityPostNotification(focused, NSAccessibilityFocusedUIElementChangedNotification);
    if (structureChanged) NSAccessibilityPostNotification(self.window, NSAccessibilityLayoutChangedNotification);
    NSDictionary *feedback = self.actionFeedback;
    if (([feedback[@"role"] isEqual:@"tab"] && focusChanged) ||
        (feedback[@"deadline"] && Now() >= [feedback[@"deadline"] doubleValue])) {
        self.actionFeedback = nil; feedback = nil;
    }
    NSDictionary *activity = self.session.activity;
    if (self.popupRequest && (![activity[@"busy"] boolValue] || ![activity[@"id"] isEqual:self.popupRequest[@"id"]])) self.popupRequest = nil;
    if (self.adoptedMenu && ![self.adoptedMenu.accessibilityParent isAccessibilityElement]) [self restorePopupMenu];
    NSDictionary *result = activity[@"result"];
    BOOL sameCellReveal = feedback[@"control"] && AXBGridRevealMatchesElement(feedback[@"control"], activity);
    if (feedback[@"control"] && [activity[@"busy"] boolValue] &&
        ![feedback[@"id"] isEqual:activity[@"id"]] && !sameCellReveal) {
        self.actionFeedback = nil; feedback = nil;
    }
    // VoiceOver can reveal the same cell while its changed value page arrives.
    // Keep the original completed receipt and deadline across that request.
    self.actionFeedback = ConfirmedControlFeedback(feedback, activity, Now());
    feedback = self.actionFeedback;
    if (feedback[@"result"]) result = feedback[@"result"];
    if (feedback && [feedback[@"id"] isEqual:result[@"id"]]) {
        self.actionFeedback = nil; // A receipt replay must never repeat speech.
        if ((![activity[@"busy"] boolValue] || sameCellReveal) && [result[@"status"] isEqual:@"completed"] && NSApp.isActive && self.window.isKeyWindow && [self canAct]) {
            id<NSAccessibility> control = feedback[@"control"];
            if (control) {
                // A native click can complete before its value page arrives.
                // Disclosure also needs receipt-backed feedback when VoiceOver
                // ignores the stationary triangle's value notification.
                BOOL disclosure = [feedback[@"role"] isEqual:NSAccessibilityDisclosureTriangleRole];
                BOOL matchingDisclosure = disclosure && [[control accessibilityRole] isEqual:NSAccessibilityDisclosureTriangleRole] &&
                    [control isAccessibilityEnabled] && [[control accessibilityLabel] isEqual:feedback[@"label"]];
                if ([control isAccessibilityElement] && (matchingDisclosure ||
                    (!disclosure && [[control accessibilityRole] isEqual:NSAccessibilityCheckBoxRole]))) {
                    NSNumber *value = [control accessibilityValue];
                    if ([value isKindOfClass:NSNumber.class] && [value isEqual:feedback[@"value"]]) {
                        NSNumber *deadline = feedback[@"deadline"] ?: @(Now()+2);
                        if (Now() < deadline.doubleValue) {
                            NSMutableDictionary *waiting = [feedback mutableCopy]; waiting[@"deadline"] = deadline;
                            self.actionFeedback = waiting;
                        }
                    } else if ([value isKindOfClass:NSNumber.class]) {
                        NSString *key = disclosure ? (value.boolValue ? @"expanded" : @"collapsed") :
                            value.integerValue == 2 ? @"mixed" : value.boolValue ? @"checked" : @"unchecked";
                        NSString *state = [[NSBundle bundleForClass:AXBNode.class] localizedStringForKey:key value:key table:@"AccessibilityBridge"];
                        // A confirmed group action must be heard over the row
                        // context or interaction hints VoiceOver is still reading.
                        // AppKit's announcement contract recommends the application
                        // element. Keep the owning-window guards above unchanged.
                        id announcementElement = disclosure ? (id)NSApp : self.window;
                        NSAccessibilityPostNotificationWithUserInfo(announcementElement, NSAccessibilityAnnouncementRequestedNotification,
                            @{NSAccessibilityAnnouncementKey: [NSString stringWithFormat:@"%@: %@", [control accessibilityLabel] ?: @"", state],
                              NSAccessibilityPriorityKey: @(disclosure ? NSAccessibilityPriorityHigh : NSAccessibilityPriorityMedium)});
                    }
                }
            } else for (AXBNode *node in self.nodes) {
                if (![node.data[@"id"] isEqual:feedback[@"node"]] || ![node.data[@"role"] isEqual:feedback[@"role"]] ||
                    ![node.data[@"label"] isEqual:feedback[@"label"]] ||
                    !node.isAccessibilityElement || !node.isAccessibilityEnabled || ([feedback[@"role"] isEqual:@"checkbox"] && node.isAccessibilityFocused) ||
                    ([feedback[@"role"] isEqual:@"tab"] && focusChanged)) continue;
                if ([node.data[@"value"] isEqual:feedback[@"value"]]) {
                    if ([feedback[@"role"] isEqual:@"tab"] && ![node.data[@"value"] boolValue]) {
                        // Native dispatch can be acknowledged before the form
                        // process applies selection. Keep this exact request
                        // briefly; a new action or real focus transfer cancels it.
                        NSNumber *deadline = feedback[@"deadline"] ?: @(Now()+2);
                        if (Now() < deadline.doubleValue) {
                            NSMutableDictionary *waiting = [feedback mutableCopy]; waiting[@"deadline"] = deadline;
                            self.actionFeedback = waiting;
                        }
                    }
                    continue;
                }
                if ([feedback[@"role"] isEqual:@"tab"] && ![node.data[@"value"] boolValue]) continue;
                NSString *state = node.accessibilityValueDescription ?: [node.accessibilityValue description];
                if ([feedback[@"role"] isEqual:@"checkbox"]) {
                    NSBundle *bundle = [NSBundle bundleForClass:AXBNode.class];
                    NSString *key = [node.data[@"value"] integerValue] == 2 ? @"mixed" : [node.data[@"value"] boolValue] ? @"checked" : @"unchecked";
                    state = [bundle localizedStringForKey:key value:key table:@"AccessibilityBridge"];
                } else if ([feedback[@"role"] isEqual:@"tab"]) {
                    state = [[NSBundle bundleForClass:AXBNode.class] localizedStringForKey:@"selected" value:@"selected" table:@"AccessibilityBridge"];
                }
                NSString *announcement = [NSString stringWithFormat:@"%@: %@", node.accessibilityLabel, state];
                NSAccessibilityPostNotificationWithUserInfo(self.window, NSAccessibilityAnnouncementRequestedNotification,
                    @{NSAccessibilityAnnouncementKey: announcement, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
            }
        }
    } else if (feedback && [activity[@"busy"] boolValue] && ![feedback[@"id"] isEqual:activity[@"id"]]) self.actionFeedback = nil;
}
- (void)invalidate {
    if (!self.live) return;
    self.live = NO;
    [self refreshComboPopup];
    [self restoreNativeFocus];
    [self restorePopupMenu];
    self.popupRequest = nil;
    [self.nativeRoot restore];
    [self.session invalidate];
    for (AXBNode *node in self.nodes) [node invalidate];
    NSAccessibilityPostNotification(self.element, NSAccessibilityUIElementDestroyedNotification);
    NSWindow *window = self.window;
    [self removeFromSuperview];
    for (id observer in self.focusObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    self.focusObservers = nil;
    self.nodes = @[];
    self.publishedSnapshot = nil;
    self.actionFeedback = nil;
    self.comboOwner = nil; self.comboList = nil;
    AXBLayoutForget(window);
    if (window) NSAccessibilityPostNotification(window, NSAccessibilityLayoutChangedNotification);
}
- (void)dealloc {
    for (id observer in _focusObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
}
@end

static void ScheduleRefresh(AXBSession *session, void *nativeWindow) {
    @synchronized(registryLock) {
        if ([refreshPending containsObject:session.identifier]) return;
        [refreshPending addObject:session.identifier];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(registryLock) { [refreshPending removeObject:session.identifier]; }
        if (!session.active) return;
        if (!views) views = [NSMutableDictionary new];
        AXBWindowView *view = views[session.identifier];
        if (!view) {
            NSWindow *window = nil;
            // An opaque SDK handle is never dereferenced. Only identity matches
            // against AppKit's live window list can authorize attachment.
            for (NSWindow *candidate in NSApp.windows) if ((__bridge void *)candidate == nativeWindow) { window = candidate; break; }
            NSString *error = window.contentView ? nil : @"SDK handle does not match a live native window";
            for (AXBWindowView *existing in views.allValues) if (existing.window == window) error = @"window already has another session";
            if (error) {
                // A window may close before this queued attachment runs.
                // Retire its allocation instead of retaining a dead binding.
                AXBDetach(session.identifier);
                return;
            }
            view = [[AXBWindowView alloc] initWithFrame:window.contentView.bounds];
            view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            view.session = session;
            view.element = [AXBWindowElement new];
            view.element.owner = view;
            view.element.identifier = AXBRootIdentifier(session.snapshot);
            view.live = YES;
            AXBLayoutObserve(window);
            [window.contentView addSubview:view];
            views[session.identifier] = view;
            __weak AXBWindowView *weakView = view;
            view.focusObservers = @[
                [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
                    if (notification.object == weakView.window) [weakView refreshNativeRoot];
                    [weakView refreshComboPopup];
                }],
                [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification object:window queue:nil usingBlock:^(NSNotification *notification) {
                    (void)notification; [weakView restoreNativeFocus]; [weakView restorePopupMenu]; weakView.popupRequest = nil;
                }],
                [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
                    if (!weakView.window.isKeyWindow) return;
                    [weakView adoptPopupMenu:notification.object];
                    [weakView restoreNativeFocus];
                    id menu = notification.object;
                    if ([menu respondsToSelector:@selector(accessibilityRole)] && [[menu accessibilityRole] isEqual:NSAccessibilityMenuRole]) {
                        weakView.menuFocus = menu;
                        NSApp.accessibilityApplicationFocusedUIElement = menu;
                        NSAccessibilityPostNotification(menu, NSAccessibilityFocusedUIElementChangedNotification);
                    }
                }],
                [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidEndTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
                    if (weakView.menuFocus == notification.object) [weakView restoreNativeFocus];
                    if (weakView.adoptedMenu == notification.object) [weakView restorePopupMenu];
                }]];
            @synchronized(registryLock) { bindings[session.identifier][@"state"] = @"attached"; }
        }
        [view refresh];
    });
}

NSString *AXBOpen(NSInteger windowID, NSInteger processID, void *nativeWindow) {
    Init();
    if (windowID <= 0 || processID <= 0 || !nativeWindow)
        return JSON(@{@"ok": @NO, @"error": @"invalid window or process"});
    AXBSession *session;
    @synchronized(registryLock) {
        if (stopped) return JSON(@{@"ok": @NO, @"error": @"plugin stopped"});
        if (sessions.count >= 64) return JSON(@{@"ok": @NO, @"error": @"too many active sessions"});
        for (NSDictionary *binding in bindings.allValues)
            if ([binding[@"native"] pointerValue] == nativeWindow)
                return JSON(@{@"ok": @NO, @"error": @"window already has another session"});
        // Only this allocator creates identities. Exchange never creates a
        // session, so forgetting a closed identity cannot make a replay valid.
        NSString *identifier = NSUUID.UUID.UUIDString;
        session = [[AXBSession alloc] initWithIdentifier:identifier windowID:windowID];
        sessions[identifier] = session;
        bindings[identifier] = [@{@"process": @(processID), @"native": [NSValue valueWithPointer:nativeWindow], @"state": @"pending"} mutableCopy];
        // Register before returning, not during queued AppKit attachment: an
        // On Load handler can close its window before the first snapshot.
        // NotificationCenter is thread-safe. Only compare the opaque SDK
        // address with the actual notification object; never message it.
        bindings[identifier][@"closeObserver"] = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
            if ((__bridge void *)notification.object == nativeWindow) AXBDetach(identifier);
        }];
    }
    // Observe window closure even when initialization never publishes a tree.
    ScheduleRefresh(session, nativeWindow);
    return JSON(@{@"ok": @YES, @"session": session.identifier});
}

NSString *AXBExchange(NSInteger windowID, NSInteger processID, void *nativeWindow, NSString *sessionID, NSString *json) {
    Init();
    NSString *compactID = [sessionID stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSCharacterSet *invalidID = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    if (windowID <= 0 || processID <= 0 || !nativeWindow || compactID.length != 32 || [compactID rangeOfCharacterFromSet:invalidID].location != NSNotFound || json.length > AXBLimits::payload)
        return JSON(@{@"ok": @NO, @"error": @"invalid window, session, or payload size"});
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return JSON(@{@"ok": @NO, @"error": @"payload contains invalid Unicode"});
    id envelope = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *error = AXBValidateEnvelope(envelope);
    if (error) return JSON(@{@"ok": @NO, @"error": error});
    AXBSession *session;
    @synchronized(registryLock) {
        if (stopped) return JSON(@{@"ok": @NO, @"error": @"plugin stopped"});
        session = sessions[sessionID];
        if (!session) return JSON(@{@"ok": @NO, @"error": @"unknown or closed session"});
        if (session.windowID != windowID || [bindings[sessionID][@"process"] integerValue] != processID || [bindings[sessionID][@"native"] pointerValue] != nativeWindow)
            return JSON(@{@"ok": @NO, @"error": @"session window or process mismatch"});
        if (bindings[sessionID][@"error"]) return JSON(@{@"ok": @NO, @"error": bindings[sessionID][@"error"]});
    }
    NSMutableDictionary *response = [[session exchange:envelope now:Now()] mutableCopy];
    @synchronized(registryLock) { response[@"binding"] = bindings[sessionID][@"state"] ?: @"closed"; }
    if ([response[@"ok"] boolValue]) {
        ScheduleRefresh(session, nativeWindow);
        NSDictionary *controlInput = response[@"controlInput"];
        [response removeObjectForKey:@"controlInput"];
        if (controlInput) dispatch_async(dispatch_get_main_queue(), ^{
            BOOL accepted = NO;
            @try {
                AXBWindowView *view = views[session.identifier];
                NSDictionary *data = [session controlInputNode:controlInput];
                if (!data || ![view canAct] || !NSApp.isActive || !view.window.isKeyWindow) return;
                AXBNode *node = nil;
                for (AXBNode *candidate in view.nodes) if ([candidate.data[@"id"] isEqual:data[@"id"]]) { node = candidate; break; }
                if (!node || !node.isAccessibilityElement || !node.isAccessibilityEnabled) return;
                NSArray *frame = data[@"frame"];
                NSRect rect = NSMakeRect([frame[0] doubleValue], [frame[1] doubleValue], [frame[2] doubleValue], [frame[3] doubleValue]);
                // 4D draws the stepper's native-sized arrows at the leading edge.
                // Stay inside each half even when the form rectangle is larger.
                CGFloat direction = [data[@"operation"] isEqual:@"increment"] ? -1 : 1;
                NSPoint local = NSMakePoint(NSMinX(rect)+MIN(6, NSWidth(rect)/2), NSMidY(rect)+direction*MIN(4, NSHeight(rect)/4));
                id target = node;
                if ([@[@"gridPress", @"gridHeaderPress", @"gridSelect"] containsObject:data[@"operation"]]) {
                    if (![node isKindOfClass:AXBGridNode.class]) return;
                    target = [data[@"operation"] isEqual:@"gridHeaderPress"] ? [(AXBGridNode *)node headerForColumn:data[@"target"][@"column"]] :
                        [(AXBGridNode *)node controlForRow:data[@"target"][@"row"] column:data[@"target"][@"column"]];
                    if (![target isAccessibilityElement] || ![target isAccessibilityEnabled]) return;
                    local = NSMakePoint([controlInput[@"point"][0] doubleValue], [controlInput[@"point"][1] doubleValue]);
                }
                BOOL button = [data[@"operation"] isEqual:@"press"] && [@[@"button", @"tab"] containsObject:data[@"role"]];
                if (button) local = NSMakePoint([controlInput[@"point"][0] doubleValue], [controlInput[@"point"][1] doubleValue]);
                NSPoint point = [view convertPoint:local toView:nil];
                NSPoint screen = [view.window convertPointToScreen:point];
                if (!NSPointInRect(screen, [target accessibilityFrame]) || DeepestFormHit(view, screen) != target) return;
                NSView *content = view.window.contentView;
                NSPoint physicalPoint = [content.superview convertPoint:point fromView:nil];
                NSView *physical = [content hitTest:physicalPoint];
                if (!physical || ![physical isDescendantOf:view.superview]) return;
                // A native control or web view over the drawing canvas owns
                // this point. Never redirect its mouse input to a virtual node.
                for (NSView *ancestor = physical; ancestor && ancestor != content; ancestor = ancestor.superview)
                    if (ancestor != view.rootContainer && IsNativeControl(ancestor)) return;
                if (view.popupRequest[@"element"] == target && [view.popupRequest[@"id"] isEqual:controlInput[@"action"]])
                    view.popupRequest = @{@"element": target, @"id": controlInput[@"action"], @"nativeInput": @YES};
                NSEventModifierFlags flags = [data[@"toggleSelection"] boolValue] ? NSEventModifierFlagCommand : 0;
                NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:flags timestamp:Now()
                    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
                NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:flags timestamp:Now()
                    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
                // Mouse-down may enter AppKit's tracking loop. Queue its matching
                // release first, then synchronously dispatch to this exact window.
                // This keeps the control's normal focus behavior and On Clicked handler.
                [NSApp postEvent:up atStart:YES];
                // A button can enter a modal loop or retire its route before
                // sendEvent returns. Acknowledge verified dispatch, not its
                // business result, before entering that normal event path.
                if (button) [session finishControlInput:controlInput accepted:YES];
                [NSApp sendEvent:down];
                accepted = YES;
            } @finally {
                [session finishControlInput:controlInput accepted:accepted];
            }
        });
        NSDictionary *input = response[@"editorInput"];
        [response removeObjectForKey:@"editorInput"];
        if (input) dispatch_async(dispatch_get_main_queue(), ^{
            BOOL accepted = NO;
            @try {
                AXBWindowView *view = views[session.identifier];
                if (![session canPostEditorInput:input] || ![view canAct] || !NSApp.isActive || !view.window.isKeyWindow ||
                    ![view.window.firstResponder conformsToProtocol:@protocol(NSTextInputClient)]) return;
                if ([input[@"mode"] isEqual:@"insert"]) {
                    NSDictionary *node = [session editorInputNode:input];
                    if (!node) return;
                    id<NSTextInputClient> client = (id<NSTextInputClient>)view.window.firstResponder;
                    NSArray *selection = input[@"selection"], *frame = node[@"frame"];
                    NSRange range = NSMakeRange([selection[0] unsignedIntegerValue], [selection[1] unsignedIntegerValue]);
                    if (!NSEqualRanges(client.selectedRange, range) || client.hasMarkedText) return;
                    // 4D shares its native input view between controls. Verify its
                    // actual caret still lies inside the requested field before
                    // inserting a long value through the normal input-method path.
                    NSRange actual = NSMakeRange(NSNotFound, 0);
                    NSRect screen = [client firstRectForCharacterRange:NSMakeRange(range.location, 0) actualRange:&actual];
                    NSRect caret = [view.window.contentView convertRect:[view.window convertRectFromScreen:screen] fromView:nil];
                    if (!view.window.contentView.isFlipped) caret.origin.y = NSMaxY(view.window.contentView.bounds) - NSMaxY(caret);
                    NSRect field = NSMakeRect([frame[0] doubleValue], [frame[1] doubleValue], [frame[2] doubleValue], [frame[3] doubleValue]);
                    if (caret.size.height <= 0 || !NSIntersectsRect(NSInsetRect(caret, -1, 0), field)) return;
                    [client insertText:input[@"text"] replacementRange:NSMakeRange(NSNotFound, 0)];
                    accepted = YES;
                    return;
                }
                // A UTF-16 pair must enter as one keyboard event. Separate POST KEY
                // calls let 4D expose an unmatched surrogate between the two events.
                for (NSNumber *type in @[@(NSEventTypeKeyDown), @(NSEventTypeKeyUp)]) {
                    NSEvent *event = [NSEvent keyEventWithType:(NSEventType)type.unsignedIntegerValue location:NSZeroPoint modifierFlags:0
                        timestamp:Now() windowNumber:view.window.windowNumber context:nil characters:input[@"text"]
                        charactersIgnoringModifiers:input[@"text"] isARepeat:NO keyCode:0];
                    // 4D reads the underlying Quartz keyboard payload. Populate it
                    // too, so its editor receives the text rather than key code 0.
                    CGEventRef keyboard = CGEventCreateCopy(event.CGEvent);
                    UniChar characters[2];
                    [input[@"text"] getCharacters:characters range:NSMakeRange(0, 2)];
                    CGEventKeyboardSetUnicodeString(keyboard, 2, characters);
                    // Complete native delivery before acknowledging this input.
                    // A posted event can still be queued when 4D polls again.
                    [NSApp sendEvent:[NSEvent eventWithCGEvent:keyboard]];
                    CFRelease(keyboard);
                }
                accepted = YES;
            } @finally {
                [session finishEditorInput:input accepted:accepted];
            }
        });
    }
    return JSON(response);
}

void AXBDetach(NSString *sessionID, NSInteger processID) {
    Init();
    @synchronized(registryLock) {
        if (processID && [bindings[sessionID][@"process"] integerValue] != processID) return;
        id observer = bindings[sessionID][@"closeObserver"];
        if (observer) [NSNotificationCenter.defaultCenter removeObserver:observer];
        [sessions[sessionID] invalidate]; [sessions removeObjectForKey:sessionID]; [bindings removeObjectForKey:sessionID];
    }
    dispatch_block_t cleanup = ^{ [views[sessionID] invalidate]; [views removeObjectForKey:sessionID]; };
    if (NSThread.isMainThread) cleanup(); else dispatch_async(dispatch_get_main_queue(), cleanup);
}

void AXBInitialize(void) {
    Init();
    AXBLayoutInitialize();
    // 4D can close and reopen a database while this bundle remains loaded.
    // Shutdown has retired old sessions and completed native-view cleanup.
    @synchronized(registryLock) { stopped = NO; }
}

void AXBShutdown(void) {
    Init();
    @synchronized(registryLock) {
        stopped = YES;
        for (AXBSession *s in sessions.allValues) [s invalidate];
        for (NSDictionary *binding in bindings.allValues)
            if (binding[@"closeObserver"]) [NSNotificationCenter.defaultCenter removeObserver:binding[@"closeObserver"]];
        [sessions removeAllObjects]; [bindings removeAllObjects];
    }
    // Unload must wait until every AppKit object and queued refresh has gone.
    // No monitor is held, and cleanup never calls 4D or waits for the form.
    dispatch_block_t cleanup = ^{ for (AXBWindowView *v in views.allValues) [v invalidate]; [views removeAllObjects]; AXBLayoutShutdown(); };
    if (NSThread.isMainThread) cleanup(); else dispatch_sync(dispatch_get_main_queue(), cleanup);
}
