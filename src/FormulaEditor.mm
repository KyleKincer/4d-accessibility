#import "FormulaEditor.h"
#import "InternalForms.h"
#import "DrawnText.h"

// 4D draws each object into a layer larger than the object by a margin that depends on
// its kind; clicks and frames use the object itself.
static const CGFloat PopupInset = 10, ButtonInset = 5;

static NSString *Localized(NSString *key) {
    return [[NSBundle bundleForClass:AXBInternalFormOverlay.class] localizedStringForKey:key value:key table:@"AccessibilityBridge"];
}

// The objects the editor draws text into, so a change in any of them refreshes the window.
static NSSet<NSString *> *FormulaNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"vFormula", @"vMessage", @"helpString", @"lh_champ", @"LH_Operateur", @"LH_EnCm", @"_ope_filter", @"_ope_theme", @"_ope_routine",
                                      @"bLoad", @"bSave", @"bCancel", @"bOK"]];
    });
    return names;
}

static NSMutableDictionary *Entry(NSString *key, CALayer *layer, NSString *role, NSString *label, CGFloat inset) {
    NSMutableDictionary *entry = [@{@"key": key, @"layer": layer, @"role": role, @"inset": @(inset)} mutableCopy];
    if (label) entry[@"label"] = label;
    return entry;
}

// Whether 4D draws a disclosure chevron in an area of a list's image, and which way it points.
// Its pixels stand out from the area's most common shade, the line's own or its selection's.
// They span at most 11 points by 7, smaller than any icon, and form a tip in the middle of
// their long side: the middle row reaches furthest right for a chevron pointing right, the
// middle column lowest for one pointing down. Bars and dots, such as an operator's :=, do not.
static BOOL Chevron(CALayer *layer, NSRect area, BOOL *expanded) {
    id contents = layer.contents;
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return NO;
    CGImageRef image = (__bridge CGImageRef)contents;
    CGFloat height = NSHeight(layer.bounds), scale = height > 0 ? CGImageGetHeight(image) / height : 0;
    if (scale <= 0) return NO;
    // From the bottom left to the image's top left, in pixels.
    CGRect box = CGRectIntegral(CGRectMake(NSMinX(area) * scale, (height - NSMaxY(area)) * scale, NSWidth(area) * scale, NSHeight(area) * scale));
    CGImageRef part = CGImageCreateWithImageInRect(image, box);
    if (!part) return NO;
    size_t width = CGImageGetWidth(part), rows = CGImageGetHeight(part);
    NSMutableData *pixels = [NSMutableData dataWithLength:width * rows * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, rows, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(part); return NO; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, rows), part);
    CGContextRelease(context);
    CGImageRelease(part);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    auto luminance = [&](size_t x, size_t y) { const uint8_t *p = bytes + (y * width + x) * 4; return 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2]; };
    // The most common shade, in steps of 8.
    NSUInteger counts[33] = {0};
    for (size_t y = 0; y < rows; y++) for (size_t x = 0; x < width; x++) counts[(NSUInteger)(luminance(x, y) / 8)]++;
    NSUInteger common = 0;
    for (NSUInteger i = 1; i < 33; i++) if (counts[i] > counts[common]) common = i;
    double background = common * 8 + 4;
    auto ink = [&](size_t x, size_t y) { return fabs(luminance(x, y) - background) > 40; };
    NSInteger left = NSIntegerMax, right = -1, top = NSIntegerMax, bottom = -1;
    for (size_t y = 0; y < rows; y++)
        for (size_t x = 0; x < width; x++)
            if (ink(x, y)) { left = MIN(left, (NSInteger)x); right = MAX(right, (NSInteger)x); top = MIN(top, (NSInteger)y); bottom = MAX(bottom, (NSInteger)y); }
    if (right < 0) return NO;
    CGFloat across = (right - left + 1) / scale, along = (bottom - top + 1) / scale;
    BOOL down = across > along;
    if (MAX(across, along) < 4 || MAX(across, along) > 11 || MIN(across, along) < 2 || MIN(across, along) > 7) return NO;
    // The mean position of the ink in a row (or, pointing down, a column), across it.
    auto middle = [&](NSInteger at) {
        double sum = 0, count = 0;
        for (NSInteger i = down ? top : left; i <= (down ? bottom : right); i++)
            if (down ? ink((size_t)at, (size_t)i) : ink((size_t)i, (size_t)at)) { sum += i; count++; }
        return count ? sum / count : NAN;
    };
    NSInteger first = down ? left : top, last = down ? right : bottom;
    double ends = (middle(first) + middle(last)) / 2, tip = middle((first + last) / 2);
    // Rows run down, so a lower tip is a larger row, as a tip further right is a larger column.
    if (isnan(ends) || isnan(tip) || tip - ends < 1.5 * scale) return NO;
    *expanded = down;
    return YES;
}

