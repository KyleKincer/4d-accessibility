#import "InternalTable.h"

@class AXBInternalRow, AXBInternalColumn, AXBInternalCell;

// A column's title; with the table's menus, Show Menu is a secondary click on it.
@interface AXBInternalHeader : NSAccessibilityElement
@property(nonatomic, weak) AXBInternalColumn *column;
@end

// A cell's text. VoiceOver presses it with VO-Space, which selects its row.
@interface AXBInternalCellText : NSAccessibilityElement
@property(nonatomic, weak) AXBInternalCell *cell;
@end


@interface AXBInternalTable ()
@property(nonatomic, strong) NSMutableArray<AXBInternalRow *> *rows;
@property(nonatomic, strong) NSMutableArray<AXBInternalColumn *> *columns;
// The selected rows last announced.
@property(nonatomic, copy) NSArray *lastSelection;
// The header's band, in the layer's points from the bottom left.
@property(nonatomic) NSRect headerArea;
// The row last asked to be selected, and when.
@property(nonatomic) NSUInteger requestedRow;
@property(nonatomic) NSTimeInterval requestedAt;
@property(nonatomic, strong) NSAccessibilityElement *headerGroup;
@property(nonatomic) BOOL cellActions, menus, pointer;
@property(nonatomic, copy) NSIndexSet *editableColumns;
@end

@interface AXBInternalColumn : NSAccessibilityElement
@property(nonatomic, weak) AXBInternalTable *table;
@property(nonatomic) NSUInteger index;
@property(nonatomic) CGFloat x, width;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) AXBInternalHeader *header;
@end

@interface AXBInternalRow : NSAccessibilityElement
@property(nonatomic, weak) AXBInternalTable *table;
@property(nonatomic) NSUInteger index;
@property(nonatomic) NSRect area;
@property(nonatomic, strong) NSNumber *selected;
@property(nonatomic, strong) NSMutableArray *cells;
@end

@interface AXBInternalCell : NSAccessibilityElement
@property(nonatomic, weak) AXBInternalRow *row;
@property(nonatomic) NSUInteger column;
@property(nonatomic, copy) NSString *text;
// The cell's text, as a table's text cells hold it.
@property(nonatomic, strong) AXBInternalCellText *content;
// The cell's area, in the layer's points from the bottom left.
- (NSRect)area;
@end

static NSRect TableArea(AXBInternalTable *table, NSRect area) {
    CALayer *layer = table.layer;
    return layer ? [table.owner screenFrameForArea:area inLayer:layer] : NSZeroRect;
}

@implementation AXBInternalColumn
- (NSString *)accessibilityRole { return NSAccessibilityColumnRole; }
- (id)accessibilityParent { return self.table; }
- (BOOL)isAccessibilityElement { return self.table.isAccessibilityElement; }
- (NSInteger)accessibilityIndex { return (NSInteger)self.index; }
- (NSRect)accessibilityFrame {
    CALayer *layer = self.table.layer;
    return layer ? TableArea(self.table, NSMakeRect(self.x, 0, self.width, NSHeight(layer.bounds))) : NSZeroRect;
}
- (NSArray *)accessibilityChildren {
    NSMutableArray *cells = [NSMutableArray new];
    for (AXBInternalRow *row in self.table.rows) if (self.index < row.cells.count) [cells addObject:row.cells[self.index]];
    return cells;
}
- (id)accessibilityHeader { return self.header; }
@end

@implementation AXBInternalHeader
- (NSString *)accessibilityRole { return NSAccessibilityStaticTextRole; }
- (BOOL)accessibilityPerformShowMenu {
    AXBInternalTable *table = self.column.table;
    NSRect header = table.headerArea;
    return table.menus && [table.owner clickArea:NSMakeRect(self.column.x, NSMinY(header), self.column.width, NSHeight(header)) inLayer:table.layer
                                       secondary:YES movingPointer:table.pointer];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformShowMenu)) return self.column.table.menus;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@implementation AXBInternalCell
