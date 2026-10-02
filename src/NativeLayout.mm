#import "NativeLayout.h"
#import <objc/runtime.h>
#include <cmath>
#include <atomic>

static NSMapTable<NSWindow *, NSMutableArray<NSDictionary *> *> *layouts;
static NSMapTable<NSWindow *, NSMutableDictionary<NSString *, NSDictionary *> *> *layoutOwners;
static NSMapTable<NSDictionary *, NSView *> *paintViews;
static NSHashTable<NSWindow *> *observedWindows;
static NSHashTable<NSWindow *> *restartWindows;
@interface AXBTabPaint : NSObject
@property(nonatomic, weak) NSView *view;
@property(nonatomic, copy) NSDictionary *layout;
@property(nonatomic) NSUInteger epoch;
@end
@implementation AXBTabPaint
@end
static NSObject *paintLock;
static NSMutableArray<AXBTabPaint *> *pendingPaints;
static NSUInteger paintEpoch;
static NSString * const DrawingKey = @"org.sweetwater.AccessibilityBridge.tabDrawing";
static NSUInteger serial;
static IMP originalDraw, observedDraw, originalSegment, observedSegment, originalPopup, observedPopup;
static BOOL hooksInstalled;
static std::atomic_bool observing{false};

static NSString *JSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static NSArray *RectJSON(NSRect rect) { return @[@(rect.origin.x), @(rect.origin.y), @(rect.size.width), @(rect.size.height)]; }
static BOOL FiniteRect(NSRect rect) {
    return std::isfinite(rect.origin.x) && std::isfinite(rect.origin.y) &&
        std::isfinite(rect.size.width) && std::isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0 && rect.size.width <= 100000 && rect.size.height <= 100000;
}
static BOOL Number(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
        std::isfinite([value doubleValue]);
}
static BOOL OwnedControlCell(NSCell *cell, NSView *view) {
    NSView *owner = cell.controlView;
    return ([owner isKindOfClass:NSControl.class] && ((NSControl *)owner).cell == cell) ||
        ([view isKindOfClass:NSControl.class] && ((NSControl *)view).cell == cell);
}
static NSUInteger EvictionIndex(NSArray *items, NSString *kind, BOOL queued) {
    NSUInteger count = 0, first = NSNotFound;
    for (NSUInteger i = 0; i < items.count; ++i) {
        NSDictionary *layout = queued ? ((AXBTabPaint *)items[i]).layout : items[i];
        if (![layout[@"kind"] isEqual:kind]) continue;
        if (first == NSNotFound) first = i;
        ++count;
    }
    // Grid popups must not consume the tab strip's paint budget.
    return count >= 512 ? first : NSNotFound;
}

