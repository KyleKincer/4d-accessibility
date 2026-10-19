#import "Session.h"
#import "Grid.h"
#include "Limits.h"
#import "Identifiers.h"
#include <cmath>
#include <vector>

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
    return @{@"label": snapshot[@"label"], @"enabled": snapshot[@"enabled"], @"automationKey": snapshot[@"automationKey"] ?: NSNull.null,
        @"focused": focused, @"nodes": dependencies, @"rows": rows};
}

// What a client acted on: its target, with the target's ancestors and labels, and the window,
// apart from focus and selection. An action waiting behind another runs only if these are unchanged
// once that one completes, as a click made meanwhile would land on the same control.
static NSDictionary *TargetState(NSDictionary *snapshot, NSDictionary *action) {
    NSDictionary *state = ActionState(snapshot, action);
    if (!state) return nil;
    NSMutableDictionary *nodes = [NSMutableDictionary new];
    for (NSString *key in state[@"nodes"]) {
        NSMutableDictionary *node = [state[@"nodes"][key] mutableCopy];
        [node removeObjectForKey:@"focused"];
        [node removeObjectForKey:@"selection"];
        nodes[key] = node;
    }
    return @{@"label": state[@"label"], @"enabled": state[@"enabled"], @"automationKey": state[@"automationKey"], @"nodes": nodes, @"rows": state[@"rows"]};
}

// A newly activated 4D form can assign initial focus after the action was
// queued. Accept only focus arriving on that exact target with every other
// dependency unchanged. A text field gains its editor's selection with focus;
// otherwise values, selections and prior focus in another control remain
// strict guards. Never use this after dispatch.
static BOOL SameDispatchState(NSDictionary *before, NSDictionary *after, NSString *target) {
    if ([before isEqual:after]) return YES;
    if (!before || !after || [before[@"focused"] count] != 0 ||
        ![after[@"focused"] isEqual:@[target]]) return NO;
    NSDictionary *oldNode = before[@"nodes"][target], *newNode = after[@"nodes"][target];
    if (!oldNode || !newNode || [oldNode[@"focused"] boolValue] || ![newNode[@"focused"] boolValue]) return NO;
    NSMutableDictionary *normalizedNode = [newNode mutableCopy];
    if (oldNode[@"focused"]) normalizedNode[@"focused"] = oldNode[@"focused"];
    else [normalizedNode removeObjectForKey:@"focused"];
    if (!oldNode[@"selection"]) [normalizedNode removeObjectForKey:@"selection"];
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

NSString *AXBValidateEnvelopeParts(NSDictionary *envelope, NSDictionary *byID);

NSString *AXBRepairUnicode(NSString *text) {
    NSUInteger length = text.length;
    std::vector<unichar> units(length);
    [text getCharacters:units.data() range:NSMakeRange(0, length)];
    BOOL changed = NO;
    for (NSUInteger i = 0; i < length; i++) {
        if (CFStringIsSurrogateHighCharacter(units[i]) && i + 1 < length && CFStringIsSurrogateLowCharacter(units[i + 1])) { i++; continue; }
        if (CFStringIsSurrogateHighCharacter(units[i]) || CFStringIsSurrogateLowCharacter(units[i])) { units[i] = 0xFFFD; changed = YES; }
    }
    return changed ? [NSString stringWithCharacters:units.data() length:length] : text;
}
static id RepairText(id value, NSUInteger limit, NSUInteger *repairs) {
    if (![value isKindOfClass:NSString.class]) return value;
    NSString *text = Text(value, NSUIntegerMax) ? value : AXBRepairUnicode(value);
    if (text.length > limit) {
        NSUInteger end = limit - 1;
        if (end && CFStringIsSurrogateHighCharacter([text characterAtIndex:end - 1])) end--;
        text = [[text substringToIndex:end] stringByAppendingString:@"\u2026"];
    }
    if (text != value) (*repairs)++;
    return text;
}
static NSDictionary *RepairNode(id raw, NSUInteger *repairs) {
    if (![raw isKindOfClass:NSDictionary.class]) return raw;
    NSDictionary *node = raw;
    NSMutableDictionary *n = nil;
    NSUInteger before = *repairs;
    auto set = [&](NSString *key, id value) { if (value == node[key]) return; if (!n) n = [node mutableCopy]; n[key] = value; };
    for (NSString *key in @[@"label", @"placeholder"]) if (node[key]) set(key, RepairText(node[key], 512, repairs));
    if (node[@"valueDescription"]) set(@"valueDescription", RepairText(node[@"valueDescription"], AXBLimits::text, repairs));
    NSString *value = node[@"value"];
    if ([value isKindOfClass:NSString.class] && ![node[@"role"] isEqual:@"stepper"]) {
        NSString *repaired = RepairText(value, AXBLimits::text, repairs);
        if (repaired != value) {
            set(@"value", repaired);
            [n removeObjectForKey:@"selection"];
            // A client that wrote a shortened value back would delete the rest.
            if (repaired.length != value.length && node[@"editable"]) n[@"editable"] = @NO;
        }
    }
    NSArray *choices = node[@"choices"];
    if ([choices isKindOfClass:NSArray.class]) {
        NSMutableArray *next = [NSMutableArray arrayWithCapacity:choices.count];
        for (id choice in choices) [next addObject:RepairText(choice, 512, repairs)];
        if (*repairs != before) set(@"choices", next);
    }
    NSDictionary *table = node[@"table"];
    if ([table isKindOfClass:NSDictionary.class] && [table[@"columns"] isKindOfClass:NSArray.class]) {
        NSUInteger at = *repairs;
        NSMutableArray *columns = [NSMutableArray new];
        for (id column in table[@"columns"]) {
            if ([column isKindOfClass:NSDictionary.class] && column[@"header"]) {
                id header = RepairText(column[@"header"], 512, repairs);
                if (header != column[@"header"]) { NSMutableDictionary *copy = [column mutableCopy]; copy[@"header"] = header; [columns addObject:copy]; continue; }
            }
            [columns addObject:column];
        }
        if (*repairs != at) { NSMutableDictionary *copy = [table mutableCopy]; copy[@"columns"] = columns; set(@"table", copy); }
    }
    return n ?: node;
}
static BOOL LocatorReady(NSDictionary *node) {
    if (![node[@"id"] isKindOfClass:NSString.class]) return NO;
    NSArray *path = node[@"automationPath"];
    if (!path) return YES;
    if (![path isKindOfClass:NSArray.class] || !path.count) return NO;
    for (id segment in path) if (![segment isKindOfClass:NSString.class]) return NO;
    return YES;
}
static NSArray *RepairStructure(NSDictionary *snapshot, NSArray *nodes, NSUInteger *repairs) {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:MIN(nodes.count, AXBLimits::nodes)];
    NSMutableSet *ids = [NSMutableSet new], *locators = [NSMutableSet new];
    BOOL dropped = NO;
    for (id raw in nodes) {
        if (kept.count >= AXBLimits::nodes) { (*repairs)++; dropped = YES; continue; }
        if (![raw isKindOfClass:NSDictionary.class] || !LocatorReady(raw)) { [kept addObject:raw]; continue; }
        NSDictionary *node = raw;
        if ([ids containsObject:node[@"id"]]) { (*repairs)++; dropped = YES; continue; }
        [ids addObject:node[@"id"]];
        if ([locators containsObject:AXBNodeIdentifier(snapshot, node)]) {
            NSArray *base = node[@"automationPath"] ?: @[node[@"id"]];
            for (NSUInteger copy = 2;; copy++) {
                NSMutableArray *path = [base mutableCopy];
                path[path.count - 1] = [NSString stringWithFormat:@"%@~%lu", base.lastObject, (unsigned long)copy];
                NSMutableDictionary *renamed = [node mutableCopy];
                renamed[@"automationPath"] = path;
                if ([locators containsObject:AXBNodeIdentifier(snapshot, renamed)]) continue;
                node = renamed;
                break;
            }
            (*repairs)++;
        }
        [locators addObject:AXBNodeIdentifier(snapshot, node)];
        [kept addObject:node];
    }
    if (!dropped) return kept;
    // Leave out controls whose parent was left out, and references to controls that were.
    for (BOOL again = YES; again;) {
        again = NO;
        NSMutableSet *present = [NSMutableSet new];
        for (NSDictionary *node in kept) if ([node isKindOfClass:NSDictionary.class] && node[@"id"]) [present addObject:node[@"id"]];
        for (NSInteger i = (NSInteger)kept.count - 1; i >= 0; i--) {
            NSDictionary *node = kept[i];
            if (![node isKindOfClass:NSDictionary.class]) continue;
            if ([node[@"parent"] isKindOfClass:NSString.class] && ![present containsObject:node[@"parent"]]) { [kept removeObjectAtIndex:i]; (*repairs)++; again = YES; continue; }
            NSMutableDictionary *copy = nil;
            if ([node[@"labelledBy"] isKindOfClass:NSString.class] && ![present containsObject:node[@"labelledBy"]]) { copy = [node mutableCopy]; [copy removeObjectForKey:@"labelledBy"]; }
            if ([node[@"linked"] isKindOfClass:NSArray.class]) {
                NSArray *linked = [node[@"linked"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings) { (void)bindings; return [present containsObject:item]; }]];
                if (linked.count != [node[@"linked"] count]) { if (!copy) copy = [node mutableCopy]; copy[@"linked"] = linked; }
            }
            if (copy) kept[i] = copy;
        }
    }
    return kept;
}
NSDictionary *AXBRepairEnvelope(id envelope, NSUInteger *repairs) {
    *repairs = 0;
    if (![envelope isKindOfClass:NSDictionary.class] || ![envelope[@"snapshot"] isKindOfClass:NSDictionary.class]) return envelope;
    NSDictionary *snapshot = envelope[@"snapshot"];
    NSMutableDictionary *next = [snapshot mutableCopy];
    if (snapshot[@"label"]) next[@"label"] = RepairText(snapshot[@"label"], 512, repairs);
    for (NSString *key in @[@"nodes", @"changed"]) {
        NSArray *nodes = snapshot[key];
        if (![nodes isKindOfClass:NSArray.class]) continue;
        NSMutableArray *repaired = [NSMutableArray arrayWithCapacity:nodes.count];
        for (id node in nodes) [repaired addObject:RepairNode(node, repairs)];
        next[key] = [key isEqual:@"nodes"] ? RepairStructure(snapshot, repaired, repairs) : repaired;
    }
    if (!*repairs) return envelope;
    NSMutableDictionary *result = [envelope mutableCopy];
    result[@"snapshot"] = [next copy];
    return [result copy];
}