- (NSString *)accessibilityRole { return NSAccessibilityCellRole; }
- (id)accessibilityParent { return self.row; }
- (BOOL)isAccessibilityElement { return self.row.isAccessibilityElement; }
- (id)accessibilityValue { return self.text ?: @""; }
- (NSString *)accessibilityLabel {
    AXBInternalTable *table = self.row.table;
    return self.column < table.columns.count ? table.columns[self.column].title : nil;
}
- (NSRect)area {
    AXBInternalTable *table = self.row.table;
    if (self.column >= table.columns.count) return NSZeroRect;
    AXBInternalColumn *column = table.columns[self.column];
    NSRect area = self.row.area;
    return NSMakeRect(column.x, NSMinY(area), column.width, NSHeight(area));
}
- (NSRect)accessibilityFrame { return TableArea(self.row.table, self.area); }
- (BOOL)isEditable { return [self.row.table.editableColumns containsIndex:self.column]; }
- (NSArray *)accessibilityChildren {
    if (!self.content) self.content = (AXBInternalCellText *)[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:NSZeroRect label:nil parent:self];
    self.content.accessibilityValue = self.text ?: @"";
    self.content.accessibilityFrame = self.accessibilityFrame;
    return @[self.content];
}
- (NSRange)accessibilityColumnIndexRange { return NSMakeRange(self.column, 1); }
- (NSRange)accessibilityRowIndexRange { return NSMakeRange(self.row.index, 1); }
- (BOOL)isAccessibilitySelected { return self.row.isAccessibilitySelected; }
- (BOOL)accessibilityPerformPress {
    AXBInternalTable *table = self.row.table;
    return table.cellActions ? [table.owner clickArea:self.area inLayer:table.layer secondary:NO movingPointer:table.pointer] : [self.row accessibilityPerformPress];
}
- (BOOL)accessibilityPerformShowMenu {
    AXBInternalTable *table = self.row.table;
    return table.menus && [table.owner clickArea:self.area inLayer:table.layer secondary:YES movingPointer:table.pointer];
}
- (void)setAccessibilityValue:(id)value {
    AXBInternalTable *table = self.row.table;
    if (self.isEditable && [value isKindOfClass:NSString.class]) (void)[table.owner editText:value inArea:self.area ofLayer:table.layer movingPointer:table.pointer];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityValue:)) return self.isAccessibilityElement && self.isEditable;
    if (selector == @selector(setAccessibilityFocused:) || selector == @selector(setAccessibilitySelected:)) return NO;
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformShowMenu)) return self.isAccessibilityElement && self.row.table.menus;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@implementation AXBInternalCellText
- (NSString *)accessibilityRole { return NSAccessibilityStaticTextRole; }
- (id)accessibilityParent { return self.cell; }
- (BOOL)isAccessibilityElement { return self.cell.isAccessibilityElement; }
- (BOOL)accessibilityPerformPress { return [self.cell accessibilityPerformPress]; }
- (BOOL)accessibilityPerformShowMenu { return [self.cell accessibilityPerformShowMenu]; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.isAccessibilityElement;
    if (selector == @selector(accessibilityPerformShowMenu)) return [self.cell isAccessibilitySelectorAllowed:selector];
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@implementation AXBInternalRow
- (NSString *)accessibilityRole { return NSAccessibilityRowRole; }
- (NSString *)accessibilitySubrole { return NSAccessibilityTableRowSubrole; }
- (id)accessibilityParent { return self.table; }
- (BOOL)isAccessibilityElement { return self.table.isAccessibilityElement; }
- (NSInteger)accessibilityIndex { return (NSInteger)self.index; }
- (NSArray *)accessibilityChildren { return self.cells; }
- (NSRect)accessibilityFrame { return TableArea(self.table, self.area); }
- (BOOL)isAccessibilitySelected { return self.selected.boolValue; }
// Selecting a row is an ordinary click on it, as the mouse selects it.
- (void)setAccessibilitySelected:(BOOL)selected { if (selected) [self.table setAccessibilitySelectedRows:@[self]]; }
- (BOOL)accessibilityPerformPress {
    if (self.table.cellActions) return self.cells.count && [self.cells.firstObject accessibilityPerformPress];
    return [self.table.owner clickArea:self.area inLayer:self.table.layer];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilitySelected:) || selector == @selector(accessibilityPerformPress)) return self.isAccessibilityElement;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@implementation AXBInternalTable