// A list's lines. A line that 4D draws with a disclosure chevron, a table of fields or a theme
// of commands, is a disclosure triangle: the chevron points right while the line is collapsed
// and down while it is expanded, and a click on it toggles it. Any other line is a button whose
// double click inserts it into the formula, as with the mouse.
static NSArray<NSDictionary *> *ListEntries(CALayer *list, NSString *prefix, NSString *label) {
    // The list itself, which holds its lines.
    NSString *container = [prefix stringByAppendingString:@"list"];
    NSMutableArray *entries = [NSMutableArray arrayWithObject:Entry(container, list, NSAccessibilityListRole, label, 0)];
    NSCountedSet *seen = [NSCountedSet new];
    for (NSDictionary *item in AXBInternalListItems(list, @"", NSAccessibilityButtonRole) ?: @[]) {
        NSMutableDictionary *entry = [item mutableCopy];
        entry[@"list"] = container;
        NSRect line = [item[@"area"] rectValue], chevron = NSZeroRect;
        CGFloat offset = 0;
        CGFloat origin = [item[@"originX"] doubleValue];
        // The chevron lies just left of the text, or of the icon before it.
        BOOL expanded = NO;
        for (NSNumber *left in @[@16, @32]) {
            NSRect candidate = NSMakeRect(origin - left.doubleValue, NSMinY(line) + 2, 12, NSHeight(line) - 4);
            if (NSMinX(candidate) < 0 || !Chevron(list, candidate, &expanded)) continue;
            chevron = candidate; offset = left.doubleValue;
            break;
        }
        BOOL disclosure = !NSIsEmptyRect(chevron);
        // A line the list's edge cuts can lose its chevron: it is a table or theme when a whole one
        // starts its text where it does, so it keeps its element as it scrolls into view.
        if (NSMinY(line) < 0 || NSMaxY(line) > NSHeight(list.bounds)) entry[@"clipped"] = @YES;
        NSString *name = [(disclosure ? @"group/" : @"item/") stringByAppendingString:item[@"text"]];
        [seen addObject:name];
        NSUInteger count = [seen countForObject:name];
        entry[@"key"] = [NSString stringWithFormat:@"%@%@%@", prefix, name, count > 1 ? [NSString stringWithFormat:@"/%lu", (unsigned long)count] : @""];
        if (disclosure) {
            entry[@"role"] = NSAccessibilityDisclosureTriangleRole;
            entry[@"pressArea"] = [NSValue valueWithRect:chevron];
            entry[@"chevron"] = @(offset);
            // Expanded, it points down; a cut chevron's way is unknown.
            if (!entry[@"clipped"]) entry[@"checked"] = @(expanded);
        } else {
            entry[@"clicks"] = @2;
        }
        [entries addObject:entry];
    }
    // Where each whole table's or theme's chevron lies left of its text, by where its text starts.
    NSMutableDictionary<NSNumber *, NSNumber *> *groups = [NSMutableDictionary new];
    for (NSDictionary *entry in entries)
        if (![entry[@"clipped"] boolValue] && entry[@"chevron"]) groups[entry[@"originX"]] = entry[@"chevron"];
    for (NSMutableDictionary *entry in entries) {
        NSNumber *offset = groups[entry[@"originX"]];
        if (![entry[@"clipped"] boolValue] || entry[@"chevron"] || !offset) continue;
        // Its state is unknown without its chevron.
        entry[@"role"] = NSAccessibilityDisclosureTriangleRole;
        entry[@"key"] = [entry[@"key"] stringByReplacingOccurrencesOfString:[prefix stringByAppendingString:@"item/"] withString:[prefix stringByAppendingString:@"group/"]
                                                                      options:NSAnchoredSearch range:NSMakeRange(0, [entry[@"key"] length])];
        [entry removeObjectForKey:@"clicks"];
        NSRect line = [entry[@"area"] rectValue];
        entry[@"pressArea"] = [NSValue valueWithRect:NSMakeRect([entry[@"originX"] doubleValue] - offset.doubleValue, NSMinY(line) + 2, 12, NSHeight(line) - 4)];
    }
    return entries;
}

// 4D's form view is the window's text-input client; the formula holds 4D's keyboard focus
// when the first rectangle of its selection, the caret, lies in it.
static BOOL HoldsCaret(NSWindow *window, NSView *view, CALayer *formula) {
    if (!window.isKeyWindow || ![window.firstResponder conformsToProtocol:@protocol(NSTextInputClient)]) return NO;
    id<NSTextInputClient> client = (id<NSTextInputClient>)window.firstResponder;
    NSRange selected = client.selectedRange;
    if (selected.location == NSNotFound || client.hasMarkedText) return NO;
    NSPoint point = [client firstRectForCharacterRange:NSMakeRange(selected.location, 0) actualRange:NULL].origin;
    NSRect frame = [formula.superlayer convertRect:formula.frame toLayer:view.layer];
    if (view.layer.geometryFlipped != view.isFlipped) frame.origin.y = NSHeight(view.bounds) - NSMaxY(frame);
    frame = [window convertRectToScreen:[view convertRect:frame toView:nil]];
    return NSPointInRect(point, NSInsetRect(frame, -2, -2));
}

