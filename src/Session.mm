#import "Session.h"
#import "Grid.h"
#include "Limits.h"
#include <cmath>

static BOOL Text(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class] || [value length] > limit) return NO;
    for (NSUInteger index = 0; index < [value length]; index++) {
        unichar unit = [value characterAtIndex:index];
        if (unit >= 0xD800 && unit <= 0xDBFF) {
            if (++index >= [value length]) return NO;
            unichar low = [value characterAtIndex:index];
            if (low < 0xDC00 || low > 0xDFFF) return NO;
        } else if (unit >= 0xDC00 && unit <= 0xDFFF) return NO;
    }
    return YES;
}
static BOOL Bool(id value) {
    return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
static BOOL Number(id value) {
    return [value isKindOfClass:NSNumber.class] && !Bool(value) && std::isfinite([value doubleValue]);
}

BOOL AXBTextRangeValid(NSString *text, NSRange range) {
    if (range.location > text.length || range.length > text.length - range.location) return NO;
    for (NSNumber *boundary in @[@(range.location), @(NSMaxRange(range))]) {
        NSUInteger index = boundary.unsignedIntegerValue;
        if (index < text.length) {
            unichar unit = [text characterAtIndex:index];
            if (unit >= 0xDC00 && unit <= 0xDFFF) return NO;
        }
    }
    return YES;
}

// A clock, status label or separately loaded grid page must not starve an
// action on an unchanged control. Retain its complete state and ancestry, plus
// the table's ordered subtree for selection. Identity includes the host's form
// generation/scope. Focus and the window label remain contextual guards.
static NSDictionary *ActionState(NSDictionary *snapshot, NSDictionary *action) {
    NSMutableDictionary *nodes = [NSMutableDictionary new];
    NSMutableArray *focused = [NSMutableArray new];
    for (NSDictionary *node in snapshot[@"nodes"]) {
        nodes[node[@"id"]] = node;
        if ([node[@"focused"] boolValue]) [focused addObject:node[@"id"]];
    }
    [focused sortUsingSelector:@selector(compare:)];
    NSDictionary *target = nodes[action[@"node"]];
    if (!target) return nil;
    NSMutableDictionary *dependencies = [NSMutableDictionary new];
    for (NSDictionary *node = target; node; node = nodes[node[@"parent"]]) {
        dependencies[node[@"id"]] = node;
        if (node[@"labelledBy"]) dependencies[node[@"labelledBy"]] = nodes[node[@"labelledBy"]];
    }
    NSMutableArray *rows = [NSMutableArray new];
    if ([action[@"operation"] isEqual:@"selectRows"]) {
        for (NSDictionary *node in snapshot[@"nodes"]) {
            NSDictionary *parent = nodes[node[@"parent"]];
            if ([node[@"parent"] isEqual:target[@"id"]] || [parent[@"parent"] isEqual:target[@"id"]])
                [rows addObject:node];
        }
    }
    return @{@"label": snapshot[@"label"], @"enabled": snapshot[@"enabled"],
        @"focused": focused, @"nodes": dependencies, @"rows": rows};
}

// A newly activated 4D form can assign initial focus after the action was
// queued. Accept only focus arriving on that exact target with every other
// dependency unchanged. In particular, values, selections and prior focus
// in another control remain strict guards. Never use this after dispatch.
static BOOL SameDispatchState(NSDictionary *before, NSDictionary *after, NSString *target) {
    if ([before isEqual:after]) return YES;
    if (!before || !after || [before[@"focused"] count] != 0 ||
        ![after[@"focused"] isEqual:@[target]]) return NO;
    NSDictionary *oldNode = before[@"nodes"][target], *newNode = after[@"nodes"][target];
    if (!oldNode || !newNode || [oldNode[@"focused"] boolValue] || ![newNode[@"focused"] boolValue]) return NO;
    NSMutableDictionary *normalizedNode = [newNode mutableCopy];
    if (oldNode[@"focused"]) normalizedNode[@"focused"] = oldNode[@"focused"];
    else [normalizedNode removeObjectForKey:@"focused"];
    NSMutableDictionary *nodes = [after[@"nodes"] mutableCopy];
    nodes[target] = normalizedNode;
    NSMutableDictionary *normalized = [after mutableCopy];
    normalized[@"focused"] = before[@"focused"];
    normalized[@"nodes"] = nodes;
    return [before isEqual:normalized];
}

static BOOL SameGridDispatchValue(NSDictionary *before, NSDictionary *after, NSDictionary *action) {
    if ([before isEqual:after]) return YES;
    if (!before || !after || !action[@"value"][@"expectedEditor"] ||
        ![@[@"gridSetValue", @"gridSetSelection", @"gridReplaceSelection"] containsObject:action[@"operation"]]) return NO;
    // A text editor owns its current value and selection. A delayed backing
    // page can catch up after Undo/Redo while that editor is unchanged. Keep
    // all cached capability guards, and let SameDispatchState compare the
    // exact live editor, focus, identity and generation independently.
    NSMutableDictionary *oldCell = [before mutableCopy], *newCell = [after mutableCopy];
    [oldCell removeObjectForKey:@"value"]; [newCell removeObjectForKey:@"value"];
    return [oldCell isEqual:newCell];
}

NSString *AXBValidateEnvelope(NSDictionary *envelope) {
    if (![envelope isKindOfClass:NSDictionary.class]) return @"envelope must be an object";
    NSDictionary *s = envelope[@"snapshot"];
    if (![s isKindOfClass:NSDictionary.class]) return @"snapshot must be an object";
    if (!Number(s[@"version"]) || [s[@"version"] integerValue] != 1 || [s[@"version"] doubleValue] != 1) return @"unsupported protocol version";
    double revision = [s[@"revision"] respondsToSelector:@selector(doubleValue)] ? [s[@"revision"] doubleValue] : 0;
    if (!Number(s[@"revision"]) || revision < 1 || revision > 9007199254740991.0 || floor(revision) != revision) return @"invalid revision";
    if (!Text(s[@"label"], 512) || !Bool(s[@"enabled"])) return @"invalid window metadata";
    NSArray *nodes = s[@"nodes"];
    if (![nodes isKindOfClass:NSArray.class] || nodes.count > AXBLimits::nodes) return @"invalid node count";
    NSMutableSet *ids = [NSMutableSet new];
    NSMutableDictionary *byID = [NSMutableDictionary new];
    NSSet *roles = [NSSet setWithArray:@[@"button", @"checkbox", @"radio", @"popup", @"textfield", @"text", @"table", @"row", @"cell", @"group", @"image", @"progress", @"slider", @"stepper"]];
    for (id raw in nodes) {
        if (![raw isKindOfClass:NSDictionary.class]) return @"invalid node";
        NSDictionary *n = raw;
        NSString *identifier = n[@"id"];
        if (!Text(identifier, 128) || !identifier.length || [ids containsObject:identifier]) return @"invalid or duplicate node identifier";
        [ids addObject:identifier];
        byID[identifier] = n;
        if (![roles containsObject:n[@"role"] ?: @""]) return @"unsupported role";
        if (n[@"grid"]) {
            if (![n[@"role"] isEqual:@"table"]) return @"grid descriptor requires a table";
            NSString *gridError = AXBValidateGrid(n[@"grid"]);
            if (gridError) return gridError;
        }
        if (!Text(n[@"label"], 512) || !Bool(n[@"enabled"]) || !Bool(n[@"visible"])) return @"invalid node metadata";
        NSArray *frame = n[@"frame"];
        if (![frame isKindOfClass:NSArray.class] || frame.count != 4) return @"invalid frame";
        for (id dimension in frame) if (!Number(dimension) || fabs([dimension doubleValue]) > 100000) return @"invalid frame coordinate";
        if ([frame[2] doubleValue] <= 0 || [frame[3] doubleValue] <= 0) return @"empty frame";
        NSArray *clip = n[@"clip"];
        NSArray *navigation = n[@"navigation"];
        if (navigation) {
            if (![navigation isKindOfClass:NSArray.class] || navigation.count < 2 || navigation.count > 18 || navigation.count % 2) return @"invalid navigation path";
            for (id coordinate in navigation) if (!Number(coordinate) || fabs([coordinate doubleValue]) > 100000) return @"invalid navigation coordinate";
        }
        if (clip) {
            if (![clip isKindOfClass:NSArray.class] || clip.count != 4) return @"invalid clipping rectangle";
            for (id coordinate in clip) if (!Number(coordinate) || fabs([coordinate doubleValue]) > 100000) return @"invalid clip coordinate";
            if ([clip[2] doubleValue] < 0 || [clip[3] doubleValue] < 0) return @"negative clipping size";
        }
        if ([@[@"slider", @"stepper"] containsObject:n[@"role"]]) {
            if (!Bool(n[@"adjustable"]) || !Number(n[@"step"]) || [n[@"step"] doubleValue] <= 0) return @"invalid adjustment capability";
            if (n[@"vertical"] && !Bool(n[@"vertical"])) return @"invalid adjustment orientation";
            if (n[@"adjustment"] && ![@[@"keyboard", @"pointer", @"callback"] containsObject:n[@"adjustment"]]) return @"invalid adjustment route";
            if ([n[@"adjustment"] isEqual:@"pointer"] && ![n[@"role"] isEqual:@"stepper"]) return @"pointer adjustment requires a stepper";
            if ([n[@"role"] isEqual:@"stepper"] && Text(n[@"value"], 512)) {
                if (n[@"min"] || n[@"max"]) return @"formatted date stepper cannot claim a numeric range";
            } else if (!Number(n[@"value"]) || !Number(n[@"min"]) || !Number(n[@"max"]) ||
                       [n[@"min"] doubleValue] > [n[@"max"] doubleValue]) return @"invalid adjustable range";
        } else if ([n[@"role"] isEqual:@"progress"]) {
            if (n[@"vertical"] && !Bool(n[@"vertical"])) return @"invalid progress orientation";
            if (!Bool(n[@"indeterminate"])) return @"invalid progress mode";
            if ([n[@"indeterminate"] boolValue]) {
                if (n[@"value"] != NSNull.null) return @"indeterminate progress must omit its value";
            } else if (!Number(n[@"value"]) || !Number(n[@"min"]) || !Number(n[@"max"]) ||
                [n[@"min"] doubleValue] > [n[@"max"] doubleValue]) return @"invalid progress range";
        } else if ([n[@"role"] isEqual:@"checkbox"]) {
            if (!Bool(n[@"value"]) && !(Number(n[@"value"]) && [n[@"value"] doubleValue] == 2)) return @"invalid checkbox state";
        } else if ([n[@"role"] isEqual:@"radio"] ? !Bool(n[@"value"]) : !Text(n[@"value"], AXBLimits::text)) return @"invalid node value";
        if (n[@"valueDescription"] && !Text(n[@"valueDescription"], AXBLimits::text)) return @"invalid value description";
        for (NSString *key in @[@"focused", @"focusable", @"editable", @"protected", @"multiline", @"combo", @"revealable"])
            if (n[key] && !Bool(n[key])) return @"invalid control capability";
        if ([n[@"combo"] boolValue] && (![n[@"role"] isEqual:@"textfield"] || [n[@"multiline"] boolValue])) return @"combo requires single-line text";
        if (n[@"labelledBy"] && !Text(n[@"labelledBy"], 128)) return @"invalid label relationship";
        if (n[@"placeholder"] && !Text(n[@"placeholder"], 512)) return @"invalid placeholder";
        if ([n[@"protected"] boolValue] && (![n[@"role"] isEqual:@"textfield"] || ![n[@"value"] isEqual:@""])) return @"protected text must omit its value";
        if (n[@"selection"]) {
            NSArray *range = n[@"selection"];
            if (![n[@"role"] isEqual:@"textfield"] || [n[@"protected"] boolValue] || ![range isKindOfClass:NSArray.class] || range.count != 2) return @"invalid text selection";
            for (id part in range) if (!Number(part) || [part doubleValue] < 0 || floor([part doubleValue]) != [part doubleValue]) return @"invalid text selection";
            if ([range[0] doubleValue] + [range[1] doubleValue] > [n[@"value"] length]) return @"invalid text selection";
            if (!AXBTextRangeValid(n[@"value"], NSMakeRange([range[0] unsignedIntegerValue], [range[1] unsignedIntegerValue]))) return @"text selection splits a character";
        }
        if (n[@"parent"] && !Text(n[@"parent"], 128)) return @"invalid parent";
        if ([n[@"role"] isEqual:@"row"] && (!Bool(n[@"selected"]) || !Number(n[@"index"]) || [n[@"index"] doubleValue] < 0 ||
            [n[@"index"] doubleValue] >= 256 || floor([n[@"index"] doubleValue]) != [n[@"index"] doubleValue])) return @"invalid row state";
        // Protected fields are represented without transmitting their contents.
    }
    // Ordinary controls can belong to semantic groups. Table rows/cells retain
    // their stricter hierarchy. Validate all ancestry before following it.
    for (NSDictionary *n in nodes) {
        NSString *role = n[@"role"];
        NSString *expected = [role isEqual:@"row"] ? @"table" : [role isEqual:@"cell"] ? @"row" : nil;
        if (expected && (!n[@"parent"] || ![byID[n[@"parent"]][@"role"] isEqual:expected])) return @"invalid table hierarchy";
        if (n[@"parent"] && byID[n[@"parent"]][@"grid"]) return @"logical grid cannot mix explicit summary rows";
        if (!expected && n[@"parent"] && ![byID[n[@"parent"]][@"role"] isEqual:@"group"]) return @"invalid group parent";
        NSMutableSet *ancestors = [NSMutableSet new];
        for (NSDictionary *ancestor = n; ancestor; ancestor = byID[ancestor[@"parent"]]) {
            if ([ancestors containsObject:ancestor[@"id"]] || ancestors.count >= 32) return @"invalid control ancestry";
            [ancestors addObject:ancestor[@"id"]];
            if (ancestor[@"parent"] && !byID[ancestor[@"parent"]]) return @"missing control parent";
        }
        if (n[@"labelledBy"] && (![byID[n[@"labelledBy"]][@"role"] isEqual:@"text"] || [n[@"id"] isEqual:n[@"labelledBy"]])) return @"invalid label relationship";
    }
    if (envelope[@"gridPages"]) {
        NSArray *pages = envelope[@"gridPages"];
        if (![pages isKindOfClass:NSArray.class] || pages.count > 32) return @"invalid grid page batch";
        for (id page in pages) {
            NSString *pageError = AXBValidateGridPage(page);
            if (pageError) return pageError;
            pageError = AXBValidateGridPageForDescriptor(page, byID[page[@"node"]][@"grid"]);
            if (pageError) return pageError;
        }
    }
    id receipt = envelope[@"receipt"];
    if (receipt) {
        if (![receipt isKindOfClass:NSDictionary.class] || !Text(receipt[@"id"], 128) ||
            ![@[@"completed", @"rejected"] containsObject:receipt[@"status"] ?: @""] ||
            !Text(receipt[@"message"], 512)) return @"invalid action receipt";
    }
    NSDictionary *input = envelope[@"editorInput"];
    if (input) {
        if (![input isKindOfClass:NSDictionary.class] || !Text(input[@"action"], 128) || !Number(input[@"serial"]) ||
            [input[@"serial"] doubleValue] < 1 || [input[@"serial"] doubleValue] > 1048576 || floor([input[@"serial"] doubleValue]) != [input[@"serial"] doubleValue] ||
            !Text(input[@"text"], AXBLimits::text)) return @"invalid editor input";
        if (input[@"mode"]) {
            if (![input[@"mode"] isEqual:@"insert"] || [input[@"serial"] integerValue] != 1 || ![input[@"text"] length]) return @"invalid text insertion";
            NSArray *range = input[@"selection"];
            if (![range isKindOfClass:NSArray.class] || range.count != 2) return @"invalid insertion selection";
            for (id part in range) if (!Number(part) || [part doubleValue] < 0 || [part doubleValue] > AXBLimits::text || floor([part doubleValue]) != [part doubleValue]) return @"invalid insertion selection";
        } else {
            if ([input[@"text"] length] != 2) return @"invalid editor input";
            unichar high = [input[@"text"] characterAtIndex:0], low = [input[@"text"] characterAtIndex:1];
            if (high < 0xD800 || high > 0xDBFF || low < 0xDC00 || low > 0xDFFF) return @"editor input must contain one supplementary character";
        }
        if (receipt) return @"editor input cannot accompany a final receipt";
    }
    NSDictionary *controlInput = envelope[@"controlInput"];
    if (controlInput) {
        if (![controlInput isKindOfClass:NSDictionary.class] || !Text(controlInput[@"action"], 128) || input || receipt)
            return @"invalid control input";
        NSArray *point = controlInput[@"point"];
        if (point && (![point isKindOfClass:NSArray.class] || point.count != 2 || !Number(point[0]) || !Number(point[1])))
            return @"invalid control input point";
        if (controlInput.count != (point ? 2 : 1)) return @"invalid control input";
    }
    return nil;
}

@implementation AXBSession {
    NSString *_identifier;
    NSInteger _windowID;
    NSDictionary *_snapshot;
    NSMutableDictionary<NSString *, AXBGrid *> *_grids;
    BOOL _active;
    NSDictionary *_pending;
    NSDictionary *_pendingState;
    NSDictionary *_pendingGridValue;
    BOOL _delivered;
    NSTimeInterval _queuedAt;
    NSString *_lastReceiptID;
    NSDictionary *_lastReceipt;
    NSDictionary *_lastResult;
    NSInteger _lastInputSerial;
    NSDictionary *_lastInput;
    NSDictionary *_inputResult;
    NSDictionary *_controlInput;
    NSDictionary *_controlInputState;
    NSDictionary *_controlInputResult;
    BOOL _controlMenuOpened;
}
- (instancetype)initWithIdentifier:(NSString *)identifier windowID:(NSInteger)windowID {
    if ((self = [super init])) { _identifier = [identifier copy]; _windowID = windowID; _active = YES; _grids = [NSMutableDictionary new]; }
    return self;
}
- (NSString *)identifier { return _identifier; }
- (NSInteger)windowID { return _windowID; }
- (NSDictionary *)snapshot { @synchronized(self) { return _snapshot; } }
- (BOOL)active { @synchronized(self) { return _active; } }
- (NSDictionary *)activity {
    @synchronized(self) {
        NSMutableDictionary *result = [@{@"busy": @(_pending != nil), @"delivered": @(_delivered)} mutableCopy];
        if (_pending) result[@"id"] = _pending[@"id"];
        if (_lastResult) result[@"result"] = _lastResult;
        return [result copy];
    }
}
- (AXBGrid *)gridForNode:(NSString *)nodeID { @synchronized(self) { return _grids[nodeID]; } }
- (void)invalidate {
    @synchronized(self) {
        _active = NO; _pending = nil; _pendingState = nil; _pendingGridValue = nil; _delivered = NO; _snapshot = nil; _lastInput = nil; _inputResult = nil; _controlInput = nil; _controlInputState = nil; _controlInputResult = nil;
        for (AXBGrid *grid in _grids.allValues) [grid invalidate];
        [_grids removeAllObjects];
    }
}
- (NSDictionary *)controlInputNode:(NSDictionary *)input snapshot:(NSDictionary *)snapshot {
    if (!_active || !_delivered || ![_pending[@"id"] isEqual:input[@"action"]] ||
        ![snapshot[@"enabled"] boolValue]) return nil;
    for (NSDictionary *node in snapshot[@"nodes"]) if ([node[@"id"] isEqual:_pending[@"node"]]) {
        if (![node[@"enabled"] boolValue] || ![node[@"visible"] boolValue]) return nil;
        if ([_pending[@"operation"] isEqual:@"gridHeaderPress"]) {
            NSDictionary *target = _pending[@"value"], *grid = node[@"grid"];
            NSArray *point = input[@"point"], *frame = grid[@"headers"][target[@"column"]];
            if (!point || !frame || ![grid[@"generation"] isEqual:target[@"generation"]]) return nil;
            double x = [point[0] doubleValue], y = [point[1] doubleValue];
            if (x < [frame[0] doubleValue] || y < [frame[1] doubleValue] ||
                x >= [frame[0] doubleValue] + [frame[2] doubleValue] || y >= [frame[1] doubleValue] + [frame[3] doubleValue]) return nil;
            for (NSDictionary *column in grid[@"columns"]) if ([column[@"id"] isEqual:target[@"column"]]) {
                NSDictionary *header = column[@"header"];
                return [header[@"visible"] boolValue] && [header[@"enabled"] boolValue] && [header[@"press"] boolValue] &&
                    [header isEqual:target[@"expectedHeader"]] ? node : nil;
            }
            return nil;
        }
        if ([_pending[@"operation"] isEqual:@"gridPress"]) {
            NSDictionary *target = _pending[@"value"], *grid = node[@"grid"], *expected = target[@"expectedCell"];
            NSArray *point = input[@"point"], *frame = grid[@"frames"][target[@"row"]][target[@"column"]];
            if (!point || !frame || ![grid[@"generation"] isEqual:target[@"generation"]] ||
                ![grid[@"actions"][@"edit"] boolValue] || !AXBGridRowAllowsEditing(grid, target[@"row"]) ||
                ![@[@"checkbox", @"popup"] containsObject:expected[@"role"] ?: @""] ||
                ![expected[@"enabled"] boolValue] || ![expected[@"editable"] boolValue]) return nil;
            double x = [point[0] doubleValue], y = [point[1] doubleValue];
            if (x < [frame[0] doubleValue] || y < [frame[1] doubleValue] ||
                x >= [frame[0] doubleValue] + [frame[2] doubleValue] || y >= [frame[1] doubleValue] + [frame[3] doubleValue]) return nil;
            for (NSDictionary *column in grid[@"columns"]) if ([column[@"id"] isEqual:target[@"column"]])
                return [column[@"enabled"] boolValue] && [column[@"editable"] boolValue] ? node : nil;
            return nil;
        }
        return !input[@"point"] && [@[@"increment", @"decrement"] containsObject:_pending[@"operation"]] &&
            ([node[@"role"] isEqual:@"stepper"] && (!node[@"adjustment"] || [node[@"adjustment"] isEqual:@"pointer"])) &&
            [node[@"adjustable"] boolValue] ? node : nil;
    }
    return nil;
}
- (NSDictionary *)controlInputNode:(NSDictionary *)input {
    @synchronized(self) {
        if (![_controlInput isEqual:input] || _controlInputResult || ![_controlInputState isEqual:ActionState(_snapshot, _pending)]) return nil;
        NSDictionary *node = [self controlInputNode:input snapshot:_snapshot];
        if (!node) return nil;
        NSDictionary *expected = _pending[@"value"][@"expectedCell"];
        if ([_pending[@"operation"] isEqual:@"gridPress"] && ![expected isEqual:[_grids[_pending[@"node"]] cellForRow:_pending[@"value"][@"row"] column:_pending[@"value"][@"column"] now:NSProcessInfo.processInfo.systemUptime]]) return nil;
        NSMutableDictionary *result = [node mutableCopy];
        result[@"operation"] = _pending[@"operation"];
        if ([@[@"gridPress", @"gridHeaderPress"] containsObject:_pending[@"operation"]]) result[@"target"] = _pending[@"value"];
        return result;
    }
}
- (void)finishControlInput:(NSDictionary *)input accepted:(BOOL)accepted {
    @synchronized(self) {
        if (!_active || !_delivered || ![_pending[@"id"] isEqual:input[@"action"]] || ![_controlInput isEqual:input] || _controlInputResult) return;
        _controlInputResult = @{@"action": input[@"action"], @"accepted": @(accepted), @"menuOpened": @(_controlMenuOpened)};
    }
}
- (void)noteMenuForControlInput:(NSString *)action {
    @synchronized(self) {
        if (!_active || !_delivered || ![_pending[@"id"] isEqual:action] || ![_controlInput[@"action"] isEqual:action] ||
            ![_pending[@"operation"] isEqual:@"gridPress"] || ![_pending[@"value"][@"expectedCell"][@"role"] isEqual:@"popup"]) return;
        _controlMenuOpened = YES;
        // The verified native menu is already open. Mouse-down can keep
        // tracking until the user chooses or cancels, while 4D continues
        // polling. Acknowledge opening now, before that tracking call returns.
        _controlInputResult = @{@"action": action, @"accepted": @YES, @"menuOpened": @YES};
    }
}
- (BOOL)canPostEditorInput:(NSDictionary *)input {
    @synchronized(self) { return [self canPostEditorInput:input snapshot:_snapshot]; }
}
- (void)finishEditorInput:(NSDictionary *)input accepted:(BOOL)accepted {
    @synchronized(self) {
        if (!_active || !_delivered || ![_pending[@"id"] isEqual:input[@"action"]] || ![_lastInput isEqual:input] || _inputResult) return;
        _inputResult = @{@"action": input[@"action"], @"serial": input[@"serial"], @"accepted": @(accepted)};
    }
}
- (NSDictionary *)editorInputNode:(NSDictionary *)input {
    @synchronized(self) {
        if (![self canPostEditorInput:input snapshot:_snapshot]) return nil;
        for (NSDictionary *node in _snapshot[@"nodes"]) if ([node[@"id"] isEqual:_pending[@"node"]]) return node;
        return nil;
    }
}
- (BOOL)canPostEditorInput:(NSDictionary *)input snapshot:(NSDictionary *)snapshot {
    @synchronized(self) {
        if (!_active || !_delivered || ![_pending[@"id"] isEqual:input[@"action"]] ||
            ![@[@"setValue", @"replaceSelection", @"gridSetValue", @"gridReplaceSelection"] containsObject:_pending[@"operation"] ?: @""]) return NO;
        BOOL gridInput = [@[@"gridSetValue", @"gridReplaceSelection"] containsObject:_pending[@"operation"]];
        BOOL insertion = [input[@"mode"] isEqual:@"insert"];
        NSString *text = gridInput ? _pending[@"value"][@"text"] : _pending[@"value"];
        text = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
        NSUInteger position = [input[@"serial"] unsignedIntegerValue];
        if (![snapshot[@"enabled"] boolValue]) return NO;
        if (insertion) {
            // 4D's input-method client strips trailing line terminators. The
            // host sends the remaining Returns through its guarded key path.
            NSUInteger end = text.length;
            while (end && [text characterAtIndex:end - 1] == '\r') --end;
            text = [text substringToIndex:end];
            if (gridInput || position != 1 || ![text isEqual:input[@"text"]]) return NO;
        } else if (position < 1 || position > text.length || text.length - position + 1 < 2 ||
                   ![[text substringWithRange:NSMakeRange(position - 1, 2)] isEqual:input[@"text"]]) return NO;
        for (NSDictionary *node in snapshot[@"nodes"]) if ([node[@"id"] isEqual:_pending[@"node"]]) {
            if (gridInput) {
                NSDictionary *grid = node[@"grid"], *focus = grid[@"focused"], *target = _pending[@"value"];
                if (![node[@"enabled"] boolValue] || ![node[@"visible"] boolValue] || ![grid[@"actions"][@"edit"] boolValue] ||
                    ![grid[@"generation"] isEqual:target[@"generation"]] ||
                    ![focus[@"row"] isEqual:target[@"row"]] || ![focus[@"column"] isEqual:target[@"column"]] ||
                    !AXBGridRowAllowsEditing(grid, target[@"row"])) return NO;
                for (NSDictionary *column in grid[@"columns"]) if ([column[@"id"] isEqual:target[@"column"]])
                    return [column[@"enabled"] boolValue] && [column[@"editable"] boolValue];
                return NO;
            }
            if (insertion && ([node[@"protected"] boolValue] || ![node[@"selection"] isEqual:input[@"selection"]])) return NO;
            return [node[@"role"] isEqual:@"textfield"] && [node[@"focused"] boolValue] && [node[@"editable"] boolValue] && [node[@"enabled"] boolValue] && [node[@"visible"] boolValue];
        }
        return NO;
    }
}
- (NSDictionary *)exchange:(NSDictionary *)envelope now:(NSTimeInterval)now {
    NSString *error = AXBValidateEnvelope(envelope);
    if (error) return @{@"ok": @NO, @"error": error};
    // Defensive ownership: published state must not change behind its revision.
    if (![NSJSONSerialization isValidJSONObject:envelope]) return @{@"ok": @NO, @"error": @"payload is not JSON"};
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    if (!bytes) return @{@"ok": @NO, @"error": @"payload cannot be encoded as JSON"};
    // Large ordinary forms and long notes need the same window budget as grids.
    if (bytes.length > AXBLimits::payload) return @{@"ok": @NO, @"error": @"payload too large"};
    envelope = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
    @synchronized(self) {
        if (!_active) return @{@"ok": @NO, @"error": @"session closed"};
        NSDictionary *next = envelope[@"snapshot"];
        if (_snapshot) {
            NSComparisonResult order = [next[@"revision"] compare:_snapshot[@"revision"]];
            if (order == NSOrderedAscending || (order == NSOrderedSame && ![next isEqual:_snapshot]))
                return @{@"ok": @NO, @"error": @"snapshot revision must increase when state changes"};
        }
        for (NSDictionary *node in next[@"nodes"]) if (node[@"grid"]) {
            NSString *gridError = AXBValidateGridChange(_grids[node[@"id"]].descriptor, node[@"grid"]);
            if (gridError) return @{@"ok": @NO, @"error": gridError};
        }
        NSDictionary *receipt = envelope[@"receipt"];
        if (receipt && [receipt[@"id"] isEqual:_lastReceiptID] && ![receipt isEqual:_lastReceipt])
            return @{@"ok": @NO, @"error": @"receipt replay changed its result"};
        if (receipt && ![receipt[@"id"] isEqual:_lastReceiptID]) {
            if (!_delivered || ![receipt[@"id"] isEqual:_pending[@"id"]])
                return @{@"ok": @NO, @"error": @"receipt does not match delivered action"};
            _lastReceiptID = receipt[@"id"];
            _lastReceipt = receipt;
            _lastResult = receipt;
            _pending = nil;
            _pendingState = nil;
            _pendingGridValue = nil;
            _delivered = NO;
            _lastInput = nil;
            _inputResult = nil;
            _controlInput = nil; _controlInputState = nil; _controlInputResult = nil;
        }
        NSDictionary *input = envelope[@"editorInput"];
        if (input && ![self canPostEditorInput:input snapshot:next]) return @{@"ok": @NO, @"error": @"editor input does not match the active text action"};
        if (input && [input[@"serial"] integerValue] <= _lastInputSerial && ![input isEqual:_lastInput])
            return @{@"ok": @NO, @"error": @"editor input replay changed its contents"};
        NSDictionary *controlInput = envelope[@"controlInput"];
        BOOL gridInput = controlInput[@"point"] && _delivered && [_pending[@"id"] isEqual:controlInput[@"action"]] && [@[@"gridPress", @"gridHeaderPress"] containsObject:_pending[@"operation"] ?: @""];
        // A target can move or become unavailable between host confirmation
        // and this snapshot. Let the native dispatcher acknowledge that grid
        // input as rejected without disabling the entire accessibility session.
        if (controlInput && !gridInput && ![self controlInputNode:controlInput snapshot:next]) return @{@"ok": @NO, @"error": @"control input does not match the active control action"};
        if (controlInput && _controlInput && ![_controlInput isEqual:controlInput]) return @{@"ok": @NO, @"error": @"control input replay changed its contents"};
        _snapshot = next;
        NSMutableSet *seenGrids = [NSMutableSet new];
        for (NSDictionary *node in next[@"nodes"]) if (node[@"grid"]) {
            NSString *key = node[@"id"];
            [seenGrids addObject:key];
            AXBGrid *grid = _grids[key];
            if (grid && ![grid.descriptor[@"generation"] isEqual:node[@"grid"][@"generation"]]) {
                [grid invalidate]; grid = nil;
            }
            if (grid) [grid update:node[@"grid"]];
            else _grids[key] = [[AXBGrid alloc] initWithNode:key descriptor:node[@"grid"]];
        }
        for (NSString *key in [_grids.allKeys copy]) if (![seenGrids containsObject:key]) {
            [_grids[key] invalidate]; [_grids removeObjectForKey:key];
        }
        for (NSDictionary *page in envelope[@"gridPages"]) [_grids[page[@"node"]] acceptPage:page now:now];
        NSMutableDictionary *result = [@{@"ok": @YES} mutableCopy];
        NSMutableArray *requests = [NSMutableArray new];
        for (AXBGrid *grid in _grids.allValues) [requests addObjectsFromArray:[grid takeRequestsAtTime:now]];
        if (requests.count) result[@"gridRequests"] = requests;
        if (input) {
            if ([input[@"serial"] integerValue] > _lastInputSerial) {
                _lastInputSerial = [input[@"serial"] integerValue];
                _lastInput = input;
                _inputResult = nil;
                result[@"editorInput"] = input;
            }
        }
        if (controlInput && !_controlInput) {
            _controlInput = controlInput;
            _controlMenuOpened = NO;
            _controlInputState = ActionState(next, _pending);
            result[@"controlInput"] = controlInput;
        }
        if (_controlInputResult) result[@"controlInputResult"] = _controlInputResult;
        if (_inputResult) result[@"editorInputResult"] = _inputResult;
        if (_lastResult) result[@"result"] = _lastResult;
        if (_pending && !_delivered) {
            BOOL changedGridValue = _pendingGridValue && !SameGridDispatchValue(_pendingGridValue,
                [_grids[_pending[@"node"]] cellForRow:_pending[@"value"][@"row"] column:_pending[@"value"][@"column"] now:now], _pending);
            if (now - _queuedAt > 3.0 || changedGridValue || !SameDispatchState(_pendingState, ActionState(next, _pending), _pending[@"node"]) || ![next[@"enabled"] boolValue]) {
                _lastResult = @{@"id": _pending[@"id"], @"status": @"rejected", @"message": @"expired or changed before dispatch"};
                result[@"result"] = _lastResult;
                _pending = nil;
                _pendingState = nil;
                _pendingGridValue = nil;
            } else {
                // Dispatch against the state just checked by both the session
                // and host. Keep the original revision for diagnostics only.
                if (![_pending[@"revision"] isEqual:next[@"revision"]]) {
                    NSMutableDictionary *current = [_pending mutableCopy];
                    current[@"requestedRevision"] = _pending[@"revision"];
                    current[@"revision"] = next[@"revision"];
                    _pending = [current copy];
                }
                result[@"action"] = _pending;
                _delivered = YES;
                _pendingState = nil;
                _pendingGridValue = nil;
            }
        }
        result[@"busy"] = @(_pending != nil);
        return result;
    }
}
- (BOOL)enqueueNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value now:(NSTimeInterval)now {
    return [self enqueueNode:nodeID revision:revision operation:operation value:value observedSnapshot:nil now:now];
}
- (BOOL)enqueueNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value observedSnapshot:(NSDictionary *)observed now:(NSTimeInterval)now {
    @synchronized(self) {
        if (!_active || _pending || ![_snapshot[@"enabled"] boolValue]) return NO;
        if (![revision isEqual:_snapshot[@"revision"]]) {
            NSDictionary *request = @{@"node": nodeID, @"operation": operation};
            if (!observed || ![observed[@"revision"] isEqual:revision] || [revision compare:_snapshot[@"revision"]] != NSOrderedAscending ||
                !SameDispatchState(ActionState(observed, request), ActionState(_snapshot, request), nodeID)) return NO;
        }
        NSDictionary *node = nil;
        for (NSDictionary *candidate in _snapshot[@"nodes"]) if ([candidate[@"id"] isEqual:nodeID]) { node = candidate; break; }
        if (!node || (![node[@"enabled"] boolValue] && ![operation isEqual:@"reveal"]) || ![node[@"visible"] boolValue]) return NO;
        NSString *role = node[@"role"];
        NSDictionary *gridValue = nil;
        if ([operation isEqual:@"press"]) {
            if (![@[@"button", @"checkbox", @"radio", @"popup"] containsObject:role]) return NO;
        } else if ([@[@"showMenu", @"confirm", @"dismissMenu"] containsObject:operation]) {
            if (![node[@"combo"] boolValue]) return NO;
        } else if ([@[@"increment", @"decrement"] containsObject:operation]) {
            if (![@[@"slider", @"stepper"] containsObject:role] || ![node[@"adjustable"] boolValue] || value) return NO;
        } else if ([operation isEqual:@"reveal"]) {
            if (![node[@"revealable"] boolValue] || value) return NO;
        } else if ([operation isEqual:@"focus"]) {
            if (![node[@"focusable"] boolValue] || !Bool(value) || ![value boolValue]) return NO;
        } else if ([operation isEqual:@"setValue"] || [operation isEqual:@"replaceSelection"]) {
            if (![role isEqual:@"textfield"] || !Text(value, AXBLimits::text) || (node[@"editable"] && ![node[@"editable"] boolValue])) return NO;
            if ([operation isEqual:@"replaceSelection"] && (!node[@"selection"] || [node[@"protected"] boolValue])) return NO;
        } else if ([operation isEqual:@"setSelection"]) {
            if (![role isEqual:@"textfield"] || ![node[@"editable"] boolValue] || [node[@"protected"] boolValue] || ![value isKindOfClass:NSArray.class] || [value count] != 2) return NO;
            for (id part in value) if (!Number(part) || [part doubleValue] < 0 || floor([part doubleValue]) != [part doubleValue]) return NO;
            if ([value[0] doubleValue] + [value[1] doubleValue] > [node[@"value"] length]) return NO;
            if (!AXBTextRangeValid(node[@"value"], NSMakeRange([value[0] unsignedIntegerValue], [value[1] unsignedIntegerValue]))) return NO;
        } else if ([@[@"gridHeaderPress", @"gridHeaderReveal"] containsObject:operation]) {
            AXBGrid *grid = _grids[nodeID];
            if (![role isEqual:@"table"] || ![value isKindOfClass:NSDictionary.class] || !Text(value[@"column"], 256) ||
                [grid indexOfColumn:value[@"column"]] == NSNotFound) return NO;
            NSDictionary *header = grid.descriptor[@"columns"][[grid indexOfColumn:value[@"column"]]][@"header"];
            if (![header[@"visible"] boolValue] ||
                ([operation isEqual:@"gridHeaderPress"] && (![header[@"enabled"] boolValue] || ![header[@"press"] boolValue]))) return NO;
            value = @{@"column": value[@"column"], @"generation": grid.descriptor[@"generation"], @"expectedHeader": header};
        } else if ([operation isEqual:@"gridSelect"]) {
            AXBGrid *grid = _grids[nodeID];
            if (![role isEqual:@"table"] || ![grid.descriptor[@"actions"][@"select"] boolValue] || ![value isKindOfClass:NSArray.class] || [value count] > [grid.descriptor[@"rows"] count]) return NO;
            NSMutableSet *selected = [NSMutableSet new];
            for (id key in value) {
                if (!Text(key, 256) || [selected containsObject:key] || [grid indexOfRow:key] == NSNotFound ||
                    (![grid.descriptor[@"selected"] containsObject:key] && !AXBGridRowAllowsSelection(grid.descriptor, key))) return NO;
                [selected addObject:key];
            }
        } else if ([@[@"gridReveal", @"gridEdit", @"gridPress", @"gridSetValue", @"gridSetSelection", @"gridReplaceSelection"] containsObject:operation]) {
            AXBGrid *grid = _grids[nodeID];
            BOOL edit = ![operation isEqual:@"gridReveal"];
            if (![role isEqual:@"table"] || ![grid.descriptor[@"actions"][edit ? @"edit" : @"reveal"] boolValue] || ![value isKindOfClass:NSDictionary.class] ||
                !Text(value[@"row"], 256) || !Text(value[@"column"], 256) || [grid indexOfRow:value[@"row"]] == NSNotFound || [grid indexOfColumn:value[@"column"]] == NSNotFound) return NO;
            NSMutableDictionary *target = [value mutableCopy]; target[@"generation"] = grid.descriptor[@"generation"]; value = target;
            if (edit) {
                if (!AXBGridRowAllowsEditing(grid.descriptor, value[@"row"])) return NO;
                NSDictionary *column = grid.descriptor[@"columns"][[grid indexOfColumn:value[@"column"]]];
                gridValue = [grid cellForRow:value[@"row"] column:value[@"column"] now:now];
                if (![column[@"editable"] boolValue] || ![column[@"enabled"] boolValue] || ![gridValue[@"editable"] boolValue] || ![gridValue[@"enabled"] boolValue]) return NO;
                BOOL widget = [@[@"checkbox", @"popup"] containsObject:gridValue[@"role"] ?: @""];
                if ([operation isEqual:@"gridPress"] && !widget) return NO;
                if (widget && ![@[@"gridPress", @"gridEdit"] containsObject:operation]) return NO;
                if (widget) {
                    target[@"expectedCell"] = gridValue;
                    // Non-text controls have focus without a text selection.
                    // The host rechecks the exact native cell before activation.
                }
                NSDictionary *focus = grid.descriptor[@"focused"];
                BOOL focused = !widget && [focus[@"row"] isEqual:value[@"row"]] && [focus[@"column"] isEqual:value[@"column"]] && focus[@"value"];
                if (focused && !focus[@"selection"]) return NO;
                if ([operation isEqual:@"gridSetValue"] || [operation isEqual:@"gridReplaceSelection"]) {
                    if (!Text(value[@"text"], AXBLimits::text)) return NO;
                    // The provider must compare this to its live rendered value
                    // before entering the real editor, then use normal editing.
                    target[@"expectedValue"] = focused ? focus[@"value"] : gridValue[@"value"];
                }
                if ([@[@"gridSetSelection", @"gridReplaceSelection"] containsObject:operation]) {
                    if (!focused || !focus[@"selection"]) return NO;
                    if ([operation isEqual:@"gridSetSelection"]) {
                        id range = value[@"selection"];
                        if (![range isKindOfClass:NSArray.class] || [range count] != 2) return NO;
                        for (id part in range) if (!Number(part) || [part doubleValue] < 0 || floor([part doubleValue]) != [part doubleValue]) return NO;
                        if ([range[0] doubleValue] + [range[1] doubleValue] > [focus[@"value"] length] ||
                            !AXBTextRangeValid(focus[@"value"], NSMakeRange([range[0] unsignedIntegerValue], [range[1] unsignedIntegerValue]))) return NO;
                    }
                }
                if (focused) {
                    target[@"expectedEditor"] = focus;
                    target[@"expectedValue"] = focus[@"value"];
                }
            }
        } else if ([operation isEqual:@"selectRows"]) {
            if (![role isEqual:@"table"] || ![value isKindOfClass:NSArray.class] || [value count] > 100) return NO;
            NSMutableSet *selected = [NSMutableSet new];
            for (id rowID in value) {
                if (!Text(rowID, 128) || [selected containsObject:rowID]) return NO;
                [selected addObject:rowID];
                BOOL valid = NO;
                for (NSDictionary *row in _snapshot[@"nodes"]) if ([row[@"id"] isEqual:rowID] && [row[@"parent"] isEqual:nodeID] &&
                    [row[@"role"] isEqual:@"row"] && [row[@"visible"] boolValue] && [row[@"enabled"] boolValue]) { valid = YES; break; }
                if (!valid) return NO;
            }
        } else return NO;
        NSMutableDictionary *action = [@{@"id": NSUUID.UUID.UUIDString, @"session": _identifier,
            @"node": nodeID, @"revision": _snapshot[@"revision"], @"operation": operation} mutableCopy];
        if (![revision isEqual:_snapshot[@"revision"]]) action[@"requestedRevision"] = revision;
        if (value) action[@"value"] = value;
        if (![NSJSONSerialization isValidJSONObject:action]) return NO;
        NSData *actionBytes = [NSJSONSerialization dataWithJSONObject:action options:0 error:nil];
        if (!actionBytes || actionBytes.length > AXBLimits::payload) return NO;
        _pending = [NSJSONSerialization JSONObjectWithData:actionBytes options:0 error:nil];
        _pendingState = ActionState(_snapshot, _pending);
        _pendingGridValue = gridValue;
        _lastInputSerial = 0;
        _lastInput = nil;
        _inputResult = nil;
        _queuedAt = now;
        _delivered = NO;
        return YES;
    }
}
@end
