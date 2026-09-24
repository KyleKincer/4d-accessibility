#import <Cocoa/Cocoa.h>
#import "Bridge.h"
#import "Session.h"
#import "BridgePrivate.h"
#include "Limits.h"

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
    else if ([attribute isEqual:NSAccessibilitySelectedRowsAttribute] && [role isEqual:NSAccessibilityTableRole]) selector = @selector(setAccessibilitySelectedRows:);
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
- (NSString *)accessibilityIdentifier { return [self.combo.accessibilityIdentifier stringByAppendingString:@".choices"]; }
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

@implementation AXBNode
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { return AXBAttributeIsSettable(self, attribute); }
- (void)invalidate {
    if (!self.live) return;
    self.live = NO;
    NSAccessibilityPostNotification(self, NSAccessibilityUIElementDestroyedNotification);
}
- (BOOL)isAccessibilityElement { return self.live && [self.data[@"visible"] boolValue]; }
- (NSString *)accessibilityIdentifier { return [NSString stringWithFormat:@"axb.%@.%@", self.owner.session.identifier, self.data[@"id"]]; }
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
        @"group": NSAccessibilityGroupRole, @"image": NSAccessibilityImageRole, @"progress": NSAccessibilityProgressIndicatorRole, @"slider": NSAccessibilitySliderRole, @"stepper": NSAccessibilityIncrementorRole}[self.data[@"role"]];
}
- (NSString *)accessibilitySubrole { return [self.data[@"protected"] boolValue] ? NSAccessibilitySecureTextFieldSubrole : nil; }
- (NSString *)accessibilityPlaceholderValue { return self.data[@"placeholder"]; }
- (BOOL)isAccessibilityExpanded { return self.live && self.owner.comboOwner == self && self.owner.comboList.window.isVisible; }
- (NSArray *)accessibilityLinkedUIElements { return self.isAccessibilityExpanded ? @[self.owner.comboList] : @[]; }
- (id)accessibilityTitleUIElement {
    for (AXBNode *node in self.owner.nodes) if ([node.data[@"id"] isEqual:self.data[@"labelledBy"]]) return node;
    return nil;
}
- (BOOL)isAccessibilityFocused { return self.live && [self.data[@"focused"] boolValue] && self.owner.window.isKeyWindow; }
- (void)setAccessibilityFocused:(BOOL)focused { if (focused) (void)[self queue:@"focus" value:@YES]; }
- (id)accessibilityParent {
    if (self.data[@"parent"]) for (AXBNode *node in self.owner.nodes) if ([node.data[@"id"] isEqual:self.data[@"parent"]]) return node;
    return self.owner.element;
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
- (id)accessibilityValue { return self.data[@"value"] == NSNull.null ? nil : self.data[@"value"]; }
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
    BOOL accepted = [self.owner.session enqueueNode:self.data[@"id"] revision:self.revision operation:operation value:value observedSnapshot:self.owner.publishedSnapshot now:Now()];
    if (accepted) {
        self.owner.actionFeedback = nil;
        // VoiceOver can read the old value before 4D applies an action. These
        // controls need feedback after the exact host completion receipt.
        NSString *action = self.owner.session.activity[@"id"];
        BOOL checkbox = [operation isEqual:@"press"] && [self.data[@"role"] isEqual:@"checkbox"] && ![self.data[@"focusable"] boolValue];
        BOOL slider = [@[@"increment", @"decrement"] containsObject:operation] && [self.data[@"role"] isEqual:@"slider"];
        if (action && (checkbox || slider))
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
    if (selector == @selector(accessibilityPerformPress)) return ([@[@"button", @"checkbox", @"radio", @"popup"] containsObject:self.data[@"role"]] || [self.data[@"combo"] boolValue]) && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformShowMenu)) return [self.data[@"combo"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformConfirm)) return [self.data[@"combo"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformCancel)) return [self.data[@"combo"] boolValue] && self.isAccessibilityEnabled && self.isAccessibilityElement;
    if (selector == @selector(isAccessibilityExpanded) || selector == @selector(accessibilityLinkedUIElements)) return [self.data[@"combo"] boolValue] && self.isAccessibilityElement;
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
        // Real nodes always start with "axb.". Keep generated cells outside
        // that namespace even when a real row key ends with ".summary".
        self.summaryCell.identifier = [NSString stringWithFormat:@"axb-cell.%@.%@", self.owner.session.identifier, self.data[@"id"]];
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

static id DeepestHit(id element, NSPoint point) {
    NSRect frame = [element isKindOfClass:AXBNode.class] ? [(AXBNode *)element hitFrame] : [element accessibilityFrame];
    if (![element isAccessibilityElement] || !NSPointInRect(point, frame)) return nil;
    if ([element isKindOfClass:AXBGridNode.class]) return [element accessibilityHitTest:point];
    for (id child in [[element accessibilityChildren] reverseObjectEnumerator]) {
        id found = DeepestHit(child, point);
        if (found) return found;
    }
    return element;
}