// 4D paints its canvas on a worker thread. Keep the nested draw context on
// that thread and defer all NSView/NSWindow traversal to the main thread.
static NSMutableArray *DrawingStack(void) {
    NSMutableDictionary *storage = NSThread.currentThread.threadDictionary;
    NSMutableArray *stack = storage[DrawingKey];
    if (!stack) { stack = [NSMutableArray new]; storage[DrawingKey] = stack; }
    return stack;
}
static void QueuePaint(NSView *view, NSDictionary *layout, NSUInteger epoch) {
    AXBTabPaint *paint = [AXBTabPaint new];
    paint.view = view; paint.epoch = epoch; paint.layout = layout;
    // Retain no canvas, cell or window. Bound drawing before registration too.
    @synchronized(paintLock) {
        if (epoch != paintEpoch) return;
        NSIndexSet *previous = [pendingPaints indexesOfObjectsPassingTest:^BOOL(AXBTabPaint *item, NSUInteger index, BOOL *stop) {
            (void)index; (void)stop;
            return item.view == view && [item.layout[@"anchor"] isEqual:layout[@"anchor"]];
        }];
        [pendingPaints removeObjectsAtIndexes:previous];
        NSUInteger eviction = EvictionIndex(pendingPaints, layout[@"kind"], YES);
        if (eviction != NSNotFound) [pendingPaints removeObjectAtIndex:eviction];
        [pendingPaints addObject:paint];
    }
}
static void DrainPaints(void) {
    if (!NSThread.isMainThread) return;
    NSArray<AXBTabPaint *> *paints;
    NSUInteger epoch;
    @synchronized(paintLock) {
        paints = [pendingPaints copy]; [pendingPaints removeAllObjects]; epoch = paintEpoch;
    }
    if (!layouts) layouts = [NSMapTable weakToStrongObjectsMapTable];
    if (!layoutOwners) layoutOwners = [NSMapTable weakToStrongObjectsMapTable];
    if (!paintViews) paintViews = [NSMapTable weakToWeakObjectsMapTable];
    for (AXBTabPaint *paint in paints) {
        NSWindow *window = paint.view.window;
        if (!window || paint.epoch != epoch) continue;
        NSMutableArray *windowLayouts = [layouts objectForKey:window];
        if (!windowLayouts) { windowLayouts = [NSMutableArray new]; [layouts setObject:windowLayouts forKey:window]; }
        NSMutableDictionary *layout = [paint.layout mutableCopy];
        layout[@"serial"] = @(++serial);
        NSIndexSet *previous = [windowLayouts indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
            (void)index; (void)stop; return [item[@"anchor"] isEqual:layout[@"anchor"]];
        }];
        [windowLayouts removeObjectsAtIndexes:previous];
        NSUInteger eviction = EvictionIndex(windowLayouts, layout[@"kind"], NO);
        if (eviction != NSNotFound) {
            [[layoutOwners objectForKey:window] removeObjectForKey:JSON(windowLayouts[eviction][@"anchor"])];
            [windowLayouts removeObjectAtIndex:eviction];
        }
        [windowLayouts addObject:layout];
        [paintViews setObject:paint.view forKey:layout];
    }
}