// The editor's objects in reading order, or nil when the window is not the formula editor.
static NSArray<NSDictionary *> *FormulaEntries(NSWindow *window, NSView *view, CALayer *form) {
    CALayer *formula = AXBInternalFormChild(form, @"vFormula"), *commands = AXBInternalFormChild(form, @"LH_EnCm"), *ok = AXBInternalFormChild(form, @"bOK");
    if (!formula || !commands || !ok) return nil;
    NSMutableArray *entries = [NSMutableArray new];
    CALayer *layer;
    if ((layer = AXBInternalFormChild(form, @"helpString"))) [entries addObject:Entry(@"help", layer, NSAccessibilityStaticTextRole, nil, 0)];
    // Each list follows the menu that chooses what it shows.
    NSArray *lists = @[@[@"_ope_filter", @"Tables", @"lh_champ", @"fields/", @"Fields"], @[@"_ope_theme", @"Kind of operators", @"LH_Operateur", @"operators/", @"Operators"],
                       @[@"_ope_routine", @"Order of commands", @"LH_EnCm", @"commands/", @"Commands"]];
    for (NSArray *list in lists) {
        if ((layer = AXBInternalFormChild(form, list[0]))) [entries addObject:Entry([list[3] stringByAppendingString:@"show"], layer, NSAccessibilityPopUpButtonRole, Localized(list[1]), PopupInset)];
        if ((layer = AXBInternalFormChild(form, list[2]))) [entries addObjectsFromArray:ListEntries(layer, list[3], Localized(list[4]))];
    }
    NSMutableDictionary *field = Entry(@"formula", formula, NSAccessibilityTextFieldRole, Localized(@"Formula"), 0);
    field[@"editable"] = @YES;
    // The formula's box lies within its layer's margins, wider on the right and below; a click
    // in the right margin would miss it.
    NSRect bounds = formula.bounds;
    if (NSWidth(bounds) > 60 && NSHeight(bounds) > 36) field[@"area"] = [NSValue valueWithRect:NSMakeRect(8, 21, NSWidth(bounds) - 30, NSHeight(bounds) - 28)];
    // Holding 4D's caret, it is the focused element, so typing is echoed as in any field.
    if (HoldsCaret(window, view, formula)) field[@"caret"] = field[@"focused"] = @YES;
    [entries addObject:field];
    if ((layer = AXBInternalFormChild(form, @"vMessage"))) [entries addObject:Entry(@"message", layer, NSAccessibilityStaticTextRole, nil, 0)];
    for (NSString *name in @[@"bLoad", @"bSave", @"bCancel", @"bOK"])
        if ((layer = AXBInternalFormChild(form, name))) [entries addObject:Entry(name, layer, NSAccessibilityButtonRole, nil, ButtonInset)];
    return entries;
}

static NSMapTable<NSWindow *, AXBInternalFormOverlay *> *Overlays;
static id KeyObserver, CloseObserver, UpdateObserver;

static void RemoveOverlay(NSWindow *window, AXBInternalFormOverlay *overlay) {
    if (!overlay) return;
    [overlay releaseFocus];
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
}

BOOL AXBFormulaEditorRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    CALayer *form = view ? AXBInternalFormContext(view) : nil;
    NSArray *entries = form ? FormulaEntries(window, view, form) : nil;
    if (!entries) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:@"axb/formula/"];
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
                                                              usingBlock:^(NSNotification *note) { AXBFormulaEditorRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
    // A click or Tab moves the caret into or out of the formula without drawing any text, and a
    // caret move within it draws none either: check after each window update.
    UpdateObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSWindow *window = note.object;
        AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
        AXBInternalFormElement *formula = overlay.elements[@"formula"];
        if (!formula || !window.isKeyWindow) return;
        BOOL caret = formula.layer && HoldsCaret(window, overlay.formView, formula.layer);
        if (caret != formula.caret) AXBFormulaEditorRefreshWindow(window);
        else [formula noticeCaret];
    }];
}

void AXBFormulaEditorInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(@"formula", FormulaNames(), ^(CALayer *layer) {
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBFormulaEditorRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBFormulaEditorShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(@"formula", nil, nil);
    for (id observer in @[KeyObserver ?: NSNull.null, CloseObserver ?: NSNull.null, UpdateObserver ?: NSNull.null])
        if (observer != NSNull.null) [NSNotificationCenter.defaultCenter removeObserver:observer];
    KeyObserver = CloseObserver = UpdateObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBFormulaEditorEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
