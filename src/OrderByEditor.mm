#import "OrderByEditor.h"
#import "InternalForms.h"
#import "DrawnText.h"

static NSString *Localized(NSString *key) {
    return [[NSBundle bundleForClass:AXBInternalFormOverlay.class] localizedStringForKey:key value:key table:@"AccessibilityBridge"];
}

// The objects the editor draws text into, so a change in any of them refreshes the window.
static NSSet<NSString *> *OrderNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"tFields", @"tSortedFields", @"bAdd", @"bEdit", @"bCancel", @"bOK", @"tFields.title", @"tSortedFields.title"]];
    });
    return names;
}

static NSString *Joined(NSArray<NSString *> *texts) {
    return [[texts ?: @[] componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSMutableDictionary *Entry(NSString *key, CALayer *layer, NSString *role, NSString *label) {
    NSMutableDictionary *entry = [@{@"key": key, @"layer": layer, @"role": role} mutableCopy];
    if (label) entry[@"label"] = label;
    return entry;
}

// Each ordered line ends with a triangle 4D draws, pointing up when the line sorts ascending
// and down when it sorts descending; a click on it reverses it. Its rows of ink, those that
// stand out from the line's own background, widen downward or narrow downward.
static NSNumber *Descending(CALayer *list, NSRect triangle) {
    id contents = list.contents;
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return nil;
    CGImageRef image = (__bridge CGImageRef)contents;
    CGFloat height = NSHeight(list.bounds), scale = height > 0 ? CGImageGetHeight(image) / height : 0;
    if (scale <= 0) return nil;
    // From the bottom left to the image's top left, in pixels.
    CGRect box = CGRectMake(NSMinX(triangle) * scale, (height - NSMaxY(triangle)) * scale, NSWidth(triangle) * scale, NSHeight(triangle) * scale);
    CGImageRef part = CGImageCreateWithImageInRect(image, box);
    if (!part) return nil;
    size_t width = CGImageGetWidth(part), rows = CGImageGetHeight(part);
    NSMutableData *pixels = [NSMutableData dataWithLength:width * rows * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, rows, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(part); return nil; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, rows), part);
    CGContextRelease(context);
    CGImageRelease(part);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    auto luminance = [&](size_t x, size_t y) { const uint8_t *p = bytes + (y * width + x) * 4; return 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2]; };
    // The line's background: its corner.
    double background = luminance(0, rows / 2);
    NSMutableArray<NSNumber *> *widths = [NSMutableArray new];
    for (size_t y = 0; y < rows; y++) {
        NSUInteger ink = 0;
        for (size_t x = 0; x < width; x++) if (fabs(luminance(x, y) - background) > 80) ink++;
        if (ink) [widths addObject:@(ink)];
    }
    if (widths.count < 3) return nil;
    NSInteger top = widths.firstObject.integerValue, bottom = widths.lastObject.integerValue;
    if (top == bottom) return nil;
    return @(top > bottom);
}

// The editor's objects in reading order, or nil when the window is not the Order By editor.
static NSArray<NSDictionary *> *OrderEntries(CALayer *form) {
    CALayer *fields = AXBInternalFormChild(form, @"tFields"), *ordered = AXBInternalFormChild(form, @"tSortedFields"), *sort = AXBInternalFormChild(form, @"bOK");
    if (!fields || !ordered || !sort) return nil;
    NSMutableArray *entries = [NSMutableArray new];
    CALayer *layer;
    CALayer *caption = AXBInternalFormChild(form, @"tFields.title");
    if (caption) [entries addObject:Entry(@"fields.title", caption, NSAccessibilityStaticTextRole, nil)];
    // Each list holds its lines, named by its caption. An available field is added with a
    // double click, as with the mouse.
    [entries addObject:Entry(@"fields", fields, NSAccessibilityListRole, caption ? Joined(AXBDrawnTextForLayer(caption)) : Localized(@"Available Fields"))];
    for (NSDictionary *item in AXBInternalListItems(fields, @"field/", NSAccessibilityButtonRole) ?: @[]) {
        NSMutableDictionary *entry = [item mutableCopy];
        entry[@"clicks"] = @2;
        entry[@"list"] = @"fields";
        [entries addObject:entry];
    }
    NSArray *moves = @[@[@"bOne", @"Add field"], @[@"bRemoveOne", @"Remove field"], @[@"bRemoveAll", @"Remove all fields"]];
    for (NSArray *move in moves)
        if ((layer = AXBInternalFormChild(form, move[0]))) [entries addObject:Entry(move[0], layer, NSAccessibilityButtonRole, Localized(move[1]))];
    caption = AXBInternalFormChild(form, @"tSortedFields.title");
    if (caption) [entries addObject:Entry(@"order.title", caption, NSAccessibilityStaticTextRole, nil)];
    [entries addObject:Entry(@"order", ordered, NSAccessibilityListRole, caption ? Joined(AXBDrawnTextForLayer(caption)) : Localized(@"Ordered by"))];
    // An ordered line is selected with a click, for Remove field; its triangle, left of the
    // list's scroll bar, is its direction.
    CALayer *scroller = AXBInternalFormChild(ordered, @"vertical_scrollbar");
    CGFloat end = scroller ? NSMinX(scroller.frame) : NSWidth(ordered.bounds) - 20;
    for (NSDictionary *item in AXBInternalListItems(ordered, @"order/", NSAccessibilityButtonRole) ?: @[]) {
        NSMutableDictionary *ordering = [item mutableCopy];
        ordering[@"list"] = @"order";
        [entries addObject:ordering];
        NSRect line = [item[@"area"] rectValue];
        NSRect triangle = NSMakeRect(end - 26, NSMinY(line), 22, NSHeight(line));
        NSMutableDictionary *direction = Entry([item[@"key"] stringByAppendingString:@"/descending"], ordered, NSAccessibilityCheckBoxRole, Localized(@"Descending"));
        direction[@"area"] = [NSValue valueWithRect:triangle];
        direction[@"list"] = @"order";
        NSNumber *descending = Descending(ordered, triangle);
        if (descending) direction[@"checked"] = descending;
        [entries addObject:direction];
    }
    for (NSString *name in @[@"bAdd", @"bEdit", @"bCancel", @"bOK"])
        if ((layer = AXBInternalFormChild(form, name))) [entries addObject:Entry(name, layer, NSAccessibilityButtonRole, nil)];
    return entries;
}

static NSMapTable<NSWindow *, AXBInternalFormOverlay *> *Overlays;
static id KeyObserver, CloseObserver;

static void RemoveOverlay(NSWindow *window, AXBInternalFormOverlay *overlay) {
    if (!overlay) return;
    [overlay releaseFocus];
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
}

BOOL AXBOrderByEditorRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    CALayer *form = view ? AXBInternalFormContext(view) : nil;
    NSArray *entries = form ? OrderEntries(form) : nil;
    if (!entries) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:@"axb/order/"];
        created = YES;
    }
    if (![overlay updateWithEntries:entries]) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    if (created) {
        [view addSubview:overlay];
        [Overlays setObject:overlay forKey:window];
    }
    return YES;
}

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
    if (KeyObserver) return;
    KeyObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil
                                                              usingBlock:^(NSNotification *note) { AXBOrderByEditorRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
}

void AXBOrderByEditorInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(@"order", OrderNames(), ^(CALayer *layer) {
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBOrderByEditorRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBOrderByEditorShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(@"order", nil, nil);
    if (KeyObserver) [NSNotificationCenter.defaultCenter removeObserver:KeyObserver];
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    KeyObserver = CloseObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBOrderByEditorEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
