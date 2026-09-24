#import "BridgePrivate.h"
#import "Grid.h"

// A full-array request is truthful. Indexed AX requests resolve only their
// requested slice, and no native getter waits for the 4D form process.
@interface AXBGridArray : NSArray
- (instancetype)initWithCount:(NSUInteger)count resolve:(id (^)(NSUInteger))resolve;
@end
@implementation AXBGridArray {
    NSUInteger _count;
    unsigned long _mutation;
    id (^_resolve)(NSUInteger);
}
- (instancetype)initWithCount:(NSUInteger)count resolve:(id (^)(NSUInteger))resolve {
    if ((self = [super init])) { _count = count; _resolve = [resolve copy]; }
    return self;
}
- (NSUInteger)count { return _count; }
- (id)objectAtIndex:(NSUInteger)index {
    if (index >= _count) [NSException raise:NSRangeException format:@"Grid array index outside snapshot"];
    return _resolve(index);
}
- (void)getObjects:(id __unsafe_unretained [])objects range:(NSRange)range {
    if (range.location > _count || range.length > _count - range.location) [NSException raise:NSRangeException format:@"Grid array range outside snapshot"];
    for (NSUInteger i = 0; i < range.length; i++) objects[i] = [self objectAtIndex:range.location + i];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)length {
    if (state->state >= _count) return 0;
    NSUInteger count = MIN(length, _count - state->state);
    for (NSUInteger i = 0; i < count; i++) buffer[i] = [self objectAtIndex:state->state + i];
    state->itemsPtr = buffer; state->mutationsPtr = &_mutation; state->state += count;
    return count;
}
- (id)copyWithZone:(NSZone *)zone { (void)zone; return self; }
@end
static NSArray *Slice(NSArray *array, NSUInteger index, NSUInteger maximum) {
    if (index >= array.count || maximum == 0) return @[];
    return [array subarrayWithRange:NSMakeRange(index, MIN(maximum, array.count - index))];
}
static NSString *Identifier(AXBGridNode *table, NSString *kind, NSString *row, NSString *column) {
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:@[table.owner.session.identifier ?: @"", table.data[@"id"] ?: @"", table.data[@"grid"][@"generation"] ?: @"", kind, row ?: @"", column ?: @""] options:0 error:nil];
    return [@"axb-grid." stringByAppendingString:[bytes base64EncodedStringWithOptions:0]];
}
@class AXBGridRow, AXBGridCell, AXBGridColumn, AXBGridHeader, AXBGridContent, AXBGridWidget, AXBGridHeaderGroup;
@protocol AXBGridContentElement <NSObject, NSAccessibility>
@property(nonatomic) BOOL live;
- (void)invalidate;
@end
@interface AXBGridNode ()
@property(nonatomic, strong) AXBGrid *grid;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBGridRow *> *rowRegistry;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBGridColumn *> *columnRegistry;
@property(nonatomic, strong) NSDictionary *lastDescriptor;
@property(nonatomic) NSUInteger lastCacheSerial;
@property(nonatomic, strong) NSArray *pendingDestroyed;
@property(nonatomic, strong) AXBGridHeaderGroup *headerGroup;
- (AXBGridRow *)row:(NSString *)key;
- (AXBGridColumn *)column:(NSString *)key;
- (BOOL)synchronizeForAction;
- (NSRect)screenFrame:(NSArray *)frame;
- (NSRect)layoutFrameForRow:(NSString *)row column:(NSString *)column;
@end
@interface AXBGridPart : NSAccessibilityElement
@property(nonatomic, weak) AXBGridNode *table;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) BOOL live;
- (void)invalidate;
@end
BOOL AXBGridElementBelongsToView(id element, AXBWindowView *view) {
    return ([element isKindOfClass:AXBGridPart.class] && ((AXBGridPart *)element).table.owner == view) ||
        ([element isKindOfClass:AXBTextNode.class] && ((AXBTextNode *)element).owner == view);
}
@interface AXBGridRow : AXBGridPart
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBGridCell *> *cells;
- (AXBGridCell *)cell:(NSString *)column;
@end
@interface AXBGridCell : AXBGridPart
@property(nonatomic, weak) AXBGridRow *row;
@property(nonatomic, copy) NSString *columnKey;
@property(nonatomic, strong) NSDictionary *lastValue;
@property(nonatomic, strong) id<AXBGridContentElement> content;
@property(nonatomic, copy) NSString *contentRole;
- (NSDictionary *)value;
- (BOOL)canEdit;
- (BOOL)isWidget;
@end
@interface AXBGridContent : AXBEditableTextNode <AXBGridContentElement>
@property(nonatomic, weak) AXBGridCell *cell;
@property(nonatomic, readonly) AXBGridNode *table;
@end
@interface AXBGridWidget : AXBGridPart <AXBGridContentElement>
@property(nonatomic, weak) AXBGridCell *cell;
@property(nonatomic, copy) NSString *role;
@end
@interface AXBGridColumn : AXBGridPart
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) AXBGridHeader *header;
@end
@interface AXBGridHeader : AXBGridPart
@property(nonatomic, weak) AXBGridColumn *column;
- (NSDictionary *)metadata;
@end
@interface AXBGridHeaderGroup : AXBGridPart
@end

