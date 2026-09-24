#import "Grid.h"
#include "Limits.h"
#import "Session.h"
#include <cmath>

static const NSUInteger RowBatch = 16, ColumnBatch = 8, PageLimit = 32, RequestLimit = 8;
static const NSUInteger CacheByteLimit = 8 * 1024 * 1024;
static BOOL Text(id value, NSUInteger maximum, BOOL nonempty = NO) {
    return [value isKindOfClass:NSString.class] && [value length] <= maximum &&
        (!nonempty || [value length]) && [value dataUsingEncoding:NSUTF8StringEncoding] != nil;
}
static BOOL Bool(id value) { return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID(); }
static BOOL Integer(id value, double minimum = 0) {
    return [value isKindOfClass:NSNumber.class] && !Bool(value) && std::isfinite([value doubleValue]) &&
        [value doubleValue] >= minimum && [value doubleValue] <= 9007199254740991.0 && floor([value doubleValue]) == [value doubleValue];
}
static BOOL Keys(id value, NSMutableSet *known) {
    if (![value isKindOfClass:NSArray.class]) return NO;
    for (id key in value) {
        if (!Text(key, 256, YES) || [known containsObject:key]) return NO;
        [known addObject:key];
    }
    return YES;
}
static BOOL Frame(id frame) {
    if (![frame isKindOfClass:NSArray.class] || [frame count] != 4) return NO;
    for (id part in frame) if (![part isKindOfClass:NSNumber.class] || Bool(part) || !std::isfinite([part doubleValue]) || fabs([part doubleValue]) > 100000) return NO;
    return [frame[2] doubleValue] > 0 && [frame[3] doubleValue] > 0;
}
BOOL AXBGridRowAllowsEditing(NSDictionary *descriptor, NSString *row) {
    // Older providers treated nonselectable rows as noneditable. New native
    // providers report the two independently, including single-click editors.
    NSArray *blocked = descriptor[@"uneditable"] ?: descriptor[@"unselectable"];
    return ![descriptor[@"disabled"] containsObject:row] && ![blocked containsObject:row];
}
BOOL AXBGridRowAllowsSelection(NSDictionary *descriptor, NSString *row) {
    // Native 4D can highlight a disabled row. Only its cells are disabled.
    // Keep the older provider contract when independent row states are absent.
    return ![descriptor[@"unselectable"] containsObject:row] &&
        (descriptor[@"uneditable"] || ![descriptor[@"disabled"] containsObject:row]);
}
NSString *AXBValidateGrid(id descriptor) {
    if (![descriptor isKindOfClass:NSDictionary.class]) return @"grid must be an object";
    if (!Text(descriptor[@"generation"], 128, YES) || !Integer(descriptor[@"order"], 1)) return @"invalid grid generation or order";
    NSMutableSet *rows = [NSMutableSet new], *columns = [NSMutableSet new];
    if (!Keys(descriptor[@"rows"], rows)) return @"invalid grid row identities";
    NSArray *definitions = descriptor[@"columns"];
    if (![definitions isKindOfClass:NSArray.class]) return @"invalid grid columns";
    for (id column in definitions) {
        if (![column isKindOfClass:NSDictionary.class] || !Text(column[@"id"], 256, YES) ||
            !Text(column[@"label"], 512) || !Bool(column[@"enabled"]) || !Bool(column[@"editable"]) ||
            [columns containsObject:column[@"id"]]) return @"invalid grid column";
        [columns addObject:column[@"id"]];
        id header = column[@"header"];
        if (header && (![header isKindOfClass:NSDictionary.class] || !Bool(header[@"visible"]) ||
            !Bool(header[@"enabled"]) || !Bool(header[@"press"]) || !Bool(header[@"sortable"]) ||
            ![@[@"none", @"ascending", @"descending"] containsObject:header[@"sort"] ?: @""])) return @"invalid grid header";
    }
    for (NSString *name in @[@"selected", @"visible"]) {
        NSMutableSet *subset = [NSMutableSet new];
        if (!Keys(descriptor[name], subset) || ![subset isSubsetOfSet:rows]) return @"invalid grid row subset";
    }
    for (NSString *name in @[@"disabled", @"unselectable", @"uneditable"]) if (descriptor[name]) {
        NSMutableSet *subset = [NSMutableSet new];
        if (!Keys(descriptor[name], subset) || ![subset isSubsetOfSet:rows]) return @"invalid grid row capability";
    }
    if (descriptor[@"frames"]) {
        if (![descriptor[@"frames"] isKindOfClass:NSDictionary.class]) return @"invalid grid geometry";
        for (NSString *key in descriptor[@"frames"]) {
            id cells = descriptor[@"frames"][key];
            if (![descriptor[@"visible"] containsObject:key] || ![cells isKindOfClass:NSDictionary.class]) return @"invalid grid row geometry";
            for (NSString *column in cells) if (![columns containsObject:column] || !Frame(cells[column])) return @"invalid grid cell geometry";
        }
    }
    if (descriptor[@"headers"]) {
        if (![descriptor[@"headers"] isKindOfClass:NSDictionary.class]) return @"invalid grid header geometry";
        for (NSString *column in descriptor[@"headers"]) if (![columns containsObject:column] || !Frame(descriptor[@"headers"][column])) return @"invalid grid header frame";
    }
    if (descriptor[@"headerHeight"] && (!Integer(descriptor[@"headerHeight"]) || [descriptor[@"headerHeight"] doubleValue] > 100000)) return @"invalid grid header height";
    // Layout bounds remain available outside the viewport. VoiceOver skips
    // zero-sized cells when navigating to an offscreen row. Store independent
    // row/column extents rather than one rectangle per logical cell.
    if (descriptor[@"layout"]) {
        id layout = descriptor[@"layout"];
        if (![layout isKindOfClass:NSDictionary.class]) return @"invalid grid layout";
        for (NSString *axis in @[@"rows", @"columns"]) {
            id extents = layout[axis];
            if (![extents isKindOfClass:NSArray.class] || [extents count] != [descriptor[axis] count]) return @"incomplete grid layout";
            for (id extent in extents) {
                if (![extent isKindOfClass:NSArray.class] || [extent count] != 2) return @"invalid grid layout extent";
                for (id number in extent) if (![number isKindOfClass:NSNumber.class] || Bool(number) || !std::isfinite([number doubleValue]) || fabs([number doubleValue]) > 1000000000) return @"invalid grid layout coordinate";
                if ([extent[1] doubleValue] <= 0) return @"invalid grid layout size";
            }
        }
    }
    if (descriptor[@"actions"]) {
        if (![descriptor[@"actions"] isKindOfClass:NSDictionary.class]) return @"invalid grid capabilities";
        for (NSString *operation in descriptor[@"actions"]) if (![@[@"select", @"reveal", @"edit"] containsObject:operation] || !Bool(descriptor[@"actions"][operation])) return @"invalid grid capability";
    }
    if (descriptor[@"focused"]) {
        id focused = descriptor[@"focused"];
        if (![focused isKindOfClass:NSDictionary.class] || ![rows containsObject:focused[@"row"]] || ![columns containsObject:focused[@"column"]]) return @"invalid focused grid cell";
        if (focused[@"value"] && !Text(focused[@"value"], AXBLimits::text)) return @"invalid grid editor text";
        if (focused[@"selection"]) {
            id range = focused[@"selection"];
            if (!focused[@"value"] || ![range isKindOfClass:NSArray.class] || [range count] != 2 || !Integer(range[0]) || !Integer(range[1]) ||
                !AXBTextRangeValid(focused[@"value"], NSMakeRange([range[0] unsignedIntegerValue], [range[1] unsignedIntegerValue]))) return @"invalid grid editor selection";
        }
    }
    return nil;
}
NSString *AXBValidateGridPage(id page) {
    if (![page isKindOfClass:NSDictionary.class] || !Text(page[@"node"], 128, YES) ||
        !Text(page[@"generation"], 128, YES) || !Integer(page[@"order"], 1) ||
        !Integer(page[@"row"]) || !Integer(page[@"column"])) return @"invalid grid page identity";
    NSArray *rows = page[@"rows"];
    if (![rows isKindOfClass:NSArray.class] || rows.count > RowBatch) return @"invalid grid page rows";
    for (id row in rows) {
        if (![row isKindOfClass:NSDictionary.class] || !Text(row[@"id"], 256, YES) ||
            ![row[@"cells"] isKindOfClass:NSArray.class] || [row[@"cells"] count] > ColumnBatch) return @"invalid grid page row";
        for (id cell in row[@"cells"]) {
            if (![cell isKindOfClass:NSDictionary.class] || !Text(cell[@"column"], 256, YES) ||
                !Text(cell[@"value"], AXBLimits::text) || !Bool(cell[@"enabled"]) || !Bool(cell[@"editable"])) return @"invalid grid cell";
            if (cell[@"role"] && ![@[@"text", @"checkbox", @"popup"] containsObject:cell[@"role"]]) return @"invalid grid cell role";
            if (cell[@"label"] && !Text(cell[@"label"], 512)) return @"invalid grid cell label";
            if (cell[@"focusable"] && !Bool(cell[@"focusable"])) return @"invalid grid cell focus capability";
            if ([cell[@"role"] isEqual:@"checkbox"]) {
                if (!Integer(cell[@"checked"]) || [cell[@"checked"] integerValue] > 2) return @"invalid grid checkbox state";
            } else if (cell[@"checked"]) return @"checkbox state requires a checkbox cell";
        }
    }
    return nil;
}
NSString *AXBValidateGridChange(NSDictionary *previous, NSDictionary *next) {
    if (![previous[@"generation"] isEqual:next[@"generation"]]) return nil;
    NSComparisonResult order = [next[@"order"] compare:previous[@"order"]];
    if (order == NSOrderedAscending) return @"grid order cannot go backwards";
    if (order == NSOrderedSame && (![previous[@"rows"] isEqual:next[@"rows"]] || ![previous[@"columns"] isEqual:next[@"columns"]]))
        return @"grid order must change when rows or columns change";
    return nil;
}
NSString *AXBValidateGridPageForDescriptor(NSDictionary *page, NSDictionary *descriptor) {
    NSString *error = AXBValidateGridPage(page);
    if (error) return error;
    if (!descriptor || ![descriptor[@"generation"] isEqual:page[@"generation"]] || ![descriptor[@"order"] isEqual:page[@"order"]]) return nil;
    NSUInteger start = [page[@"row"] unsignedIntegerValue], column = [page[@"column"] unsignedIntegerValue];
    NSArray *rows = descriptor[@"rows"], *columns = descriptor[@"columns"];
    if (start >= rows.count || column >= columns.count || start % RowBatch || column % ColumnBatch) return @"invalid grid page range";
    if ([page[@"rows"] count] != MIN(RowBatch, rows.count - start)) return @"incomplete grid page rows";
    NSUInteger index = start;
    for (NSDictionary *row in page[@"rows"]) {
        if (![row[@"id"] isEqual:rows[index++]] || [row[@"cells"] count] != MIN(ColumnBatch, columns.count - column)) return @"grid page row no longer matches";
        NSUInteger c = column;
        for (NSDictionary *cell in row[@"cells"]) if (![cell[@"column"] isEqual:columns[c++][@"id"]]) return @"grid page column no longer matches";
    }
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:page options:0 error:nil];
    return !bytes || bytes.length > CacheByteLimit ? @"grid page exceeds cache capacity" : nil;
}