NSString *AXBValidateEnvelope(NSDictionary *envelope) {
    if (![envelope isKindOfClass:NSDictionary.class]) return @"envelope must be an object";
    NSDictionary *s = envelope[@"snapshot"];
    if (![s isKindOfClass:NSDictionary.class]) return @"snapshot must be an object";
    if (!Number(s[@"version"]) || [s[@"version"] integerValue] != 1 || [s[@"version"] doubleValue] != 1) return @"unsupported protocol version";
    double revision = [s[@"revision"] respondsToSelector:@selector(doubleValue)] ? [s[@"revision"] doubleValue] : 0;
    if (!Number(s[@"revision"]) || revision < 1 || revision > 9007199254740991.0 || floor(revision) != revision) return @"invalid revision";
    if (!Text(s[@"label"], 512) || !Bool(s[@"enabled"])) return @"invalid window metadata";
    if (s[@"automationKey"] && (!Text(s[@"automationKey"], 128) || ![s[@"automationKey"] length])) return @"invalid automation key";
    if (s[@"omitOutsideWindow"] && !Bool(s[@"omitOutsideWindow"])) return @"invalid window metadata";
    if (s[@"idleRefresh"] && (!Number(s[@"idleRefresh"]) || [s[@"idleRefresh"] doubleValue] < 1 || [s[@"idleRefresh"] doubleValue] > 60))
        return @"invalid idle refresh interval";
    NSArray *nodes = s[@"nodes"];
    if (![nodes isKindOfClass:NSArray.class] || nodes.count > AXBLimits::nodes) return @"invalid node count";
    NSMutableSet *ids = [NSMutableSet new];
    NSMutableSet *locators = [NSMutableSet new];
    NSMutableDictionary *byID = [NSMutableDictionary new];
    NSSet *roles = [NSSet setWithArray:@[@"button", @"checkbox", @"radio", @"popup", @"textfield", @"text", @"table", @"row", @"cell", @"group", @"image", @"progress", @"slider", @"stepper", @"tabgroup", @"tab", @"splitter", @"drawnTable"]];
    for (id raw in nodes) {
        if (![raw isKindOfClass:NSDictionary.class]) return @"invalid node";
        NSDictionary *n = raw;
        NSString *identifier = n[@"id"];
        if (!Text(identifier, 128) || !identifier.length || [ids containsObject:identifier]) return @"invalid or duplicate node identifier";
        [ids addObject:identifier];
        byID[identifier] = n;
        if (n[@"automationPath"]) {
            NSArray *path = n[@"automationPath"];
            if (![path isKindOfClass:NSArray.class] || !path.count || path.count > 16) return @"invalid automation path";
            for (id segment in path) if (!Text(segment, 256) || ![segment length]) return @"invalid automation path segment";
        }
        NSString *locator = AXBNodeIdentifier(s, n);
        if ([locators containsObject:locator]) return [@"duplicate automation path: " stringByAppendingString:locator];
        [locators addObject:locator];
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
        } else if ([n[@"role"] isEqual:@"drawnTable"]) {
            // A list box no grid adapter describes: the plugin reads the rows 4D draws, guided
            // by its columns' titles, widths and visibility.
            NSDictionary *table = n[@"table"];
            if (![table isKindOfClass:NSDictionary.class] || !Number(table[@"headerHeight"]) || !Bool(table[@"showHeaders"])) return @"invalid drawn table";
            NSArray *columns = table[@"columns"];
            if (![columns isKindOfClass:NSArray.class] || columns.count > 256) return @"invalid drawn table columns";
            for (NSDictionary *column in columns)
                if (![column isKindOfClass:NSDictionary.class] || !Text(column[@"header"], 512) || !Number(column[@"width"]) || !Bool(column[@"hidden"])) return @"invalid drawn table column";
        } else if ([n[@"role"] isEqual:@"splitter"]) {
            // The host moves a splitter through 4D's own splitter handling by one step.
            if (!Bool(n[@"adjustable"]) || !Number(n[@"step"]) || [n[@"step"] doubleValue] <= 0 || !Bool(n[@"vertical"]) ||
                n[@"adjustment"] || !Number(n[@"value"]) || !Number(n[@"min"]) || !Number(n[@"max"]) ||
                [n[@"min"] doubleValue] > [n[@"max"] doubleValue]) return @"invalid splitter";
        } else if ([n[@"role"] isEqual:@"progress"]) {
            if (n[@"vertical"] && !Bool(n[@"vertical"])) return @"invalid progress orientation";
            if (!Bool(n[@"indeterminate"])) return @"invalid progress mode";
            if ([n[@"indeterminate"] boolValue]) {
                if (n[@"value"] != NSNull.null) return @"indeterminate progress must omit its value";
            } else if (!Number(n[@"value"]) || !Number(n[@"min"]) || !Number(n[@"max"]) ||
                [n[@"min"] doubleValue] > [n[@"max"] doubleValue]) return @"invalid progress range";
        } else if ([n[@"role"] isEqual:@"checkbox"]) {
            if (!Bool(n[@"value"]) && !(Number(n[@"value"]) && [n[@"value"] doubleValue] == 2)) return @"invalid checkbox state";
        } else if ([@[@"radio", @"tab"] containsObject:n[@"role"]] ? !Bool(n[@"value"]) : !Text(n[@"value"], AXBLimits::text)) return @"invalid node value";
        if (n[@"valueDescription"] && !Text(n[@"valueDescription"], AXBLimits::text)) return @"invalid value description";
        if (n[@"choices"] || n[@"choice"]) {
            // A picture popup menu's labeled cells, and the chosen one or 0.
            NSArray *choices = n[@"choices"];
            if (![n[@"role"] isEqual:@"popup"] || ![choices isKindOfClass:NSArray.class] || !choices.count || choices.count > 256 ||
                !Number(n[@"choice"]) || [n[@"choice"] doubleValue] < 0 || [n[@"choice"] doubleValue] > choices.count ||
                floor([n[@"choice"] doubleValue]) != [n[@"choice"] doubleValue]) return @"invalid choices";
            for (id choice in choices) if (!Text(choice, 512) || ![choice length]) return @"invalid choices";
        }
        // A button's own pop-up menu: opened by any click on a linked button, or on a separated one's arrow.
        if (n[@"menu"] && (![n[@"role"] isEqual:@"button"] || ![@[@"linked", @"separated"] containsObject:n[@"menu"]])) return @"invalid button menu";
        if (n[@"pictureActions"]) {
            // An editable picture's standard edit actions.
            NSArray *actions = n[@"pictureActions"];
            if (![n[@"role"] isEqual:@"image"] || ![actions isKindOfClass:NSArray.class] || !actions.count || actions.count > 4 ||
                [NSSet setWithArray:actions].count != actions.count) return @"invalid picture actions";
            for (id action in actions) if (![@[@"cut", @"copy", @"paste", @"clear"] containsObject:action]) return @"invalid picture actions";
        }
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
    NSMutableSet *selectedTabGroups = [NSMutableSet new];
    for (NSDictionary *n in nodes) {
        NSString *role = n[@"role"];
        NSString *expected = [role isEqual:@"row"] ? @"table" : [role isEqual:@"cell"] ? @"row" : [role isEqual:@"tab"] ? @"tabgroup" : nil;
        if (expected && (!n[@"parent"] || ![byID[n[@"parent"]][@"role"] isEqual:expected])) return @"invalid table hierarchy";
        if ([role isEqual:@"tab"] && [n[@"value"] boolValue]) {
            if ([selectedTabGroups containsObject:n[@"parent"]]) return @"multiple selected tabs";
            [selectedTabGroups addObject:n[@"parent"]];
        }
        if (n[@"parent"] && byID[n[@"parent"]][@"grid"]) return @"logical grid cannot mix explicit summary rows";
        if (!expected && n[@"parent"] && ![byID[n[@"parent"]][@"role"] isEqual:@"group"]) return @"invalid group parent";
        NSMutableSet *ancestors = [NSMutableSet new];
        for (NSDictionary *ancestor = n; ancestor; ancestor = byID[ancestor[@"parent"]]) {
            if ([ancestors containsObject:ancestor[@"id"]] || ancestors.count >= 32) return @"invalid control ancestry";
            [ancestors addObject:ancestor[@"id"]];
            if (ancestor[@"parent"] && !byID[ancestor[@"parent"]]) return @"missing control parent";
        }
        if (n[@"labelledBy"] && (![byID[n[@"labelledBy"]][@"role"] isEqual:@"text"] || [n[@"id"] isEqual:n[@"labelledBy"]])) return @"invalid label relationship";
        if (n[@"linked"]) {
            if (![n[@"linked"] isKindOfClass:NSArray.class] || [n[@"linked"] count] > nodes.count) return @"invalid linked controls";
            NSMutableSet *linked = [NSMutableSet new];
            for (id identifier in n[@"linked"]) {
                if (!Text(identifier, 128) || !byID[identifier] || [identifier isEqual:n[@"id"]] || [linked containsObject:identifier]) return @"invalid linked controls";
                [linked addObject:identifier];
            }
        }
    }
    return AXBValidateEnvelopeParts(envelope, byID);
}