@implementation AXBGridPart
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { return AXBAttributeIsSettable(self, attribute); }
- (BOOL)isAccessibilityElement { return self.live && self.table.isAccessibilityElement && self.table.grid.active; }
- (NSString *)accessibilityIdentifier { return self.identifier; }
- (id)accessibilityWindow { return self.table.accessibilityWindow; }
- (id)accessibilityTopLevelUIElement { return self.table.accessibilityTopLevelUIElement; }
- (BOOL)isAccessibilityEnabled { return self.isAccessibilityElement && self.table.isAccessibilityEnabled; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityValue:) || selector == @selector(setAccessibilityFocused:) ||
        selector == @selector(setAccessibilitySelected:) || selector == @selector(accessibilityPerformPress)) return NO;
    return [super isAccessibilitySelectorAllowed:selector];
}
- (void)invalidate {
    if (!self.live) return;
    self.live = NO; NSAccessibilityPostNotification(self, NSAccessibilityUIElementDestroyedNotification);
}
@end
@implementation AXBGridCell
- (BOOL)isAccessibilityElement { return [super isAccessibilityElement] && self.row.isAccessibilityElement && [self.table.grid indexOfColumn:self.columnKey] != NSNotFound; }
- (NSString *)accessibilityRole { return NSAccessibilityCellRole; }
- (id)accessibilityParent { return self.row; }
- (NSString *)accessibilityLabel { return nil; }
- (NSArray *)accessibilityChildren {
    if (!self.isAccessibilityElement) return @[];
    NSString *role = self.value[@"role"] ?: @"text";
    if (self.content && ![self.contentRole isEqual:role]) {
        [self.content invalidate]; self.content = nil;
        NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
    }
    if (!self.content) {
        if ([self isWidget]) {
            AXBGridWidget *widget = [AXBGridWidget new]; widget.cell = self; widget.table = self.table; widget.role = role;
            widget.identifier = Identifier(self.table, role, self.row.key, self.columnKey);
            self.content = widget;
        } else {
            AXBGridContent *text = [AXBGridContent new]; text.cell = self; self.content = text;
        }
        self.contentRole = role; self.content.live = YES;
    }
    return @[self.content];
}
- (void)invalidate { [super invalidate]; [self.content invalidate]; }
- (NSDictionary *)value { return self.isAccessibilityElement ? [self.table.grid cellForRow:self.row.key column:self.columnKey now:NSProcessInfo.processInfo.systemUptime] : nil; }
- (id)accessibilityValue {
    NSDictionary *focus = self.isAccessibilityFocused ? self.table.grid.descriptor[@"focused"] : nil;
    return focus[@"value"] ?: self.value[@"value"] ?: (self.isAccessibilityElement ? @"Loading" : nil);
}
- (NSString *)accessibilityHelp { return self.value ? nil : @"Loading cell value"; }
- (BOOL)isAccessibilityEnabled { return [super isAccessibilityEnabled] && self.row.isAccessibilityEnabled && ![self.table.grid.descriptor[@"disabled"] containsObject:self.row.key] && [self.table column:self.columnKey].isAccessibilityEnabled && (!self.value || [self.value[@"enabled"] boolValue]); }
- (BOOL)canEdit {
    NSUInteger column = [self.table.grid indexOfColumn:self.columnKey];
    return self.isAccessibilityEnabled && column != NSNotFound && [self.table.grid.descriptor[@"actions"][@"edit"] boolValue] &&
        AXBGridRowAllowsEditing(self.table.grid.descriptor, self.row.key) &&
        [self.table.grid.descriptor[@"columns"][column][@"editable"] boolValue] && [self.value[@"editable"] boolValue];
}
- (BOOL)isWidget { return [@[@"checkbox", @"popup"] containsObject:self.value[@"role"] ?: @""]; }
- (BOOL)isAccessibilityFocused {
    NSDictionary *focused = self.table.grid.descriptor[@"focused"];
    return self.isAccessibilityElement && self.table.owner.window.isKeyWindow && [focused[@"row"] isEqual:self.row.key] && [focused[@"column"] isEqual:self.columnKey];
}
- (void)setAccessibilityFocused:(BOOL)focused {
    if (focused && [self.table synchronizeForAction] && [self canEdit]) (void)[self.table queue:@"gridEdit" value:@{@"row": self.row.key, @"column": self.columnKey}];
}
// AppKit exposes ScrollToVisible through its action-name protocol. There is
// no corresponding method in NSAccessibilityProtocol, including the 26 SDK.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray *)accessibilityActionNames {
    NSMutableArray *actions = [NSMutableArray new];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)]) [actions addObject:NSAccessibilityPressAction];
    if (@available(macOS 26.0, *)) {
        if (self.isAccessibilityElement && self.table.isAccessibilityEnabled && [self.table.grid.descriptor[@"actions"][@"reveal"] boolValue])
            [actions addObject:NSAccessibilityScrollToVisibleAction];
    }
    return actions;
}
- (void)accessibilityPerformAction:(NSString *)action {
    if (@available(macOS 26.0, *)) {
        if ([action isEqual:NSAccessibilityScrollToVisibleAction]) {
            if ([self.table synchronizeForAction] && self.isAccessibilityElement) (void)[self.table queue:@"gridReveal" value:@{@"row": self.row.key, @"column": self.columnKey}];
            return;
        }
    }
    [super accessibilityPerformAction:action];
}
#pragma clang diagnostic pop
- (void)setAccessibilityValue:(id)value {
    if ([value isKindOfClass:NSString.class] && [self.table synchronizeForAction] && ![self isWidget] && [self canEdit]) (void)[self.table queue:@"gridSetValue" value:@{@"row": self.row.key, @"column": self.columnKey, @"text": value}];
}
- (BOOL)accessibilityPerformPress {
    if (![self.table synchronizeForAction] || !self.isAccessibilityEnabled) return NO;
    if ([self canEdit]) {
        BOOL accepted = [self.table queue:[self isWidget] ? @"gridPress" : @"gridEdit" value:@{@"row": self.row.key, @"column": self.columnKey}];
        if (accepted && [self.value[@"role"] isEqual:@"popup"]) [self.table.owner expectPopupFrom:self.accessibilityChildren.firstObject];
        return accepted;
    }
    if (![self.table.grid.descriptor[@"actions"][@"select"] boolValue] || !AXBGridRowAllowsSelection(self.table.grid.descriptor, self.row.key)) return NO;
    return [self.table queue:@"gridSelect" value:@[self.row.key]];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityFocused:)) return [self canEdit];
    if (selector == @selector(setAccessibilityValue:)) return ![self isWidget] && [self canEdit];
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityEnabled && ([self canEdit] || ([self.table.grid.descriptor[@"actions"][@"select"] boolValue] && AXBGridRowAllowsSelection(self.table.grid.descriptor, self.row.key)));
    return [super isAccessibilitySelectorAllowed:selector];
}
- (NSRange)accessibilityRowIndexRange {
    NSUInteger index = self.row.isAccessibilityElement ? [self.table.grid indexOfRow:self.row.key] : NSNotFound;
    return NSMakeRange(index, index == NSNotFound ? 0 : 1);
}
- (NSRange)accessibilityColumnIndexRange {
    NSUInteger index = self.isAccessibilityElement ? [self.table.grid indexOfColumn:self.columnKey] : NSNotFound;
    return NSMakeRange(index, index == NSNotFound ? 0 : 1);
}
- (NSArray *)accessibilityColumnHeaderUIElements {
    if (!self.isAccessibilityElement) return @[];
    AXBGridHeader *header = [self.table column:self.columnKey].header;
    return header.isAccessibilityElement ? @[header] : @[];
}
- (BOOL)isAccessibilitySelected { return [self.row isAccessibilitySelected]; }
- (NSRect)accessibilityFrame {
    return self.isAccessibilityElement ? [self.table layoutFrameForRow:self.row.key column:self.columnKey] : NSZeroRect;
}
@end
// Native control children provide typed states and actions without inheriting
// text-range APIs. Their structural cell retains the table relationships.
@implementation AXBGridWidget
- (BOOL)isAccessibilityElement { return [super isAccessibilityElement] && self.cell.isAccessibilityElement && [self.cell.value[@"role"] isEqual:self.role]; }
- (id)accessibilityParent { return self.cell; }
- (NSArray *)accessibilityChildren {
    NSMenu *menu = self.table.owner.adoptedMenu;
    return self.isAccessibilityElement && menu.accessibilityParent == self ? @[menu] : @[];
}
- (NSString *)accessibilityRole { return [self.role isEqual:@"checkbox"] ? NSAccessibilityCheckBoxRole : NSAccessibilityPopUpButtonRole; }
- (NSString *)accessibilityLabel { return [self.cell.value[@"label"] length] ? self.cell.value[@"label"] : [self.table column:self.cell.columnKey].accessibilityLabel; }
- (id)accessibilityValue { return self.isAccessibilityElement ? self.cell.value[([self.role isEqual:@"checkbox"] ? @"checked" : @"value")] : nil; }
- (NSRect)accessibilityFrame { return self.cell.accessibilityFrame; }
- (BOOL)isAccessibilityEnabled { return self.isAccessibilityElement && [self.cell canEdit]; }
- (BOOL)isAccessibilityFocused { return self.isAccessibilityElement && self.cell.isAccessibilityFocused; }
- (void)setAccessibilityFocused:(BOOL)value { if ([self.table synchronizeForAction] && self.isAccessibilityElement) [self.cell setAccessibilityFocused:value]; }
- (BOOL)accessibilityPerformPress { return [self.table synchronizeForAction] && self.isAccessibilityEnabled && [self.cell accessibilityPerformPress]; }
- (BOOL)accessibilityPerformShowMenu { return [self.role isEqual:@"popup"] && [self accessibilityPerformPress]; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray *)accessibilityActionNames {
    NSMutableArray *actions = [NSMutableArray new];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)]) [actions addObject:NSAccessibilityPressAction];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformShowMenu)]) [actions addObject:NSAccessibilityShowMenuAction];
    if (@available(macOS 26.0, *)) {
        if (self.isAccessibilityElement && [[self.cell accessibilityActionNames] containsObject:NSAccessibilityScrollToVisibleAction])
            [actions addObject:NSAccessibilityScrollToVisibleAction];
    }
    return actions;
}
- (void)accessibilityPerformAction:(NSString *)action {
    if (@available(macOS 26.0, *)) {
        if ([action isEqual:NSAccessibilityScrollToVisibleAction]) {
            if (self.isAccessibilityElement) [self.cell accessibilityPerformAction:action];
            return;
        }
    }
    [super accessibilityPerformAction:action];
}
#pragma clang diagnostic pop
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityFocused:) || selector == @selector(accessibilityPerformPress)) return self.isAccessibilityEnabled;
    if (selector == @selector(accessibilityPerformShowMenu)) return self.isAccessibilityEnabled && [self.role isEqual:@"popup"];
    return [super isAccessibilitySelectorAllowed:selector];
}
@end
// A cell is structural. Its text/editor child supplies what VoiceOver reads,
// just as a native view-based table cell contains a label or text field.
@implementation AXBGridContent
- (AXBGridNode *)table { return self.cell.table; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray *)accessibilityActionNames {
    NSMutableArray *actions = [[super accessibilityActionNames] mutableCopy];
    if (@available(macOS 26.0, *)) {
        if (self.isAccessibilityElement && [[self.cell accessibilityActionNames] containsObject:NSAccessibilityScrollToVisibleAction])
            [actions addObject:NSAccessibilityScrollToVisibleAction];
    }
    return actions;
}
- (void)accessibilityPerformAction:(NSString *)action {
    if (@available(macOS 26.0, *)) {
        if ([action isEqual:NSAccessibilityScrollToVisibleAction]) {
            if (self.isAccessibilityElement) [self.cell accessibilityPerformAction:action];
            return;
        }
    }
    [super accessibilityPerformAction:action];
}
#pragma clang diagnostic pop
- (AXBWindowView *)owner { return self.table.owner; }
- (NSString *)accessibilityIdentifier { return Identifier(self.table, @"content", self.cell.row.key, self.cell.columnKey); }
- (NSDictionary *)data {
    NSDictionary *focus = self.cell.isAccessibilityFocused ? self.table.grid.descriptor[@"focused"] : nil;
    NSMutableDictionary *data = [@{@"editable": @([self.cell canEdit] && focus[@"selection"]), @"protected": @NO} mutableCopy];
    if (focus[@"selection"]) data[@"selection"] = focus[@"selection"];
    return data;
}
- (BOOL)isAccessibilityElement { return self.live && self.cell.isAccessibilityElement && ![self.cell isWidget]; }
- (BOOL)isAccessibilityEnabled { return self.cell.isAccessibilityEnabled; }
- (id)accessibilityParent { return self.cell; }
- (NSString *)accessibilityRole {
    NSUInteger column = [self.table.grid indexOfColumn:self.cell.columnKey];
    return column != NSNotFound && [self.table.grid.descriptor[@"columns"][column][@"editable"] boolValue] ? NSAccessibilityTextFieldRole : NSAccessibilityStaticTextRole;
}
- (NSString *)accessibilityLabel { return [self.accessibilityRole isEqual:NSAccessibilityTextFieldRole] ? [self.table column:self.cell.columnKey].accessibilityLabel : nil; }
- (id)accessibilityValue {
    NSDictionary *focus = self.cell.isAccessibilityFocused ? self.table.grid.descriptor[@"focused"] : nil;
    return focus[@"value"] ?: self.cell.accessibilityValue;
}
- (id)accessibilityWindow { return self.table.owner.window; }
- (id)accessibilityTopLevelUIElement { return self.table.owner.window; }
- (NSRect)accessibilityFrame { return self.cell.accessibilityFrame; }
- (BOOL)isAccessibilityFocused { return self.cell.isAccessibilityFocused; }
- (void)setAccessibilityFocused:(BOOL)value { if ([self.table synchronizeForAction] && self.isAccessibilityElement) [self.cell setAccessibilityFocused:value]; }
- (void)setAccessibilityValue:(id)value { if ([self.table synchronizeForAction] && self.isAccessibilityElement) [self.cell setAccessibilityValue:value]; }
- (BOOL)accessibilityPerformPress { return [self.table synchronizeForAction] && self.isAccessibilityElement && [self.cell accessibilityPerformPress]; }
- (BOOL)queue:(NSString *)operation value:(id)value {
    if (![self.table synchronizeForAction] || !self.isAccessibilityElement || ![self.cell canEdit]) return NO;
    NSString *gridOperation = @{@"setSelection": @"gridSetSelection", @"replaceSelection": @"gridReplaceSelection"}[operation];
    if (!gridOperation) return NO;
    return [self.table queue:gridOperation value:@{@"row": self.cell.row.key, @"column": self.cell.columnKey,
        [operation isEqual:@"setSelection"] ? @"selection" : @"text": value}];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityFocused:) || selector == @selector(setAccessibilityValue:) || selector == @selector(accessibilityPerformPress)) return self.isAccessibilityElement && [self.cell canEdit];
    return [super isAccessibilitySelectorAllowed:selector];
}
@end
@implementation AXBGridRow
- (BOOL)isAccessibilityElement { return [super isAccessibilityElement] && [self.table.grid indexOfRow:self.key] != NSNotFound; }
- (BOOL)isAccessibilityEnabled { return [super isAccessibilityEnabled] && (self.table.grid.descriptor[@"uneditable"] || ![self.table.grid.descriptor[@"disabled"] containsObject:self.key]); }
- (NSString *)accessibilityRole { return NSAccessibilityRowRole; }
- (id)accessibilityParent { return self.table; }
- (NSInteger)accessibilityIndex { return self.isAccessibilityElement ? [self.table.grid indexOfRow:self.key] : NSNotFound; }
- (NSString *)accessibilityLabel { return nil; }
- (BOOL)isAccessibilitySelected { return [self.table.grid.descriptor[@"selected"] containsObject:self.key]; }
- (BOOL)accessibilityPerformPress { return [self.table synchronizeForAction] && [self isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && [self.table queue:@"gridSelect" value:@[self.key]]; }
- (void)setAccessibilitySelected:(BOOL)selected {
    if (![self.table synchronizeForAction] || !self.isAccessibilityEnabled) return;
    if (![self.table.grid.descriptor[@"actions"][@"select"] boolValue] || (selected && !self.isAccessibilitySelected && !AXBGridRowAllowsSelection(self.table.grid.descriptor, self.key))) return;
    NSMutableArray *keys = [self.table.grid.descriptor[@"selected"] mutableCopy];
    [keys removeObject:self.key]; if (selected) [keys addObject:self.key];
    (void)[self.table queue:@"gridSelect" value:keys];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityEnabled && [self.table.grid.descriptor[@"actions"][@"select"] boolValue] && AXBGridRowAllowsSelection(self.table.grid.descriptor, self.key);
    if (selector == @selector(setAccessibilitySelected:)) return self.isAccessibilityEnabled && [self.table.grid.descriptor[@"actions"][@"select"] boolValue] && (self.isAccessibilitySelected || AXBGridRowAllowsSelection(self.table.grid.descriptor, self.key));
    return [super isAccessibilitySelectorAllowed:selector];
}
- (AXBGridCell *)cell:(NSString *)column {
    AXBGridCell *cell = self.cells[column];
    if (!cell) {
        cell = [AXBGridCell new]; cell.table = self.table; cell.row = self; cell.columnKey = column; cell.live = self.live;
        cell.identifier = Identifier(self.table, @"cell", self.key, column); self.cells[column] = cell;
    }
    return cell;
}
- (NSArray *)accessibilityChildren {
    NSArray *columns = self.isAccessibilityElement ? self.table.grid.descriptor[@"columns"] : @[];
    return [[AXBGridArray alloc] initWithCount:columns.count resolve:^id(NSUInteger index) { return [self cell:columns[index][@"id"]]; }];
}
- (NSUInteger)accessibilityArrayAttributeCount:(NSAccessibilityAttributeName)attribute {
    return [attribute isEqual:NSAccessibilityChildrenAttribute] ? self.accessibilityChildren.count : [super accessibilityArrayAttributeCount:attribute];
}
- (NSArray *)accessibilityArrayAttributeValues:(NSAccessibilityAttributeName)attribute index:(NSUInteger)index maxCount:(NSUInteger)maximum {
    return [attribute isEqual:NSAccessibilityChildrenAttribute] ? Slice(self.accessibilityChildren, index, maximum) : [super accessibilityArrayAttributeValues:attribute index:index maxCount:maximum];
}
- (NSUInteger)accessibilityIndexOfChild:(id)child {
    return [child isKindOfClass:AXBGridCell.class] && ((AXBGridCell *)child).row == self ? [self.table.grid indexOfColumn:((AXBGridCell *)child).columnKey] : NSNotFound;
}
- (NSRect)accessibilityFrame {
    NSRect result = NSZeroRect;
    if (self.isAccessibilityElement) for (NSDictionary *column in self.table.grid.descriptor[@"columns"]) result = NSUnionRect(result, [self.table layoutFrameForRow:self.key column:column[@"id"]]);
    return result;
}
- (void)invalidate { [super invalidate]; for (AXBGridCell *cell in self.cells.allValues) [cell invalidate]; }
@end
@implementation AXBGridColumn
- (BOOL)isAccessibilityElement { return [super isAccessibilityElement] && [self.table.grid indexOfColumn:self.key] != NSNotFound; }
- (NSString *)accessibilityRole { return NSAccessibilityColumnRole; }
- (id)accessibilityParent { return self.table; }
- (NSInteger)accessibilityIndex { return self.isAccessibilityElement ? [self.table.grid indexOfColumn:self.key] : NSNotFound; }
- (NSString *)accessibilityLabel {
    NSUInteger index = [self.table.grid indexOfColumn:self.key];
    return self.isAccessibilityElement && index != NSNotFound ? self.table.grid.descriptor[@"columns"][index][@"label"] : nil;
}
- (BOOL)isAccessibilityEnabled {
    NSUInteger index = [self.table.grid indexOfColumn:self.key];
    return [super isAccessibilityEnabled] && index != NSNotFound && [self.table.grid.descriptor[@"columns"][index][@"enabled"] boolValue];
}
- (id)accessibilityHeader { return self.header; }
- (NSArray *)accessibilityChildren { return @[]; }
- (NSRect)accessibilityFrame { return self.isAccessibilityElement ? [self.table screenFrame:self.table.grid.descriptor[@"headers"][self.key]] : NSZeroRect; }
- (void)invalidate { [super invalidate]; [self.header invalidate]; }
@end
@implementation AXBGridHeader
- (NSDictionary *)metadata {
    NSUInteger index = [self.table.grid indexOfColumn:self.column.key];
    return index == NSNotFound ? nil : self.table.grid.descriptor[@"columns"][index][@"header"];
}
- (BOOL)isAccessibilityElement {
    return [super isAccessibilityElement] && self.column.isAccessibilityElement && (!self.metadata || [self.metadata[@"visible"] boolValue]);
}
- (BOOL)isAccessibilityEnabled { return [super isAccessibilityEnabled] && (!self.metadata || [self.metadata[@"enabled"] boolValue]); }
- (NSString *)accessibilityRole { return [self.metadata[@"press"] boolValue] ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole; }
- (NSString *)accessibilitySubrole { return [self.metadata[@"sortable"] boolValue] ? NSAccessibilitySortButtonSubrole : nil; }
- (NSAccessibilitySortDirection)accessibilitySortDirection {
    NSString *sort = self.metadata[@"sort"];
    return [sort isEqual:@"ascending"] ? NSAccessibilitySortDirectionAscending : [sort isEqual:@"descending"] ? NSAccessibilitySortDirectionDescending : NSAccessibilitySortDirectionUnknown;
}
- (id)accessibilityParent { return self.table.accessibilityHeader; }
- (NSString *)accessibilityLabel { return self.column.accessibilityLabel; }
- (id)accessibilityValue { return self.accessibilityLabel; }
- (NSRect)accessibilityFrame {
    if (!self.isAccessibilityElement) return NSZeroRect;
    NSRect visible = self.column.accessibilityFrame;
    if (!NSIsEmptyRect(visible)) return visible;
    NSDictionary *layout = self.table.grid.descriptor[@"layout"];
    NSUInteger index = [self.table.grid indexOfColumn:self.column.key];
    CGFloat height = [self.table.grid.descriptor[@"headerHeight"] doubleValue];
    if (!layout || index == NSNotFound || height <= 0) return NSZeroRect;
    NSArray *horizontal = layout[@"columns"][index];
    NSRect rect = NSMakeRect([horizontal[0] doubleValue], [self.table.data[@"frame"][1] doubleValue], [horizontal[1] doubleValue], height);
    return [self.table.owner.window convertRectToScreen:[self.table.owner convertRect:rect toView:nil]];
}
- (BOOL)accessibilityPerformPress {
    return [self.table synchronizeForAction] && self.isAccessibilityEnabled && [self.metadata[@"press"] boolValue] &&
        [self.table queue:@"gridHeaderPress" value:@{@"column": self.column.key}];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityEnabled && [self.metadata[@"press"] boolValue];
    return [super isAccessibilitySelectorAllowed:selector];
}
- (NSArray *)accessibilityActionNames {
    NSMutableArray *actions = [NSMutableArray new];
    if ([self isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)]) [actions addObject:NSAccessibilityPressAction];
    if (@available(macOS 26.0, *)) {
        if (self.metadata && self.isAccessibilityElement && [self.table.owner canAct]) [actions addObject:NSAccessibilityScrollToVisibleAction];
    }
    return actions;
}
- (void)accessibilityPerformAction:(NSString *)action {
    if (@available(macOS 26.0, *)) {
        if ([action isEqual:NSAccessibilityScrollToVisibleAction]) {
            if ([self.table synchronizeForAction] && self.isAccessibilityElement)
                (void)[self.table queue:@"gridHeaderReveal" value:@{@"column": self.column.key}];
            return;
        }
    }
    if ([action isEqual:NSAccessibilityPressAction]) (void)[self accessibilityPerformPress];
}
@end
@implementation AXBGridHeaderGroup
- (BOOL)isAccessibilityElement { return [super isAccessibilityElement] && (!self.table.grid.descriptor[@"headerHeight"] || [self.table.grid.descriptor[@"headerHeight"] doubleValue] > 0); }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (id)accessibilityParent { return self.table; }
- (NSArray *)accessibilityChildren { return self.isAccessibilityElement ? self.table.accessibilityColumnHeaderUIElements : @[]; }
- (NSRect)accessibilityFrame {
    NSRect result = NSZeroRect;
    for (id header in self.accessibilityChildren) result = NSUnionRect(result, [header accessibilityFrame]);
    return result;
}
@end