static BOOL IsNativeControl(NSView *view) {
    return [view isKindOfClass:NSControl.class] || [view isKindOfClass:NSClassFromString(@"WKWebView")] || view.isAccessibilityElement;
}

// AppKit starts AX position lookup at the physical view beneath the point.
// Put virtual children under the common native drawing container, rather than
// beside it, so an opaque form view cannot hide them from that lookup.
static NSView *NativeContainer(NSWindow *window, NSDictionary *snapshot) {
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
    while (common && common != content && IsNativeControl(common)) common = common.superview;
    return common ?: content;
}

@implementation AXBWindowElement
- (BOOL)isAccessibilityElement { return self.owner.live && self.owner.session.snapshot != nil; }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityIdentifier { return self.identifier; }
- (NSString *)accessibilityLabel { return self.owner.session.snapshot[@"label"]; }
- (id)accessibilityParent { return self.owner.superview ? NSAccessibilityUnignoredAncestor(self.owner.superview) : nil; }
- (id)accessibilityWindow { return self.owner.window; }
- (id)accessibilityTopLevelUIElement { return self.owner.window; }
- (NSRect)accessibilityFrame { return self.owner ? self.owner.accessibilityFrame : NSZeroRect; }
- (id)accessibilityFocusedUIElement { return [self.owner accessibilityFocusedUIElement]; }
- (NSString *)accessibilityHelp {
    NSDictionary *activity = self.owner.session.activity;
    if ([activity[@"busy"] boolValue]) return [activity[@"delivered"] boolValue] ? @"Waiting for the application to complete the action" : @"Action queued";
    return activity[@"result"][@"message"] ?: @"Ready";
}
- (NSArray *)accessibilityChildren {
    if (!self.owner.live) return @[];
    return [self.owner.nodes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(AXBNode *node, NSDictionary *bindings) {
        (void)bindings; return node.isAccessibilityElement && !node.data[@"parent"];
    }]];
}
- (id)accessibilityHitTest:(NSPoint)point { return DeepestHit(self, point); }
- (NSArray *)accessibilityChildrenInNavigationOrder { return NavigationChildren(self.accessibilityChildren); }
@end