BOOL AXBEnvelopeIsBrief(id envelope) {
    NSDictionary *brief = [envelope isKindOfClass:NSDictionary.class] ? envelope[@"snapshot"] : nil;
    return [brief isKindOfClass:NSDictionary.class] && ([brief[@"unchanged"] isEqual:@YES] || brief[@"base"] != nil);
}

NSDictionary *AXBExpandEnvelope(NSDictionary *envelope, NSDictionary *known, NSString **error) {
    NSDictionary *brief = envelope[@"snapshot"];
    NSMutableDictionary *expanded = [envelope mutableCopy];
    if ([brief[@"unchanged"] isEqual:@YES]) {
        if (!known || brief.count != 3 || ![brief[@"version"] isEqual:@1] || ![brief[@"revision"] isEqual:known[@"revision"]]) {
            *error = @"unchanged snapshot does not match the session's";
            return nil;
        }
        NSMutableDictionary *byID = [NSMutableDictionary new];
        if (envelope[@"gridPages"]) for (NSDictionary *node in known[@"nodes"]) byID[node[@"id"]] = node;
        expanded[@"snapshot"] = known;
        *error = AXBValidateEnvelopeParts(expanded, byID);
        return *error ? nil : [expanded copy];
    }
    NSArray *changed = brief[@"changed"], *nodes = known[@"nodes"];
    if (!known || brief[@"unchanged"] || brief[@"nodes"] || ![brief[@"base"] isEqual:known[@"revision"]] ||
        ![changed isKindOfClass:NSArray.class] || changed.count > nodes.count) {
        *error = @"changed nodes do not match the session's snapshot";
        return nil;
    }
    NSMutableDictionary<NSString *, NSNumber *> *positions = [NSMutableDictionary dictionaryWithCapacity:nodes.count];
    for (NSUInteger i = 0; i < nodes.count; i++) positions[nodes[i][@"id"]] = @(i);
    NSMutableArray *next = [nodes mutableCopy];
    NSMutableSet *replaced = [NSMutableSet new];
    for (id node in changed) {
        id identifier = [node isKindOfClass:NSDictionary.class] ? node[@"id"] : nil;
        NSNumber *position = [identifier isKindOfClass:NSString.class] ? positions[identifier] : nil;
        if (!position || [replaced containsObject:identifier]) {
            *error = @"a changed node is not in the session's snapshot";
            return nil;
        }
        [replaced addObject:identifier];
        next[position.unsignedIntegerValue] = node;
    }
    NSMutableDictionary *snapshot = [brief mutableCopy];
    [snapshot removeObjectForKey:@"base"];
    [snapshot removeObjectForKey:@"changed"];
    snapshot[@"nodes"] = [next copy];
    expanded[@"snapshot"] = [snapshot copy];
    *error = AXBValidateEnvelope(expanded);
    return *error ? nil : [expanded copy];
}