@implementation AXBGridNode
- (id)headerForColumn:(NSString *)column {
    return self.isAccessibilityElement && [self.grid indexOfColumn:column] != NSNotFound ? [self column:column].header : nil;
}
- (id)controlForRow:(NSString *)row column:(NSString *)column {
    if (!self.isAccessibilityElement || [self.grid indexOfRow:row] == NSNotFound || [self.grid indexOfColumn:column] == NSNotFound) return nil;
    return [[[self row:row] cell:column] accessibilityChildren].firstObject;
}
- (BOOL)synchronizeForAction {
    if (!NSThread.isMainThread) return NO;
    // Grid getters use the live session model. Publish its matching tree before
    // validating an action, so an old node revision cannot reject a current row.
    // Refresh first: replacement may retire the initiating row/cell, which each
    // caller must check before constructing or queuing its request.
    if (![self.owner.publishedSnapshot[@"revision"] isEqual:self.owner.session.snapshot[@"revision"]])
        [self.owner refresh];
    return self.isAccessibilityElement;
}
- (AXBGridRow *)row:(NSString *)key {
    AXBGridRow *row = self.rowRegistry[key];
    if (!row) {
        row = [AXBGridRow new]; row.table = self; row.key = key; row.live = self.live;
        row.identifier = Identifier(self, @"row", key, nil); row.cells = [NSMutableDictionary new];
        self.rowRegistry[key] = row;
    }
    return row;
}
- (AXBGridColumn *)column:(NSString *)key {
    AXBGridColumn *column = self.columnRegistry[key];
    if (!column) {
        column = [AXBGridColumn new]; column.table = self; column.key = key; column.live = self.live;
        column.identifier = Identifier(self, @"column", nil, key);
        column.header = [AXBGridHeader new]; column.header.table = self; column.header.column = column; column.header.live = self.live;
        column.header.identifier = Identifier(self, @"header", nil, key);
        self.columnRegistry[key] = column;
    }
    return column;
}
- (NSArray *)accessibilityRows {
    NSArray *keys = self.isAccessibilityElement ? self.grid.descriptor[@"rows"] : @[];
    return [[AXBGridArray alloc] initWithCount:keys.count resolve:^id(NSUInteger index) { return [self row:keys[index]]; }];
}
- (NSInteger)accessibilityRowCount { return self.isAccessibilityElement ? [self.grid.descriptor[@"rows"] count] : 0; }
- (NSInteger)accessibilityColumnCount { return self.isAccessibilityElement ? [self.grid.descriptor[@"columns"] count] : 0; }
- (NSArray *)accessibilityColumns {
    NSMutableArray *columns = [NSMutableArray new];
    if (self.isAccessibilityElement) for (NSDictionary *column in self.grid.descriptor[@"columns"]) [columns addObject:[self column:column[@"id"]]];
    return columns;
}
- (NSArray *)accessibilityColumnHeaderUIElements {
    NSMutableArray *headers = [NSMutableArray new];
    for (AXBGridColumn *column in self.accessibilityColumns) if (column.header.isAccessibilityElement) [headers addObject:column.header];
    return headers;
}
- (id)accessibilityHeader {
    if (!self.isAccessibilityElement) return nil;
    if (!self.headerGroup) {
        self.headerGroup = [AXBGridHeaderGroup new]; self.headerGroup.table = self; self.headerGroup.live = YES;
        self.headerGroup.identifier = Identifier(self, @"headers", nil, nil);
    }
    return self.headerGroup;
}
- (NSArray *)accessibilityChildren {
    if (!self.isAccessibilityElement) return @[];
    NSArray *columns = self.accessibilityColumns, *rows = self.accessibilityRows;
    id header = self.accessibilityHeader;
    return [[AXBGridArray alloc] initWithCount:rows.count + columns.count + 1 resolve:^id(NSUInteger index) {
        if (index < rows.count) return rows[index];
        if (index < rows.count + columns.count) return columns[index - rows.count];
        return header;
    }];
}
- (NSUInteger)accessibilityArrayAttributeCount:(NSAccessibilityAttributeName)attribute {
    if ([attribute isEqual:NSAccessibilityRowsAttribute]) return self.accessibilityRowCount;
    if ([attribute isEqual:NSAccessibilityChildrenAttribute]) return self.accessibilityChildren.count;
    return [super accessibilityArrayAttributeCount:attribute];
}
- (NSArray *)accessibilityArrayAttributeValues:(NSAccessibilityAttributeName)attribute index:(NSUInteger)index maxCount:(NSUInteger)maximum {
    if ([attribute isEqual:NSAccessibilityRowsAttribute]) return Slice(self.accessibilityRows, index, maximum);
    if ([attribute isEqual:NSAccessibilityChildrenAttribute]) return Slice(self.accessibilityChildren, index, maximum);
    return [super accessibilityArrayAttributeValues:attribute index:index maxCount:maximum];
}
- (NSUInteger)accessibilityIndexOfChild:(id)child {
    if ([child isKindOfClass:AXBGridRow.class] && ((AXBGridRow *)child).table == self) {
        NSUInteger index = [self.grid indexOfRow:((AXBGridRow *)child).key];
        return index;
    }
    if ([child isKindOfClass:AXBGridColumn.class] && ((AXBGridColumn *)child).table == self) {
        NSUInteger index = [self.grid indexOfColumn:((AXBGridColumn *)child).key];
        return index == NSNotFound ? index : index + self.accessibilityRowCount;
    }
    if (child == self.headerGroup) return self.accessibilityRowCount + self.accessibilityColumnCount;
    return NSNotFound;
}
- (id)accessibilityCellForColumn:(NSInteger)column row:(NSInteger)row {
    NSDictionary *descriptor = self.grid.descriptor;
    if (!self.isAccessibilityElement || column < 0 || row < 0 || (NSUInteger)row >= [descriptor[@"rows"] count] || (NSUInteger)column >= [descriptor[@"columns"] count]) return nil;
    return [[self row:descriptor[@"rows"][row]] cell:descriptor[@"columns"][column][@"id"]];
}
- (NSArray *)accessibilityVisibleRows {
    NSMutableArray *rows = [NSMutableArray new];
    if (self.isAccessibilityElement) for (NSString *key in self.grid.descriptor[@"visible"]) [rows addObject:[self row:key]];
    return rows;
}
- (NSArray *)accessibilitySelectedRows {
    NSMutableArray *rows = [NSMutableArray new];
    if (self.isAccessibilityElement) for (NSString *key in self.grid.descriptor[@"selected"]) [rows addObject:[self row:key]];
    return rows;
}
- (void)setAccessibilitySelectedRows:(NSArray *)rows {
    if (![rows isKindOfClass:NSArray.class] || ![self synchronizeForAction]) return;
    NSMutableArray *keys = [NSMutableArray new];
    for (id row in rows) {
        if (![row isKindOfClass:AXBGridRow.class] || ((AXBGridRow *)row).table != self || ![row isAccessibilityEnabled]) return;
        [keys addObject:((AXBGridRow *)row).key];
    }
    (void)[self queue:@"gridSelect" value:keys];
}
- (BOOL)isAccessibilityFocused { return self.live && self.grid.descriptor[@"focused"] && self.owner.window.isKeyWindow; }
- (id)accessibilityFocusedUIElement {
    NSDictionary *focused = self.grid.descriptor[@"focused"];
    return self.isAccessibilityFocused ? [[[[self row:focused[@"row"]] cell:focused[@"column"]] accessibilityChildren] firstObject] : nil;
}
- (NSArray *)accessibilityVisibleColumns {
    NSMutableArray *columns = [NSMutableArray new];
    for (AXBGridColumn *column in self.accessibilityColumns) {
        BOOL visible = !NSIsEmptyRect(column.accessibilityFrame);
        for (NSDictionary *frames in [self.grid.descriptor[@"frames"] allValues]) if (frames[column.key]) visible = YES;
        if (visible) [columns addObject:column];
    }
    return columns;
}
- (NSArray *)accessibilityVisibleCells {
    NSMutableArray *cells = [NSMutableArray new];
    for (AXBGridRow *row in self.accessibilityVisibleRows) for (NSString *column in self.grid.descriptor[@"frames"][row.key]) {
        AXBGridCell *cell = [row cell:column]; if (!NSIsEmptyRect([self screenFrame:self.grid.descriptor[@"frames"][row.key][column]])) [cells addObject:cell];
    }
    return cells;
}
- (NSRect)layoutFrameForRow:(NSString *)row column:(NSString *)column {
    if (!self.isAccessibilityElement || !self.owner.window) return NSZeroRect;
    NSDictionary *layout = self.grid.descriptor[@"layout"];
    if (!layout) return [self screenFrame:self.grid.descriptor[@"frames"][row][column]];
    NSUInteger r = [self.grid indexOfRow:row], c = [self.grid indexOfColumn:column];
    if (r == NSNotFound || c == NSNotFound) return NSZeroRect;
    NSArray *vertical = layout[@"rows"][r], *horizontal = layout[@"columns"][c];
    NSRect rect = NSMakeRect([horizontal[0] doubleValue], [vertical[0] doubleValue], [horizontal[1] doubleValue], [vertical[1] doubleValue]);
    return [self.owner.window convertRectToScreen:[self.owner convertRect:rect toView:nil]];
}
- (NSRect)screenFrame:(NSArray *)frame {
    if (!self.isAccessibilityElement || !self.owner.window || !frame) return NSZeroRect;
    NSRect rect = NSMakeRect([frame[0] doubleValue], [frame[1] doubleValue], [frame[2] doubleValue], [frame[3] doubleValue]);
    rect = NSIntersectionRect(rect, self.owner.bounds);
    return NSIntersectionRect([self.owner.window convertRectToScreen:[self.owner convertRect:rect toView:nil]], self.accessibilityFrame);
}
- (id)accessibilityHitTest:(NSPoint)point {
    if (!self.isAccessibilityElement || !NSPointInRect(point, self.accessibilityFrame)) return nil;
    for (AXBGridCell *cell in [self.accessibilityVisibleCells reverseObjectEnumerator]) {
        NSRect visible = [self screenFrame:self.grid.descriptor[@"frames"][cell.row.key][cell.columnKey]];
        if (NSPointInRect(point, visible)) return [[cell accessibilityChildren] firstObject] ?: cell;
    }
    for (AXBGridHeader *header in self.accessibilityColumnHeaderUIElements)
        if (NSPointInRect(point, [self screenFrame:self.grid.descriptor[@"headers"][header.column.key]])) return header;
    return self;
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilitySelectedRows:)) return self.isAccessibilityEnabled && [self.grid.descriptor[@"actions"][@"select"] boolValue];
    if (selector == @selector(setAccessibilityFocused:)) return NO;
    return [super isAccessibilitySelectorAllowed:selector];
}
- (void)prepareGrid {
    AXBGrid *grid = [self.owner.session gridForNode:self.data[@"id"]];
    if (self.grid != grid) {
        NSMutableArray *retired = [NSMutableArray new];
        for (AXBGridRow *row in self.rowRegistry.allValues) {
            [retired addObject:row];
            for (AXBGridCell *cell in row.cells.allValues) { [retired addObject:cell]; if (cell.content) [retired addObject:cell.content]; }
        }
        for (AXBGridColumn *column in self.columnRegistry.allValues) { [retired addObject:column]; [retired addObject:column.header]; }
        if (self.headerGroup) [retired addObject:self.headerGroup];
        for (AXBGridPart *part in retired) part.live = NO;
        self.pendingDestroyed = retired;
        self.rowRegistry = [NSMutableDictionary new]; self.columnRegistry = [NSMutableDictionary new];
        self.grid = grid; self.lastDescriptor = nil; self.lastCacheSerial = 0;
        self.headerGroup = nil;
    }
}
- (void)refreshGrid {
    for (AXBGridPart *part in self.pendingDestroyed) NSAccessibilityPostNotification(part, NSAccessibilityUIElementDestroyedNotification);
    self.pendingDestroyed = nil;
    AXBGrid *grid = self.grid;
    NSDictionary *descriptor = grid.descriptor;
    if (!descriptor || !grid.active) return;
    // Warm only the actual viewport through the same bounded request queue.
    // Opening a table should not first announce placeholder text for cells
    // that have already been visible for several form cycles.
    for (NSString *row in descriptor[@"visible"]) for (NSString *column in descriptor[@"frames"][row])
        (void)[grid cellForRow:row column:column now:NSProcessInfo.processInfo.systemUptime];
    BOOL orderChanged = ![self.lastDescriptor[@"order"] isEqual:descriptor[@"order"]];
    if (orderChanged) {
        for (NSString *key in [self.rowRegistry.allKeys copy]) if ([grid indexOfRow:key] == NSNotFound) {
            [self.rowRegistry[key] invalidate]; [self.rowRegistry removeObjectForKey:key];
        }
        for (NSString *key in [self.columnRegistry.allKeys copy]) if ([grid indexOfColumn:key] == NSNotFound) {
            [self.columnRegistry[key] invalidate]; [self.columnRegistry removeObjectForKey:key];
        }
        NSSet *columns = [NSSet setWithArray:[descriptor[@"columns"] valueForKey:@"id"]];
        NSSet *previousColumns = [NSSet setWithArray:[self.lastDescriptor[@"columns"] valueForKey:@"id"] ?: @[]];
        if (![previousColumns isSubsetOfSet:columns]) for (AXBGridRow *row in self.rowRegistry.allValues)
            for (NSString *key in [row.cells.allKeys copy]) if (![columns containsObject:key]) {
                [row.cells[key] invalidate]; [row.cells removeObjectForKey:key];
            }
    }
    NSDictionary *cache = grid.cacheSnapshot;
    if (self.lastCacheSerial != [cache[@"serial"] unsignedIntegerValue]) {
        for (NSDictionary *page in cache[@"pages"]) for (NSDictionary *row in page[@"rows"]) for (NSDictionary *value in row[@"cells"]) {
            AXBGridCell *cell = self.rowRegistry[row[@"id"]].cells[value[@"column"]];
            if (cell && ![cell.lastValue isEqual:value]) {
                cell.lastValue = value; NSAccessibilityPostNotification(cell, NSAccessibilityValueChangedNotification);
                if (cell.content) (void)cell.accessibilityChildren;
                if (cell.content) NSAccessibilityPostNotification(cell.content, NSAccessibilityValueChangedNotification);
            }
        }
        self.lastCacheSerial = [cache[@"serial"] unsignedIntegerValue];
    }
    if (self.lastDescriptor && ![self.lastDescriptor[@"selected"] isEqual:descriptor[@"selected"]]) NSAccessibilityPostNotification(self, NSAccessibilitySelectedRowsChangedNotification);
    // The table layout notification alone leaves VoiceOver tracking the old
    // offscreen point. Notify the instantiated elements whose geometry moved.
    if (self.lastDescriptor && ![self.lastDescriptor[@"frames"] isEqual:descriptor[@"frames"]]) {
        for (AXBGridRow *row in self.rowRegistry.allValues) {
            for (AXBGridCell *cell in row.cells.allValues) {
                NSArray *before = self.lastDescriptor[@"frames"][row.key][cell.columnKey], *after = descriptor[@"frames"][row.key][cell.columnKey];
                if ((before || after) && ![before isEqual:after]) {
                    NSAccessibilityPostNotification(cell, NSAccessibilityMovedNotification);
                    if (cell.content) NSAccessibilityPostNotification(cell.content, NSAccessibilityMovedNotification);
                }
            }
        }
    }
    if (self.lastDescriptor) for (NSDictionary *column in descriptor[@"columns"]) {
        NSDictionary *previous = nil;
        for (NSDictionary *item in self.lastDescriptor[@"columns"]) if ([item[@"id"] isEqual:column[@"id"]]) { previous = item; break; }
        if (previous && ![previous[@"header"] isEqual:column[@"header"]] && (previous[@"header"] || column[@"header"])) {
            AXBGridHeader *header = self.columnRegistry[column[@"id"]].header;
            if (header) NSAccessibilityPostNotification(header, NSAccessibilityValueChangedNotification);
        }
    }
    NSDictionary *focus = descriptor[@"focused"], *previousFocus = self.lastDescriptor[@"focused"];
    if (focus) {
        AXBGridCell *cell = [[self row:focus[@"row"]] cell:focus[@"column"]];
        if (![focus[@"value"] isEqual:previousFocus[@"value"]] && focus[@"value"]) {
            NSAccessibilityPostNotification(cell, NSAccessibilityValueChangedNotification);
            if (cell.content) NSAccessibilityPostNotification(cell.content, NSAccessibilityValueChangedNotification);
        }
        if (![focus[@"selection"] isEqual:previousFocus[@"selection"]] && cell.content) NSAccessibilityPostNotification(cell.content, NSAccessibilitySelectedTextChangedNotification);
    }
    if (self.lastDescriptor && [self.lastDescriptor[@"rows"] count] != [descriptor[@"rows"] count]) NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
    if (self.lastDescriptor && (orderChanged || ![self.lastDescriptor[@"visible"] isEqual:descriptor[@"visible"]])) NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
    self.lastDescriptor = descriptor;
}
- (void)invalidate {
    [super invalidate];
    for (AXBGridRow *row in self.rowRegistry.allValues) [row invalidate];
    for (AXBGridColumn *column in self.columnRegistry.allValues) [column invalidate];
    [self.headerGroup invalidate]; self.headerGroup = nil;
    self.grid = nil; [self.rowRegistry removeAllObjects]; [self.columnRegistry removeAllObjects]; self.lastDescriptor = nil;
}
@end