// 4D's canvas uses a segmented cell without an NSControl. Real AppKit controls
// retain their native accessibility. Chain the public drawing methods without
// changing arguments or rendering; no private 4D class/selector is referenced.
void AXBLayoutInitialize(void) {
    if (hooksInstalled) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ paintLock = [NSObject new]; pendingPaints = [NSMutableArray new]; });
    Class cls = NSSegmentedCell.class, segmentClass = NSSegmentedCell.class;
    SEL draw = @selector(drawWithFrame:inView:), segment = @selector(drawSegment:inFrame:withView:);
    Method drawMethod = class_getInstanceMethod(cls, draw), segmentMethod = class_getInstanceMethod(segmentClass, segment);
    Method popupMethod = class_getInstanceMethod(NSPopUpButtonCell.class, draw);
    // Ordinary database reopen can reuse the same wrappers. Retain a chained
    // wrapper only when another observer still references its implementation.
    if (observedDraw && method_getImplementation(drawMethod) == originalDraw && method_getImplementation(segmentMethod) == originalSegment &&
        method_getImplementation(popupMethod) == originalPopup) {
        method_setImplementation(segmentMethod, observedSegment);
        method_setImplementation(drawMethod, observedDraw);
        method_setImplementation(popupMethod, observedPopup);
        observing.store(true); hooksInstalled = YES;
        return;
    }
    originalDraw = method_getImplementation(drawMethod);
    originalSegment = method_getImplementation(segmentMethod);
    originalPopup = method_getImplementation(popupMethod);
    IMP chainedDraw = originalDraw, chainedSegment = originalSegment, chainedPopup = originalPopup;
    observedSegment = imp_implementationWithBlock(^(NSSegmentedCell *cell, NSInteger index, NSRect frame, NSView *view) {
        if (!observing.load()) { ((void (*)(id, SEL, NSInteger, NSRect, NSView *))chainedSegment)(cell, segment, index, frame, view); return; }
        NSMutableDictionary *capture = DrawingStack().lastObject;
        if (capture && [capture[@"cell"] pointerValue] == (__bridge void *)cell &&
            index >= 0 && index < cell.segmentCount && FiniteRect(frame)) {
            NSRect parent = NSRectFromString(capture[@"body"]);
            // AppKit cell rectangles use an upward y axis. 4D form coordinates
            // use a downward y axis; retain the actual segment's relative box.
            NSRect relative = NSMakeRect(NSMinX(frame)-NSMinX(parent), NSMaxY(parent)-NSMaxY(frame), NSWidth(frame), NSHeight(frame));
            capture[@"segments"][@(index).stringValue] = @{@"frame": RectJSON(relative),
                @"enabled": @([cell isEnabledForSegment:index]), @"selected": @([cell isSelectedForSegment:index])};
        }
        ((void (*)(id, SEL, NSInteger, NSRect, NSView *))chainedSegment)(cell, segment, index, frame, view);
    });
    observedDraw = imp_implementationWithBlock(^(NSSegmentedCell *cell, NSRect frame, NSView *view) {
        if (!observing.load()) { ((void (*)(id, SEL, NSRect, NSView *))chainedDraw)(cell, draw, frame, view); return; }
        BOOL segmented = [cell isKindOfClass:NSSegmentedCell.class];
        NSMutableArray *drawing = DrawingStack();
        NSMutableDictionary *capture = nil;
        NSUInteger epoch;
        @synchronized(paintLock) { epoch = paintEpoch; }
        BOOL alreadyDrawing = drawing.lastObject && [drawing.lastObject[@"cell"] pointerValue] == (__bridge void *)cell;
        if (segmented && view && !alreadyDrawing && !OwnedControlCell(cell, view) && cell.segmentCount > 0 && cell.segmentCount <= 4096 && FiniteRect(frame)) {
            CGContextRef context = NSGraphicsContext.currentContext.CGContext;
            CGAffineTransform transform = context ? CGContextGetCTM(context) : CGAffineTransformIdentity;
            // Fail closed on rotated/skewed drawing. The tested 4D renderer
            // translates its local canvas to the tab object's top edge.
            if (transform.a > 0 && transform.d > 0 && transform.b == 0 && transform.c == 0 && std::isfinite(transform.ty)) {
                capture = [@{@"cell": [NSValue valueWithPointer:(__bridge void *)cell], @"body": NSStringFromRect(frame),
                    @"anchor": @[@(NSMidX(frame)), @(transform.ty/transform.d)],
                    @"count": @(cell.segmentCount), @"segments": [NSMutableDictionary new]} mutableCopy];
                [drawing addObject:capture];
            }
        }
        @try {
            ((void (*)(id, SEL, NSRect, NSView *))chainedDraw)(cell, draw, frame, view);
        } @finally {
            if (capture) [drawing removeLastObject];
        }
        if (!capture || [capture[@"segments"] count] != (NSUInteger)cell.segmentCount) return;
        NSMutableArray *segments = [NSMutableArray new];
        for (NSInteger i = 0; i < cell.segmentCount; i++) {
            NSDictionary *item = capture[@"segments"][@(i).stringValue];
            if (!item) return;
            [segments addObject:item];
        }
        QueuePaint(view, @{@"kind": @"tabs", @"anchor": capture[@"anchor"], @"body": RectJSON(frame), @"segments": segments}, epoch);
    });
    observedPopup = imp_implementationWithBlock(^(NSPopUpButtonCell *cell, NSRect frame, NSView *view) {
        if (!observing.load()) { ((void (*)(id, SEL, NSRect, NSView *))chainedPopup)(cell, draw, frame, view); return; }
        NSMutableArray *drawing = DrawingStack();
        BOOL alreadyDrawing = drawing.lastObject && [drawing.lastObject[@"cell"] pointerValue] == (__bridge void *)cell;
        BOOL capture = view && !alreadyDrawing && !OwnedControlCell(cell, view) && FiniteRect(frame);
        CGAffineTransform transform = CGAffineTransformIdentity;
        NSUInteger epoch;
        @synchronized(paintLock) { epoch = paintEpoch; }
        if (capture) {
            CGContextRef context = NSGraphicsContext.currentContext.CGContext;
            transform = context ? CGContextGetCTM(context) : CGAffineTransformIdentity;
            capture = transform.a > 0 && transform.d > 0 && transform.b == 0 && transform.c == 0 && std::isfinite(transform.ty);
        }
        if (capture) [drawing addObject:@{@"cell": [NSValue valueWithPointer:(__bridge void *)cell]}];
        @try {
            ((void (*)(id, SEL, NSRect, NSView *))chainedPopup)(cell, draw, frame, view);
        } @finally {
            if (capture) [drawing removeLastObject];
        }
        if (capture) QueuePaint(view, @{@"kind": @"popup", @"anchor": @[@(NSMidX(frame)), @(transform.ty/transform.d)],
            @"body": RectJSON(frame), @"label": [cell.title copy] ?: @""}, epoch);
    });
    if (!class_addMethod(segmentClass, segment, observedSegment, method_getTypeEncoding(segmentMethod))) method_setImplementation(segmentMethod, observedSegment);
    if (!class_addMethod(cls, draw, observedDraw, method_getTypeEncoding(drawMethod))) method_setImplementation(drawMethod, observedDraw);
    if (!class_addMethod(NSPopUpButtonCell.class, draw, observedPopup, method_getTypeEncoding(popupMethod))) method_setImplementation(popupMethod, observedPopup);
    observing.store(true); hooksInstalled = YES;
}