NSString *AXBValidateEnvelopeParts(NSDictionary *envelope, NSDictionary *byID) {
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
        id serial = controlInput[@"serial"];
        if (serial && (!point || !Number(serial) || [serial doubleValue] < 1 || [serial doubleValue] > 10000 || floor([serial doubleValue]) != [serial doubleValue])) return @"invalid control input serial";
        id choice = controlInput[@"choice"];
        if (choice && (!point || serial || !Number(choice) || [choice doubleValue] < 1 || [choice doubleValue] > 256 || floor([choice doubleValue]) != [choice doubleValue])) return @"invalid control input choice";
        if (controlInput.count != (point ? 2 : 1) + (serial ? 1 : 0) + (choice ? 1 : 0)) return @"invalid control input";
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
    NSString *_pendingSelectionGeneration;
    NSDictionary *_pendingGridValue;
    BOOL _delivered;
    NSTimeInterval _queuedAt;
    NSTimeInterval _lastExchangeAt;
    NSTimeInterval _exchangeInterval;
    NSTimeInterval _queuedInterval;
    // Requests made while another action is under way, oldest first: each its node, operation,
    // value, request time and TargetState.
    NSMutableArray<NSDictionary *> *_waiting;
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
    BOOL _claimed;
    uint64_t _claimedSignificant, _claimedMinor;
    NSTimeInterval _claimedAt;
}
- (instancetype)initWithIdentifier:(NSString *)identifier windowID:(NSInteger)windowID {
    if ((self = [super init])) { _identifier = [identifier copy]; _windowID = windowID; _active = YES; _grids = [NSMutableDictionary new]; _waiting = [NSMutableArray new]; }
    return self;
}
- (NSString *)identifier { return _identifier; }
- (NSInteger)windowID { return _windowID; }
- (NSDictionary *)snapshot { @synchronized(self) { return _snapshot; } }
- (BOOL)active { @synchronized(self) { return _active; } }
- (NSDictionary *)activity {
    @synchronized(self) {
        NSMutableDictionary *result = [@{@"busy": @(_pending != nil), @"delivered": @(_delivered)} mutableCopy];
        if (_pending) {
            result[@"id"] = _pending[@"id"];
            result[@"operation"] = _pending[@"operation"];
            result[@"node"] = _pending[@"node"];
            if ([_pending[@"value"] isKindOfClass:NSDictionary.class])
                for (NSString *key in @[@"row", @"column"])
                    if (_pending[@"value"][key]) result[key] = _pending[@"value"][key];
        }
        if (_lastResult) result[@"result"] = _lastResult;
        return [result copy];
    }
}
- (AXBGrid *)gridForNode:(NSString *)nodeID { @synchronized(self) { return _grids[nodeID]; } }
- (BOOL)claimRefreshWithSignificant:(uint64_t)significant minor:(uint64_t)minor changedAt:(NSTimeInterval)changedAt
                         settleUntil:(NSTimeInterval)settleUntil drawingObserved:(BOOL)drawingObserved now:(NSTimeInterval)now {
    @synchronized(self) {
        if (!_active) return NO;
        NSTimeInterval since = now - _claimedAt;
        id interval = _snapshot[@"idleRefresh"];
        // Observed drawing, with its layers' visibility and geometry, reports nearly every change a
        // form shows; without it, an unchanged form is checked more often.
        NSTimeInterval idle = interval ? [interval doubleValue] : drawingObserved ? 30 : 5;
        BOOL changed = significant != _claimedSignificant && (now - changedAt >= 0.25 || since >= 1);
        BOOL settled = _claimedAt < settleUntil && now >= settleUntil;
        BOOL due = !_claimed || !_snapshot || _pending || changed || settled || since >= idle ||
            (!drawingObserved && minor != _claimedMinor && since >= 1);
        if (!due) for (AXBGrid *grid in _grids.allValues) if (grid.hasQueuedRequests) { due = YES; break; }
        if (!due) return NO;
        // The backstop checks every object again, catching anything no signal reported.
        if (_claimed && since >= idle) self.verificationDue = YES;
        _claimed = YES; _claimedSignificant = significant; _claimedMinor = minor; _claimedAt = now;
        return YES;
    }
}
- (void)invalidate {
    @synchronized(self) {
        _active = NO; [_waiting removeAllObjects]; _pending = nil; _pendingState = nil; _pendingGridValue = nil; _pendingSelectionGeneration = nil; _delivered = NO; _snapshot = nil; _lastInput = nil; _inputResult = nil; _controlInput = nil; _controlInputState = nil; _controlInputResult = nil;
        for (AXBGrid *grid in _grids.allValues) [grid invalidate];
        [_grids removeAllObjects];
    }
}
- (NSDictionary *)controlInputNode:(NSDictionary *)input snapshot:(NSDictionary *)snapshot {
    if (!_active || !_delivered || ![_pending[@"id"] isEqual:input[@"action"]] ||
        ![snapshot[@"enabled"] boolValue]) return nil;
    for (NSDictionary *node in snapshot[@"nodes"]) if ([node[@"id"] isEqual:_pending[@"node"]]) {
        if (![node[@"enabled"] boolValue] || ![node[@"visible"] boolValue]) return nil;
        BOOL choose = [_pending[@"operation"] isEqual:@"choose"] && node[@"choices"] && [input[@"choice"] isEqual:_pending[@"value"]];
        BOOL menu = [_pending[@"operation"] isEqual:@"showMenu"] && node[@"menu"];
        if (([_pending[@"operation"] isEqual:@"press"] && [@[@"button", @"tab"] containsObject:node[@"role"]]) || choose || menu) {
            NSArray *point = input[@"point"], *frame = node[@"frame"];
            if (!point) return nil;
            double x = [point[0] doubleValue], y = [point[1] doubleValue];
            return x >= [frame[0] doubleValue] && y >= [frame[1] doubleValue] &&
                x < [frame[0] doubleValue] + [frame[2] doubleValue] &&
                y < [frame[1] doubleValue] + [frame[3] doubleValue] ? node : nil;
        }
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
                ![@[@"checkbox", @"popup", @"button"] containsObject:expected[@"role"] ?: @""] ||
                ![expected[@"enabled"] boolValue] || ![expected[@"editable"] boolValue]) return nil;
            double x = [point[0] doubleValue], y = [point[1] doubleValue];
            if (x < [frame[0] doubleValue] || y < [frame[1] doubleValue] ||
                x >= [frame[0] doubleValue] + [frame[2] doubleValue] || y >= [frame[1] doubleValue] + [frame[3] doubleValue]) return nil;
            for (NSDictionary *column in grid[@"columns"]) if ([column[@"id"] isEqual:target[@"column"]])
                return [column[@"enabled"] boolValue] && [column[@"editable"] boolValue] ? node : nil;
            return nil;
        }
        if ([_pending[@"operation"] isEqual:@"gridSelect"]) {
            NSDictionary *grid = node[@"grid"];
            NSArray *point = input[@"point"], *desired = _pending[@"value"];
            if (!point || !input[@"serial"] || ![grid[@"actions"][@"select"] boolValue] ||
                ![grid[@"generation"] isEqual:_pendingSelectionGeneration]) return nil;
            for (NSString *row in grid[@"frames"]) {
                BOOL selected = [grid[@"selected"] containsObject:row], wanted = [desired containsObject:row];
                BOOL multiple = [grid[@"selectionMode"] isEqual:@"multiple"];
                BOOL single = [grid[@"selectionMode"] isEqual:@"single"];
                if ((!multiple && !single) || (single && (desired.count > 1 || (desired.count == 1 && !wanted))) || selected == wanted || !AXBGridRowAllowsSelection(grid, row)) continue;
                for (NSDictionary *column in grid[@"columns"]) {
                    if (![column[@"selectionTarget"] boolValue] || ![column[@"enabled"] boolValue]) continue;
                    NSArray *frame = grid[@"frames"][row][column[@"id"]];
                    double x = [point[0] doubleValue], y = [point[1] doubleValue];
                    if (!frame || x < [frame[0] doubleValue] || y < [frame[1] doubleValue] ||
                        x >= [frame[0] doubleValue] + [frame[2] doubleValue] || y >= [frame[1] doubleValue] + [frame[3] doubleValue]) continue;
                    NSMutableDictionary *selectionNode = [node mutableCopy];
                    selectionNode[@"target"] = @{@"row": row, @"column": column[@"id"]};
                    selectionNode[@"toggleSelection"] = @(multiple || desired.count == 0);
                    return selectionNode;
                }
            }
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
        if ([_pending[@"operation"] isEqual:@"gridPress"]) {
            NSDictionary *expected = _pending[@"value"][@"expectedCell"];
            if (![expected isEqual:[_grids[_pending[@"node"]] cellForRow:_pending[@"value"][@"row"] column:_pending[@"value"][@"column"] now:NSProcessInfo.processInfo.systemUptime]]) return nil;
        }
        NSMutableDictionary *result = [node mutableCopy];
        result[@"operation"] = _pending[@"operation"];
        if ([@[@"gridPress", @"gridHeaderPress"] containsObject:_pending[@"operation"]]) result[@"target"] = _pending[@"value"];
        return result;
    }
}
- (void)finishControlInput:(NSDictionary *)input accepted:(BOOL)accepted {
    @synchronized(self) {
        if (!_active || !_delivered || ![_pending[@"id"] isEqual:input[@"action"]] || ![_controlInput isEqual:input] || _controlInputResult) return;
        NSMutableDictionary *result = [@{@"action": input[@"action"], @"accepted": @(accepted), @"menuOpened": @(_controlMenuOpened)} mutableCopy];
        if (input[@"serial"]) result[@"serial"] = input[@"serial"];
        _controlInputResult = result;
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
    return [self exchangeParsed:[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] now:now];
}
- (NSDictionary *)exchangeParsed:(NSDictionary *)envelope now:(NSTimeInterval)now {
    @synchronized(self) {
        if (!_active) return @{@"ok": @NO, @"error": @"session closed"};
        NSTimeInterval sinceLast = _lastExchangeAt > 0 && now > _lastExchangeAt ? now - _lastExchangeAt : 0;
        _lastExchangeAt = now;
        if (sinceLast > 0) _exchangeInterval = sinceLast;
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
            _pendingSelectionGeneration = nil;
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
        BOOL gridInput = controlInput[@"point"] && _delivered && [_pending[@"id"] isEqual:controlInput[@"action"]] && [@[@"gridPress", @"gridHeaderPress", @"gridSelect"] containsObject:_pending[@"operation"] ?: @""];
        // A target can move or become unavailable between host confirmation
        // and this snapshot. Let the native dispatcher acknowledge that grid
        // input as rejected without disabling the entire accessibility session.
        if (controlInput && !gridInput && ![self controlInputNode:controlInput snapshot:next]) return @{@"ok": @NO, @"error": @"control input does not match the active control action"};
        BOOL selectionStep = controlInput[@"serial"] && [_pending[@"operation"] isEqual:@"gridSelect"];
        BOOL nextSelectionStep = selectionStep && _controlInput &&
            [controlInput[@"serial"] unsignedIntegerValue] == [_controlInput[@"serial"] unsignedIntegerValue] + 1 &&
            [_controlInputResult[@"accepted"] boolValue];
        if (controlInput[@"serial"] && (!selectionStep || (!_controlInput && [controlInput[@"serial"] unsignedIntegerValue] != 1)))
            return @{@"ok": @NO, @"error": @"control input serial does not match selection"};
        if (controlInput && _controlInput && ![_controlInput isEqual:controlInput] && !nextSelectionStep) return @{@"ok": @NO, @"error": @"control input replay changed its contents"};
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
        if (controlInput && (!_controlInput || nextSelectionStep)) {
            _controlInput = controlInput;
            _controlInputResult = nil;
            _controlMenuOpened = NO;
            _controlInputState = ActionState(next, _pending);
            result[@"controlInput"] = controlInput;
        }
        if (_controlInputResult) result[@"controlInputResult"] = _controlInputResult;
        if (_inputResult) result[@"editorInputResult"] = _inputResult;
        if (_lastResult) result[@"result"] = _lastResult;
        [self startWaitingAt:now];
        if (_pending && !_delivered) {
            BOOL changedGridValue = _pendingGridValue && !SameGridDispatchValue(_pendingGridValue,
                [_grids[_pending[@"node"]] cellForRow:_pending[@"value"][@"row"] column:_pending[@"value"][@"column"] now:now], _pending);
            // A queued action is meant for now, as a click is: it expires after three seconds, or
            // two and a half description intervals where describing the form takes longer, as an
            // interpreted one can. The slower of the interval when it was queued and the one now
            // ending counts, so a press made while 4D was busy runs once 4D is free, as a click
            // queued by macOS would; never after fifteen seconds.
            NSTimeInterval limit = MIN(15.0, MAX(3.0, 2.5 * MAX(_queuedInterval, sinceLast)));
            if (now - _queuedAt > limit || changedGridValue || !SameDispatchState(_pendingState, ActionState(next, _pending), _pending[@"node"]) || ![next[@"enabled"] boolValue]) {
                _lastResult = @{@"id": _pending[@"id"], @"status": @"rejected", @"message": @"expired or changed before dispatch"};
                result[@"result"] = _lastResult;
                _pending = nil;
                _pendingState = nil;
                _pendingGridValue = nil;
                _pendingSelectionGeneration = nil;
            } else {
                // Dispatch against the state just checked by both the session
                // and host. Keep the original revision for diagnostics only.
                if (![_pending[@"revision"] isEqual:next[@"revision"]]) {
                    NSMutableDictionary *current = [_pending mutableCopy];
                    current[@"requestedRevision"] = _pending[@"revision"];
                    current[@"revision"] = next[@"revision"];
                    _pending = [current copy];
                }
                NSMutableDictionary *delivered = [_pending mutableCopy];
                [delivered removeObjectForKey:@"requestValue"];
                result[@"action"] = [delivered copy];
                _delivered = YES;
                _pendingState = nil;
                _pendingGridValue = nil;
            }
        }
        result[@"busy"] = @(_pending != nil || _waiting.count > 0);
        return result;
    }
}
- (BOOL)enqueueNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value now:(NSTimeInterval)now {
    return [self enqueueNode:nodeID revision:revision operation:operation value:value observedSnapshot:nil now:now];
}
// An action requested while another is under way waits for it, at most eight at a time and for
// fifteen seconds. The same action as one under way or waiting is refused: a repeated press must
// not run twice. Reveals neither wait nor are waited for. Each request is validated now, and again
// when its turn comes.
- (BOOL)enqueueNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value observedSnapshot:(NSDictionary *)observed now:(NSTimeInterval)now {
    @synchronized(self) {
        NSDictionary *gridValue = nil;
        NSDictionary *action = [self actionForNode:nodeID revision:revision operation:operation value:value observedSnapshot:observed now:now gridValue:&gridValue];
        if (!action) return NO;
        if (!_pending) {
            [self startAction:action gridValue:gridValue now:now];
            return YES;
        }
        // VoiceOver reveals what its cursor reaches, and follows a reveal with requests of its own
        // that a user never made, such as selecting the row it reached. As before, those are
        // refused while a reveal is under way, and a reveal never waits: the latest one is what counts.
        NSArray *reveals = @[@"reveal", @"gridReveal", @"gridHeaderReveal"];
        if ([reveals containsObject:operation] || [reveals containsObject:_pending[@"operation"] ?: @""]) return NO;
        NSDictionary *request = @{@"node": nodeID, @"operation": operation, @"value": value ?: NSNull.null};
        NSDictionary *current = @{@"node": _pending[@"node"], @"operation": _pending[@"operation"], @"value": _pending[@"requestValue"] ?: NSNull.null};
        if (_waiting.count >= 8 || [request isEqual:current]) return NO;
        for (NSDictionary *entry in _waiting)
            if ([request isEqual:@{@"node": entry[@"node"], @"operation": entry[@"operation"], @"value": entry[@"value"]}]) return NO;
        NSMutableDictionary *entry = [request mutableCopy];
        entry[@"at"] = @(now);
        entry[@"target"] = TargetState(_snapshot, action);
        [_waiting addObject:entry];
        return YES;
    }
}
// The next waiting action, once none is under way: validated again against the current tree, and
// started only if what the client acted on is unchanged. Others are dropped.
- (void)startWaitingAt:(NSTimeInterval)now {
    while (!_pending && _waiting.count) {
        NSDictionary *entry = _waiting.firstObject;
        [_waiting removeObjectAtIndex:0];
        if (now - [entry[@"at"] doubleValue] > 15) continue;
        id value = entry[@"value"] == NSNull.null ? nil : entry[@"value"];
        NSDictionary *gridValue = nil;
        NSDictionary *action = [self actionForNode:entry[@"node"] revision:_snapshot[@"revision"] operation:entry[@"operation"] value:value
                                  observedSnapshot:nil now:now gridValue:&gridValue];
        if (action && [TargetState(_snapshot, action) isEqual:entry[@"target"]]) [self startAction:action gridValue:gridValue now:now];
    }
}
- (void)startAction:(NSDictionary *)action gridValue:(NSDictionary *)gridValue now:(NSTimeInterval)now {
    _pending = action;
    _pendingState = ActionState(_snapshot, _pending);
    NSDictionary *node = nil;
    for (NSDictionary *candidate in _snapshot[@"nodes"]) if ([candidate[@"id"] isEqual:action[@"node"]]) { node = candidate; break; }
    _pendingSelectionGeneration = [action[@"operation"] isEqual:@"gridSelect"] ? node[@"grid"][@"generation"] : nil;
    _pendingGridValue = gridValue;
    _lastInputSerial = 0;
    _lastInput = nil;
    _inputResult = nil;
    _queuedAt = now;
    _queuedInterval = _exchangeInterval;
    _delivered = NO;
}
// The action a request stands for against the current tree, or nil if it does not apply. Changes nothing.
- (NSDictionary *)actionForNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value
               observedSnapshot:(NSDictionary *)observed now:(NSTimeInterval)now gridValue:(NSDictionary **)gridValueOut {
    id requestValue = value;
    {
        if (!_active || ![_snapshot[@"enabled"] boolValue]) return nil;
        if (![revision isEqual:_snapshot[@"revision"]]) {
            NSDictionary *request = @{@"node": nodeID, @"operation": operation};
            if (!observed || ![observed[@"revision"] isEqual:revision] || [revision compare:_snapshot[@"revision"]] != NSOrderedAscending ||
                !SameDispatchState(ActionState(observed, request), ActionState(_snapshot, request), nodeID)) return nil;
        }
        NSDictionary *node = nil;
        for (NSDictionary *candidate in _snapshot[@"nodes"]) if ([candidate[@"id"] isEqual:nodeID]) { node = candidate; break; }
        if (!node || (![node[@"enabled"] boolValue] && ![operation isEqual:@"reveal"]) || ![node[@"visible"] boolValue]) return nil;
        NSString *role = node[@"role"];
        NSDictionary *gridValue = nil;
        if ([operation isEqual:@"press"]) {
            if (![@[@"button", @"checkbox", @"radio", @"popup", @"tab"] containsObject:role]) return nil;
        } else if ([operation isEqual:@"showMenu"] && node[@"menu"]) {
            if (value) return nil;
        } else if ([@[@"showMenu", @"confirm", @"dismissMenu"] containsObject:operation]) {
            if (![node[@"combo"] boolValue]) return nil;
        } else if ([@[@"increment", @"decrement"] containsObject:operation]) {
            if (![@[@"slider", @"stepper", @"splitter"] containsObject:role] || ![node[@"adjustable"] boolValue] || value) return nil;
        } else if ([operation isEqual:@"pictureEdit"]) {
            if (![node[@"pictureActions"] containsObject:value ?: @""]) return nil;
        } else if ([operation isEqual:@"choose"]) {
            if (!node[@"choices"] || !Number(value) || [value doubleValue] < 1 || [value doubleValue] > [node[@"choices"] count] ||
                floor([value doubleValue]) != [value doubleValue]) return nil;
        } else if ([operation isEqual:@"reveal"]) {
            if (![node[@"revealable"] boolValue] || value) return nil;
        } else if ([operation isEqual:@"focus"]) {
            if (![node[@"focusable"] boolValue] || !Bool(value) || ![value boolValue]) return nil;
        } else if ([operation isEqual:@"setValue"] && [role isEqual:@"splitter"]) {
            if (![node[@"adjustable"] boolValue] || !Number(value) || fabs([value doubleValue]) > 100000) return nil;
        } else if ([operation isEqual:@"setValue"] || [operation isEqual:@"replaceSelection"]) {
            if (![role isEqual:@"textfield"] || !Text(value, AXBLimits::text) || (node[@"editable"] && ![node[@"editable"] boolValue])) return nil;
            if ([operation isEqual:@"replaceSelection"] && (!node[@"selection"] || [node[@"protected"] boolValue])) return nil;
        } else if ([operation isEqual:@"setSelection"]) {
            if (![role isEqual:@"textfield"] || ![node[@"editable"] boolValue] || [node[@"protected"] boolValue] || ![value isKindOfClass:NSArray.class] || [value count] != 2) return nil;
            for (id part in value) if (!Number(part) || [part doubleValue] < 0 || floor([part doubleValue]) != [part doubleValue]) return nil;
            if ([value[0] doubleValue] + [value[1] doubleValue] > [node[@"value"] length]) return nil;
            if (!AXBTextRangeValid(node[@"value"], NSMakeRange([value[0] unsignedIntegerValue], [value[1] unsignedIntegerValue]))) return nil;
        } else if ([@[@"gridHeaderPress", @"gridHeaderReveal"] containsObject:operation]) {
            AXBGrid *grid = _grids[nodeID];
            if (![role isEqual:@"table"] || ![value isKindOfClass:NSDictionary.class] || !Text(value[@"column"], 256) ||
                [grid indexOfColumn:value[@"column"]] == NSNotFound) return nil;
            NSDictionary *header = grid.descriptor[@"columns"][[grid indexOfColumn:value[@"column"]]][@"header"];
            if (![header[@"visible"] boolValue] ||
                ([operation isEqual:@"gridHeaderReveal"] && ![grid.descriptor[@"actions"][@"reveal"] boolValue]) ||
                ([operation isEqual:@"gridHeaderPress"] && (![header[@"enabled"] boolValue] || ![header[@"press"] boolValue]))) return nil;
            value = @{@"column": value[@"column"], @"generation": grid.descriptor[@"generation"], @"expectedHeader": header};
        } else if ([operation isEqual:@"gridSetExpanded"]) {
            AXBGrid *grid = _grids[nodeID];
            if (![role isEqual:@"table"] || ![value isKindOfClass:NSDictionary.class] || !Text(value[@"row"], 256) ||
                !Bool(value[@"expanded"]) || [grid indexOfRow:value[@"row"]] == NSNotFound ||
                !AXBGridRowAllowsDisclosure(grid.descriptor, value[@"row"])) return nil;
            // Discard all caller-supplied guards, coordinates and callback data.
            value = @{@"row": value[@"row"], @"expanded": value[@"expanded"], @"generation": grid.descriptor[@"generation"],
                @"expectedGroup": AXBGridGroupActionState(grid.descriptor, value[@"row"])};
        } else if ([operation isEqual:@"gridSelect"]) {
            AXBGrid *grid = _grids[nodeID];
            if (![role isEqual:@"table"] || !AXBGridSelectionKnown(grid.descriptor) || ![grid.descriptor[@"actions"][@"select"] boolValue] || ![value isKindOfClass:NSArray.class] || [value count] > [grid.descriptor[@"rows"] count]) return nil;
            NSMutableSet *selected = [NSMutableSet new];
            for (id key in value) {
                if (!Text(key, 256) || [selected containsObject:key] || [grid indexOfRow:key] == NSNotFound ||
                    (![grid.descriptor[@"selected"] containsObject:key] && !AXBGridRowAllowsSelection(grid.descriptor, key))) return nil;
                [selected addObject:key];
            }
        } else if ([@[@"gridReveal", @"gridEdit", @"gridPress", @"gridSetValue", @"gridSetSelection", @"gridReplaceSelection"] containsObject:operation]) {
            AXBGrid *grid = _grids[nodeID];
            BOOL edit = ![operation isEqual:@"gridReveal"];
            if (![role isEqual:@"table"] || ![grid.descriptor[@"actions"][edit ? @"edit" : @"reveal"] boolValue] || ![value isKindOfClass:NSDictionary.class] ||
                !Text(value[@"row"], 256) || !Text(value[@"column"], 256) || [grid indexOfRow:value[@"row"]] == NSNotFound || [grid indexOfColumn:value[@"column"]] == NSNotFound) return nil;
            NSMutableDictionary *target = [value mutableCopy]; target[@"generation"] = grid.descriptor[@"generation"]; value = target;
            if (edit) {
                if (!AXBGridRowAllowsEditing(grid.descriptor, value[@"row"])) return nil;
                NSDictionary *column = grid.descriptor[@"columns"][[grid indexOfColumn:value[@"column"]]];
                gridValue = [grid cellForRow:value[@"row"] column:value[@"column"] now:now];
                if (![column[@"editable"] boolValue] || ![column[@"enabled"] boolValue] || ![gridValue[@"editable"] boolValue] || ![gridValue[@"enabled"] boolValue]) return nil;
                BOOL widget = [@[@"checkbox", @"popup", @"button"] containsObject:gridValue[@"role"] ?: @""];
                if ([operation isEqual:@"gridPress"] && !widget) return nil;
                if ([operation isEqual:@"gridEdit"] && gridValue[@"focusable"] && ![gridValue[@"focusable"] boolValue]) return nil;
                if (widget && ![@[@"gridPress", @"gridEdit"] containsObject:operation]) return nil;
                if (widget) {
                    target[@"expectedCell"] = gridValue;
                    // Non-text controls have focus without a text selection.
                    // The host rechecks the exact native cell before activation.
                }
                NSDictionary *focus = grid.descriptor[@"focused"];
                BOOL focused = !widget && [focus[@"row"] isEqual:value[@"row"]] && [focus[@"column"] isEqual:value[@"column"]] && focus[@"value"];
                if (focused && !focus[@"selection"]) return nil;
                if ([operation isEqual:@"gridSetValue"] || [operation isEqual:@"gridReplaceSelection"]) {
                    if (!Text(value[@"text"], AXBLimits::text)) return nil;
                    // The provider must compare this to its live rendered value
                    // before entering the real editor, then use normal editing.
                    target[@"expectedValue"] = focused ? focus[@"value"] : gridValue[@"value"];
                }
                if ([@[@"gridSetSelection", @"gridReplaceSelection"] containsObject:operation]) {
                    if (!focused || !focus[@"selection"]) return nil;
                    if ([operation isEqual:@"gridSetSelection"]) {
                        id range = value[@"selection"];
                        if (![range isKindOfClass:NSArray.class] || [range count] != 2) return nil;
                        for (id part in range) if (!Number(part) || [part doubleValue] < 0 || floor([part doubleValue]) != [part doubleValue]) return nil;
                        if ([range[0] doubleValue] + [range[1] doubleValue] > [focus[@"value"] length] ||
                            !AXBTextRangeValid(focus[@"value"], NSMakeRange([range[0] unsignedIntegerValue], [range[1] unsignedIntegerValue]))) return nil;
                    }
                }
                if (focused) {
                    target[@"expectedEditor"] = focus;
                    target[@"expectedValue"] = focus[@"value"];
                }
            }
        } else if ([operation isEqual:@"selectRows"]) {
            if (![role isEqual:@"table"] || ![value isKindOfClass:NSArray.class] || [value count] > 100) return nil;
            NSMutableSet *selected = [NSMutableSet new];
            for (id rowID in value) {
                if (!Text(rowID, 128) || [selected containsObject:rowID]) return nil;
                [selected addObject:rowID];
                BOOL valid = NO;
                for (NSDictionary *row in _snapshot[@"nodes"]) if ([row[@"id"] isEqual:rowID] && [row[@"parent"] isEqual:nodeID] &&
                    [row[@"role"] isEqual:@"row"] && [row[@"visible"] boolValue] && [row[@"enabled"] boolValue]) { valid = YES; break; }
                if (!valid) return nil;
            }
        } else return nil;
        NSMutableDictionary *action = [@{@"id": NSUUID.UUID.UUIDString, @"session": _identifier,
            @"node": nodeID, @"revision": _snapshot[@"revision"], @"operation": operation} mutableCopy];
        if (![revision isEqual:_snapshot[@"revision"]]) action[@"requestedRevision"] = revision;
        if (value) action[@"value"] = value;
        if (![NSJSONSerialization isValidJSONObject:action]) return nil;
        NSData *actionBytes = [NSJSONSerialization dataWithJSONObject:action options:0 error:nil];
        if (!actionBytes || actionBytes.length > AXBLimits::payload) return nil;
        NSMutableDictionary *parsed = [[NSJSONSerialization JSONObjectWithData:actionBytes options:0 error:nil] mutableCopy];
        // What the client asked, to recognize the same request again; never sent to the host.
        if (requestValue) parsed[@"requestValue"] = requestValue;
        if (gridValueOut) *gridValueOut = gridValue;
        return [parsed copy];
    }
}
@end