@implementation AXBWindowView
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
        if ([native isKindOfClass:AXBNode.class] || AXBGridElementBelongsToView(native, self) || native == self || native == self.element || native == self.menuFocus) native = nil;
        if (!native && self.nativeFocus && [self.nativeFocus respondsToSelector:@selector(accessibilityWindow)] &&
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
- (NSArray *)accessibilityChildren { return self.live && self.session.snapshot && self.element ? @[self.element] : @[]; }
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
    NSView *container = NativeContainer(window, snapshot);
    if (container != self.superview) { [self removeFromSuperview]; [container addSubview:self]; }
    self.frame = [container convertRect:window.contentView.bounds fromView:window.contentView];
    self.bounds = NSMakeRect(0, 0, NSWidth(window.contentView.bounds), NSHeight(window.contentView.bounds));
    NSMutableDictionary *old = [NSMutableDictionary new];
    for (AXBNode *node in self.nodes) old[node.data[@"id"]] = node;
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
        if (node && (![node.data[@"role"] isEqual:data[@"role"]] || [node.data[@"combo"] boolValue] != [data[@"combo"] boolValue] || node.class != kind)) { [retired addObject:node]; node = nil; }
        if (!node) {
            node = [kind new]; node.owner = self; node.live = YES; structureChanged = YES;
        }
        BOOL valueChanged = node.data && (![node.data[@"value"] isEqual:data[@"value"]] ||
            ((node.data[@"valueDescription"] || data[@"valueDescription"]) && ![node.data[@"valueDescription"] isEqual:data[@"valueDescription"]]));
        BOOL gainedFocus = [data[@"focused"] boolValue] && ![node.data[@"focused"] boolValue];
        BOOL textSelectionChanged = node.data && ![node.data[@"selection"] isEqual:data[@"selection"]] && (node.data[@"selection"] || data[@"selection"]);
        BOOL selectionChanged = node.data && ![node.data[@"selected"] isEqual:data[@"selected"]] && [data[@"role"] isEqual:@"row"];
        for (NSString *key in @[@"visible", @"frame", @"clip", @"parent", @"index", @"label", @"labelledBy", @"enabled"])
            if (node.data && (node.data[key] || data[key]) && ![node.data[key] isEqual:data[key]]) structureChanged = YES;
        node.data = data;
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
    [self refreshComboPopup];
    id focused = self.accessibilityFocusedUIElement;
    BOOL focusChanged = NO;
    if (focused && self.window.isKeyWindow && NSApp.isActive && [self canAct]) {
        if (NSApp.accessibilityApplicationFocusedUIElement != focused) {
            id previous = NSApp.accessibilityApplicationFocusedUIElement;
            if (![previous isKindOfClass:AXBNode.class] && !AXBGridElementBelongsToView(previous, self) && previous != self.menuFocus) self.nativeFocus = previous;
            NSApp.accessibilityApplicationFocusedUIElement = focused;
            focusChanged = YES;
        }
    } else [self restoreNativeFocus];
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
    for (AXBNode *node in changedTextSelections) NSAccessibilityPostNotification(node, NSAccessibilitySelectedTextChangedNotification);
    if (focusChanged) NSAccessibilityPostNotification(focused, NSAccessibilityFocusedUIElementChangedNotification);
    if (structureChanged) NSAccessibilityPostNotification(self.window, NSAccessibilityLayoutChangedNotification);
    NSDictionary *feedback = self.actionFeedback;
    NSDictionary *activity = self.session.activity;
    if (self.popupRequest && (![activity[@"busy"] boolValue] || ![activity[@"id"] isEqual:self.popupRequest[@"id"]])) self.popupRequest = nil;
    if (self.adoptedMenu && ![self.adoptedMenu.accessibilityParent isAccessibilityElement]) [self restorePopupMenu];
    NSDictionary *result = activity[@"result"];
    if (feedback && [feedback[@"id"] isEqual:result[@"id"]]) {
        self.actionFeedback = nil; // A receipt replay must never repeat speech.
        if (![activity[@"busy"] boolValue] && [result[@"status"] isEqual:@"completed"] && NSApp.isActive && self.window.isKeyWindow && [self canAct]) {
            for (AXBNode *node in self.nodes) {
                if (![node.data[@"id"] isEqual:feedback[@"node"]] || ![node.data[@"role"] isEqual:feedback[@"role"]] ||
                    ![node.data[@"label"] isEqual:feedback[@"label"]] || [node.data[@"value"] isEqual:feedback[@"value"]] ||
                    !node.isAccessibilityElement || !node.isAccessibilityEnabled || ([feedback[@"role"] isEqual:@"checkbox"] && node.isAccessibilityFocused)) continue;
                NSString *state = node.accessibilityValueDescription ?: [node.accessibilityValue description];
                if ([feedback[@"role"] isEqual:@"checkbox"]) {
                    NSBundle *bundle = [NSBundle bundleForClass:AXBNode.class];
                    NSString *key = [node.data[@"value"] integerValue] == 2 ? @"mixed" : [node.data[@"value"] boolValue] ? @"checked" : @"unchecked";
                    state = [bundle localizedStringForKey:key value:key table:@"AccessibilityBridge"];
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
            view.element.identifier = [@"axb.window." stringByAppendingString:session.identifier];
            view.live = YES;
            [window.contentView addSubview:view];
            views[session.identifier] = view;
            __weak AXBWindowView *weakView = view;
            view.focusObservers = @[
                [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
                    (void)notification; [weakView refreshComboPopup];
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
                if ([@[@"gridPress", @"gridHeaderPress"] containsObject:data[@"operation"]]) {
                    if (![node isKindOfClass:AXBGridNode.class]) return;
                    target = [data[@"operation"] isEqual:@"gridHeaderPress"] ? [(AXBGridNode *)node headerForColumn:data[@"target"][@"column"]] :
                        [(AXBGridNode *)node controlForRow:data[@"target"][@"row"] column:data[@"target"][@"column"]];
                    if (![target isAccessibilityElement] || ![target isAccessibilityEnabled]) return;
                    local = NSMakePoint([controlInput[@"point"][0] doubleValue], [controlInput[@"point"][1] doubleValue]);
                }
                NSPoint point = [view convertPoint:local toView:nil];
                NSPoint screen = [view.window convertPointToScreen:point];
                if (!NSPointInRect(screen, [target accessibilityFrame]) || DeepestHit(view.element, screen) != target) return;
                NSView *content = view.window.contentView;
                NSPoint physicalPoint = [content.superview convertPoint:point fromView:nil];
                NSView *physical = [content hitTest:physicalPoint];
                if (!physical || ![physical isDescendantOf:view.superview]) return;
                // A native control or web view over the drawing canvas owns
                // this point. Never redirect its mouse input to a virtual node.
                for (NSView *ancestor = physical; ancestor && ancestor != content; ancestor = ancestor.superview)
                    if (IsNativeControl(ancestor)) return;
                if (view.popupRequest[@"element"] == target && [view.popupRequest[@"id"] isEqual:controlInput[@"action"]])
                    view.popupRequest = @{@"element": target, @"id": controlInput[@"action"], @"nativeInput": @YES};
                NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:Now()
                    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
                NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:Now()
                    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
                // Mouse-down may enter AppKit's tracking loop. Queue its matching
                // release first, then synchronously dispatch to this exact window.
                // This keeps the control's normal focus behavior and On Clicked handler.
                [NSApp postEvent:up atStart:YES];
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
    dispatch_block_t cleanup = ^{ for (AXBWindowView *v in views.allValues) [v invalidate]; [views removeAllObjects]; };
    if (NSThread.isMainThread) cleanup(); else dispatch_sync(dispatch_get_main_queue(), cleanup);
}