- (NSArray *)accessibilityChildren {
    NSMutableArray *children = [NSMutableArray arrayWithArray:self.rows ?: @[]];
    [children addObjectsFromArray:self.columns ?: @[]];
    if (self.accessibilityHeader) [children addObject:self.accessibilityHeader];
    return children;
}
// The column titles, as a group, as AppKit's tables publish their header.
- (id)accessibilityHeader {
    if (!self.columns.count) return nil;
    if (!self.headerGroup) self.headerGroup = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityGroupRole frame:NSZeroRect label:nil parent:self];
    self.headerGroup.accessibilityChildren = self.accessibilityColumnHeaderUIElements;
    self.headerGroup.accessibilityFrame = TableArea(self, self.headerArea);
    return self.headerGroup;
}
- (NSArray *)accessibilityRows { return self.rows ?: @[]; }
- (NSArray *)accessibilityVisibleRows { return self.rows ?: @[]; }
- (NSInteger)accessibilityRowCount { return (NSInteger)self.rows.count; }
- (NSArray *)accessibilityColumns { return self.columns ?: @[]; }
- (NSArray *)accessibilityVisibleColumns { return self.columns ?: @[]; }
- (NSInteger)accessibilityColumnCount { return (NSInteger)self.columns.count; }
- (NSArray *)accessibilityColumnHeaderUIElements {
    NSMutableArray *headers = [NSMutableArray new];
    for (AXBInternalColumn *column in self.columns) if (column.header) [headers addObject:column.header];
    return headers;
}
- (NSArray *)accessibilitySelectedRows {
    NSMutableArray *rows = [NSMutableArray new];
    for (AXBInternalRow *row in self.rows) if (row.selected.boolValue) [rows addObject:row];
    return rows;
}
- (void)setAccessibilitySelectedRows:(NSArray *)rows {
    // One row is selected as the mouse selects it: the first one asked for. VoiceOver asks
    // again for the row under its cursor as it moves; a row already selected, or just asked
    // for, is not clicked again.
    AXBInternalRow *row = [rows.firstObject isKindOfClass:AXBInternalRow.class] && [self.rows containsObject:rows.firstObject] ? rows.firstObject : nil;
    if (!row || row.selected.boolValue) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (row.index == self.requestedRow && now - self.requestedAt < 1) return;
    self.requestedRow = row.index; self.requestedAt = now;
    (void)[row accessibilityPerformPress];
}
- (id)accessibilityCellForColumn:(NSInteger)column row:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.rows.count || column < 0) return nil;
    NSArray *cells = self.rows[row].cells;
    return (NSUInteger)column < cells.count ? cells[column] : nil;
}
- (id)accessibilityValue { return nil; }
- (BOOL)accessibilityPerformPress { return NO; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilitySelectedRows:)) return self.isAccessibilityElement && self.rows.count > 0;
    if (selector == @selector(accessibilityPerformPress) || selector == @selector(setAccessibilityValue:)) return NO;
    return [super isAccessibilitySelectorAllowed:selector];
}
- (void)updateWithModel:(NSDictionary *)model {
    if (!self.rows) self.rows = [NSMutableArray new];
    if (!self.columns) self.columns = [NSMutableArray new];
    NSArray *columns = model[@"columns"], *rows = model[@"rows"];
    BOOL layout = columns.count != self.columns.count;
    while (self.columns.count > columns.count) [self.columns removeLastObject];
    [columns enumerateObjectsUsingBlock:^(NSDictionary *spec, NSUInteger index, BOOL *stop) {
        (void)stop;
        AXBInternalColumn *column = index < self.columns.count ? self.columns[index] : nil;
        if (!column) {
            column = [AXBInternalColumn new];
            column.table = self; column.index = index;
            AXBInternalHeader *header = [AXBInternalHeader new];
            header.column = column;
            header.accessibilityParent = column;
            column.header = header;
            [self.columns addObject:column];
        }
        column.x = [spec[@"x"] doubleValue]; column.width = [spec[@"width"] doubleValue];
        column.title = spec[@"header"];
        column.header.accessibilityValue = spec[@"header"] ?: @"";
    }];
    self.headerArea = model[@"header"] ? [model[@"header"] rectValue] : NSZeroRect;
    self.cellActions = [model[@"cellActions"] boolValue];
    self.menus = [model[@"menus"] boolValue];
    self.pointer = [model[@"pointer"] boolValue];
    self.editableColumns = model[@"editableColumns"];
    for (AXBInternalColumn *column in self.columns) {
        column.header.accessibilityParent = self.accessibilityHeader;
        column.header.accessibilityFrame = TableArea(self, NSMakeRect(column.x, NSMinY(self.headerArea), column.width, NSHeight(self.headerArea)));
    }
    NSInteger before = (NSInteger)self.rows.count;
    while (self.rows.count > rows.count) [self.rows removeLastObject];
    [rows enumerateObjectsUsingBlock:^(NSDictionary *spec, NSUInteger index, BOOL *stop) {
        (void)stop;
        AXBInternalRow *row = index < self.rows.count ? self.rows[index] : nil;
        if (!row) {
            row = [AXBInternalRow new];
            row.table = self; row.index = index; row.cells = [NSMutableArray new];
            [self.rows addObject:row];
        }
        row.area = [spec[@"area"] rectValue];
        NSNumber *selected = spec[@"selected"];
        row.selected = selected;
        NSArray *texts = spec[@"cells"];
        while (row.cells.count > texts.count) [row.cells removeLastObject];
        [texts enumerateObjectsUsingBlock:^(NSString *text, NSUInteger column, BOOL *inner) {
            (void)inner;
            AXBInternalCell *cell = column < row.cells.count ? row.cells[column] : nil;
            if (!cell) { cell = [AXBInternalCell new]; cell.row = row; cell.column = column; [row.cells addObject:cell]; }
            if (![cell.text isEqual:text]) {
                BOOL known = cell.text != nil;
                cell.text = text;
                if (known) NSAccessibilityPostNotification(cell, NSAccessibilityValueChangedNotification);
            }
        }];
    }];
    // Announce a changed selection, and a changed number of rows or columns.
    NSArray *selected = [self.accessibilitySelectedRows valueForKey:@"index"];
    if (![selected isEqual:self.lastSelection]) {
        if (self.lastSelection) NSAccessibilityPostNotification(self, NSAccessibilitySelectedRowsChangedNotification);
        self.lastSelection = selected;
    }
    if ((NSInteger)self.rows.count != before) NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
    if (layout) NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
}
@end