void AXBLayoutObserve(NSWindow *window) {
    if (!NSThread.isMainThread || !window) return;
    DrainPaints();
    if (!layouts) layouts = [NSMapTable weakToStrongObjectsMapTable];
    if (!observedWindows) observedWindows = [NSHashTable weakObjectsHashTable];
    [observedWindows addObject:window];
    if (![layouts objectForKey:window]) [layouts setObject:[NSMutableArray new] forKey:window];
}
void AXBLayoutForget(NSWindow *window) {
    if (!NSThread.isMainThread || !window) return;
    DrainPaints();
    if ([restartWindows containsObject:window]) {
        // 4D can keep displaying a cached canvas without drawing its cells
        // again. Transfer only unchanged paint claims to an intentional
        // restart; normal teardown still discards the whole cache.
        NSMutableDictionary *owners = [layoutOwners objectForKey:window];
        for (NSString *anchor in owners.allKeys) {
            NSMutableDictionary *claim = [owners[anchor] mutableCopy];
            claim[@"restart"] = @YES; owners[anchor] = claim;
        }
    } else {
        [layouts removeObjectForKey:window]; [layoutOwners removeObjectForKey:window];
    }
    [restartWindows removeObject:window]; [observedWindows removeObject:window];
}
void AXBLayoutShutdown(void) {
    observing.store(false);
    @synchronized(paintLock) { ++paintEpoch; [pendingPaints removeAllObjects]; }
    if (NSThread.isMainThread) { [layouts removeAllObjects]; [layoutOwners removeAllObjects]; [paintViews removeAllObjects]; [observedWindows removeAllObjects]; [restartWindows removeAllObjects]; }
    if (!hooksInstalled) return;
    Class cls = NSSegmentedCell.class;
    Method draw = class_getInstanceMethod(cls, @selector(drawWithFrame:inView:));
    Method segment = class_getInstanceMethod(NSSegmentedCell.class, @selector(drawSegment:inFrame:withView:));
    Method popup = class_getInstanceMethod(NSPopUpButtonCell.class, @selector(drawWithFrame:inView:));
    // Do not overwrite a later observer's implementation.
    if (method_getImplementation(draw) == observedDraw) method_setImplementation(draw, originalDraw);
    if (method_getImplementation(segment) == observedSegment) method_setImplementation(segment, originalSegment);
    if (method_getImplementation(popup) == observedPopup) method_setImplementation(popup, originalPopup);
    hooksInstalled = NO;
}