@implementation AXBGrid {
    NSString *_nodeID;
    NSDictionary *_descriptor;
    NSDictionary *_rowIndexes, *_columnIndexes;
    NSMutableDictionary *_pages, *_requested;
    NSMutableArray *_recent;
    NSMutableOrderedSet *_queued;
    NSUInteger _cacheBytes;
    NSUInteger _cacheSerial;
    BOOL _active;
}
- (instancetype)initWithNode:(NSString *)nodeID descriptor:(NSDictionary *)descriptor {
    if (AXBValidateGrid(descriptor)) return nil;
    if ((self = [super init])) {
        _nodeID = [nodeID copy]; _active = YES;
        _pages = [NSMutableDictionary new]; _requested = [NSMutableDictionary new];
        _recent = [NSMutableArray new]; _queued = [NSMutableOrderedSet new];
        [self update:descriptor];
    }
    return self;
}
- (NSString *)nodeID { return _nodeID; }
- (BOOL)active { @synchronized(self) { return _active; } }
- (NSDictionary *)descriptor { @synchronized(self) { return _descriptor; } }
- (NSUInteger)cachedPageCount { @synchronized(self) { return _pages.count; } }
- (NSDictionary *)cacheSnapshot {
    @synchronized(self) {
        NSMutableArray *pages = [NSMutableArray new];
        for (NSDictionary *entry in _pages.allValues) [pages addObject:entry[@"page"]];
        return @{@"serial": @(_cacheSerial), @"pages": pages};
    }
}
- (void)update:(NSDictionary *)descriptor {
    @synchronized(self) {
        if (!_active) return;
        BOOL changed = ![_descriptor[@"generation"] isEqual:descriptor[@"generation"]] || ![_descriptor[@"order"] isEqual:descriptor[@"order"]];
        if (changed) {
            [_pages removeAllObjects]; [_requested removeAllObjects]; [_recent removeAllObjects]; [_queued removeAllObjects]; _cacheBytes = 0;
            _cacheSerial++;
        }
        if (![_descriptor[@"rows"] isEqual:descriptor[@"rows"]]) {
            NSMutableDictionary *indexes = [NSMutableDictionary new];
            [descriptor[@"rows"] enumerateObjectsUsingBlock:^(NSString *key, NSUInteger index, BOOL *stop) { (void)stop; indexes[key] = @(index); }];
            _rowIndexes = indexes;
        }
        if (![_descriptor[@"columns"] isEqual:descriptor[@"columns"]]) {
            NSMutableDictionary *indexes = [NSMutableDictionary new];
            [descriptor[@"columns"] enumerateObjectsUsingBlock:^(NSDictionary *column, NSUInteger index, BOOL *stop) { (void)stop; indexes[column[@"id"]] = @(index); }];
            _columnIndexes = indexes;
        }
        _descriptor = descriptor;
    }
}
- (NSUInteger)indexOfRow:(NSString *)key { @synchronized(self) { return _active && _rowIndexes[key] ? [_rowIndexes[key] unsignedIntegerValue] : NSNotFound; } }
- (NSUInteger)indexOfColumn:(NSString *)key { @synchronized(self) { return _active && _columnIndexes[key] ? [_columnIndexes[key] unsignedIntegerValue] : NSNotFound; } }
- (NSArray *)pageKeyForRow:(NSUInteger)row column:(NSUInteger)column { return @[@(row / RowBatch * RowBatch), @(column / ColumnBatch * ColumnBatch)]; }
- (void)expireRequestsAtTime:(NSTimeInterval)now {
    for (id key in [_requested.allKeys copy]) if (now - [_requested[key] doubleValue] > 3) [_requested removeObjectForKey:key];
}
- (NSDictionary *)cellForRow:(NSString *)row column:(NSString *)column now:(NSTimeInterval)now {
    @synchronized(self) {
        NSUInteger r = [self indexOfRow:row], c = [self indexOfColumn:column];
        if (r == NSNotFound || c == NSNotFound) return nil;
        [self expireRequestsAtTime:now];
        NSArray *key = [self pageKeyForRow:r column:c];
        NSDictionary *cached = _pages[key];
        if (!cached || now - [cached[@"time"] doubleValue] > 0.5) {
            if (!_requested[key] || now - [_requested[key] doubleValue] > 3) {
                if (_queued.count + _requested.count < RequestLimit) [_queued addObject:key];
            }
        }
        if (!cached) return nil;
        [_recent removeObject:key]; [_recent addObject:key];
        return cached[@"page"][@"rows"][r - [key[0] unsignedIntegerValue]][@"cells"][c - [key[1] unsignedIntegerValue]];
    }
}
- (NSArray *)takeRequestsAtTime:(NSTimeInterval)now {
    @synchronized(self) {
        if (!_active) return @[];
        NSMutableArray *result = [NSMutableArray new];
        for (NSArray *key in _queued) {
            [result addObject:@{@"node": _nodeID, @"generation": _descriptor[@"generation"], @"order": _descriptor[@"order"],
                @"row": key[0], @"column": key[1], @"rowCount": @(MIN(RowBatch, [_descriptor[@"rows"] count] - [key[0] unsignedIntegerValue])),
                @"columnCount": @(MIN(ColumnBatch, [_descriptor[@"columns"] count] - [key[1] unsignedIntegerValue]))}];
            _requested[key] = @(now);
        }
        [_queued removeAllObjects];
        return result;
    }
}
- (BOOL)acceptPage:(NSDictionary *)page now:(NSTimeInterval)now {
    if (AXBValidateGridPage(page)) return NO;
    @synchronized(self) {
        if (!_active || ![_nodeID isEqual:page[@"node"]] || ![_descriptor[@"generation"] isEqual:page[@"generation"]] ||
            ![_descriptor[@"order"] isEqual:page[@"order"]]) return YES;
        if (AXBValidateGridPageForDescriptor(page, _descriptor)) return NO;
        NSUInteger start = [page[@"row"] unsignedIntegerValue], column = [page[@"column"] unsignedIntegerValue];
        NSData *bytes = [NSJSONSerialization dataWithJSONObject:page options:0 error:nil];
        if (!bytes || bytes.length > CacheByteLimit) return NO;
        // Retain an immutable copy even when a test/embedded caller owns a
        // mutable page. Session callers already provide immutable JSON.
        page = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
        NSArray *key = [self pageKeyForRow:start column:column];
        if (![_pages[key][@"page"] isEqual:page]) _cacheSerial++;
        _cacheBytes -= [_pages[key][@"bytes"] unsignedIntegerValue];
        _pages[key] = @{@"page": page, @"time": @(now), @"bytes": @(bytes.length)};
        _cacheBytes += bytes.length;
        [_requested removeObjectForKey:key]; [_queued removeObject:key];
        [_recent removeObject:key]; [_recent addObject:key];
        while (_pages.count > PageLimit || _cacheBytes > CacheByteLimit) {
            id oldest = _recent.firstObject;
            _cacheBytes -= [_pages[oldest][@"bytes"] unsignedIntegerValue];
            [_pages removeObjectForKey:oldest]; [_recent removeObjectAtIndex:0];
        }
        return YES;
    }
}
- (void)invalidate {
    @synchronized(self) {
        _active = NO; [_pages removeAllObjects]; [_queued removeAllObjects]; [_requested removeAllObjects]; [_recent removeAllObjects];
        _descriptor = nil; _rowIndexes = nil; _columnIndexes = nil; _cacheBytes = 0;
    }
}
@end