NSString *AXBReadNativeLayout(void *nativeWindow, NSString *request) {
    if (!NSThread.isMainThread) return JSON(@{@"ok": @NO, @"error": @"notMainThread"});
    DrainPaints();
    NSWindow *window = nil;
    for (NSWindow *candidate in NSApp.windows) if ((__bridge void *)candidate == nativeWindow) { window = candidate; break; }
    NSArray *candidates = [layouts objectForKey:window];
    if (!window || !candidates || ![observedWindows containsObject:window]) return JSON(@{@"ok": @NO, @"error": @"inactiveLayoutWindow"});
    NSDictionary *input = [NSJSONSerialization JSONObjectWithData:[request dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![input isKindOfClass:NSDictionary.class]) return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
    if (input[@"operation"]) {
        if (![input[@"operation"] isEqual:@"restart"]) return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
        if (!restartWindows) restartWindows = [NSHashTable weakObjectsHashTable];
        [restartWindows addObject:window];
        return JSON(@{@"ok": @YES});
    }
    NSArray *bounds = input[@"frame"];
    NSNumber *count = input[@"count"];
    NSString *owner = input[@"owner"];
    NSString *signature = input[@"signature"];
    if (owner && (![owner isKindOfClass:NSString.class] || owner.length == 0 || owner.length > 128))
        return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
    if (signature && (![signature isKindOfClass:NSString.class] || signature.length == 0 || signature.length > 128))
        return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
    if (![bounds isKindOfClass:NSArray.class] || bounds.count != 4 || !Number(count) || count.integerValue <= 0 ||
        count.integerValue > 4096 || count.doubleValue != count.integerValue) return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
    for (id number in bounds) if (!Number(number)) return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
    NSRect rect = NSMakeRect([bounds[0] doubleValue], [bounds[1] doubleValue], [bounds[2] doubleValue], [bounds[3] doubleValue]);
    if (!FiniteRect(rect)) return JSON(@{@"ok": @NO, @"error": @"invalidLayoutRequest"});
    NSDictionary *found = nil;
    for (NSDictionary *candidate in candidates) {
        NSView *canvas = [paintViews objectForKey:candidate];
        if (canvas.window != window || (canvas != window.contentView && ![canvas isDescendantOf:window.contentView])) continue;
        NSArray *anchor = candidate[@"anchor"];
        if ((![candidate[@"kind"] isEqual:@"popup"] && [candidate[@"segments"] count] != count.unsignedIntegerValue) ||
            fabs([anchor[0] doubleValue]-NSMidX(rect)) > 0.5 || fabs([anchor[1] doubleValue]-NSMinY(rect)) > 0.5) continue;
        if (found) return JSON(@{@"ok": @NO, @"error": @"ambiguousNativeTabLayout"});
        found = candidate;
    }
    if (!found) return JSON(@{@"ok": @NO, @"error": @"nativeTabLayoutPending"});
    if (owner) {
        NSMutableDictionary *owners = [layoutOwners objectForKey:window];
        if (!owners) { owners = [NSMutableDictionary new]; [layoutOwners setObject:owners forKey:window]; }
        NSString *anchor = JSON(found[@"anchor"]);
        NSDictionary *previous = owners[anchor];
        // A newly discovered control at an old paint position must not use
        // another control's segment widths before its own repaint arrives.
        if (previous && [found[@"serial"] unsignedIntegerValue] <= [previous[@"serial"] unsignedIntegerValue]) {
            if (![(signature ?: @"") isEqual:previous[@"signature"]] || ![bounds isEqual:previous[@"frame"]] ||
                (![previous[@"owner"] isEqual:owner] && ![previous[@"restart"] boolValue]))
                return JSON(@{@"ok": @NO, @"error": @"nativeTabLayoutPending"});
        }
        owners[anchor] = @{@"owner": owner, @"serial": found[@"serial"], @"signature": signature ?: @"", @"frame": bounds};
    }
    NSArray *body = found[@"body"];
    NSRect parent = NSMakeRect(NSMidX(rect)-[body[2] doubleValue]/2, NSMidY(rect)-[body[3] doubleValue]/2,
        [body[2] doubleValue], [body[3] doubleValue]);
    if (NSWidth(parent) > NSWidth(rect)+1) return JSON(@{@"ok": @NO, @"error": @"nativeTabOverflowPending"});
    if ([found[@"kind"] isEqual:@"popup"]) return JSON(@{@"ok": @YES, @"kind": @"popup", @"serial": found[@"serial"], @"label": found[@"label"], @"frame": RectJSON(parent)});
    NSMutableArray *segments = [NSMutableArray new];
    for (NSDictionary *item in found[@"segments"]) {
        NSArray *relative = item[@"frame"];
        NSRect frame = NSMakeRect(NSMinX(parent)+[relative[0] doubleValue], NSMinY(parent)+[relative[1] doubleValue],
            [relative[2] doubleValue], [relative[3] doubleValue]);
        [segments addObject:@{@"frame": RectJSON(frame), @"enabled": item[@"enabled"], @"selected": item[@"selected"]}];
    }
    return JSON(@{@"ok": @YES, @"kind": @"tabs", @"serial": found[@"serial"], @"segments": segments});
}
