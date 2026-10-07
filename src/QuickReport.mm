#import "QuickReport.h"
#import "InternalForms.h"
#import "DrawnText.h"

static const CGFloat InputInset = 16.5;

static NSString *Localized(NSString *key) {
    return [[NSBundle bundleForClass:AXBInternalFormOverlay.class] localizedStringForKey:key value:key table:@"AccessibilityBridge"];
}

// The objects the editor draws text into, so a change in any of them refreshes the window.
static NSSet<NSString *> *ReportNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"nqr", @"status.records", @"field.list", @"report.list", @"ok", @"cancel", @"toolbar.opened.run", @"toolbar.opened.fields",
                                      @"file", @"printer", @"html", @"Text", @"Text1"]];
    });
    return names;
}

static NSMutableDictionary *Entry(NSString *key, CALayer *layer, NSString *role, NSString *label, CGFloat inset) {
    NSMutableDictionary *entry = [@{@"key": key, @"layer": layer, @"role": role, @"inset": @(inset)} mutableCopy];
    if (label) entry[@"label"] = label;
    return entry;
}

// The toolbar's buttons, by their drawn titles, from left to right; two sit in groups.
static void AddToolbar(CALayer *form, NSMutableArray *entries) {
    CALayer *data = AXBInternalSubformContext(AXBInternalFormChild(form, @"toolbar.opened.data") ?: [CALayer layer]);
    CALayer *headers = AXBInternalSubformContext(AXBInternalFormChild(form, @"toolbar.opened.h&f") ?: [CALayer layer]);
    NSArray *buttons = @[
        @[form, @"toolbar.opened.new", @"new"], @[form, @"toolbar.opened.open", @"open"], @[form, @"toolbar.opened.save", @"save"],
        @[form, @"toolbar.opened.destination", @"destination"], @[form, @"toolbar.opened.preview", @"preview"], @[form, @"toolbar.opened.run", @"run"],
        @[data ?: form, @"clear", @"clear"], @[data ?: form, @"reload", @"revert"],
        @[headers ?: form, @"header", @"header"], @[headers ?: form, @"footer", @"footer"],
        @[form, @"toolbar.opened.options", @"options"], @[form, @"toolbar.opened.fields", @"fields"]];
    for (NSArray *button in buttons) {
        CALayer *layer = AXBInternalFormChild(button[0], button[1]);
        if (layer) [entries addObject:Entry(button[2], layer, NSAccessibilityButtonRole, nil, 0)];
    }
}

// The report's columns, read from the titles drawn in its area: the row titles sit left of
// the first column's divider, and each column's title spans to the next column's.
static void AddColumns(CALayer *form, NSMutableArray *entries) {
    CALayer *report = AXBInternalSubformContext(AXBInternalFormChild(form, @"myQR") ?: [CALayer layer]);
    CALayer *area = report ? AXBInternalFormChild(report, @"nqr") : nil;
    CALayer *divider = AXBInternalFormChild(form, @"plus.line");
    if (!area) return;
    CGFloat left = divider ? [divider.superlayer convertRect:divider.frame toLayer:area].origin.x : 78;
    NSMutableArray<NSMutableDictionary *> *columns = [NSMutableArray new];
    for (NSMutableDictionary *item in AXBInternalListItems(area, @"column/", NSAccessibilityStaticTextRole) ?: @[])
        if ([item[@"originX"] doubleValue] >= left) [columns addObject:item];
    [columns sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"originX"] compare:b[@"originX"]]; }];
    [columns enumerateObjectsUsingBlock:^(NSMutableDictionary *column, NSUInteger index, BOOL *stop) {
        (void)stop;
        CGFloat x = [column[@"originX"] doubleValue] - 4;
        CGFloat next = index + 1 < columns.count ? [columns[index + 1][@"originX"] doubleValue] - 4 : x + 120;
        NSRect cell = [column[@"area"] rectValue];
        column[@"area"] = [NSValue valueWithRect:NSMakeRect(x, NSMinY(cell), MAX(next - x, 8), NSHeight(cell))];
        column[@"label"] = Localized(@"Report column");
        [entries addObject:column];
    }];
}

// The sheet that chooses the report's columns: available fields, added with a double click
// as with the mouse, the columns, selected with a click, and the buttons that move them.
static void AddFieldsSheet(CALayer *sheet, NSMutableArray *entries) {
    CALayer *layer;
    if ((layer = AXBInternalFormChild(sheet, @"field.search.box"))) {
        NSMutableDictionary *entry = Entry(@"sheet/search", layer, NSAccessibilityTextFieldRole, Localized(@"Search fields"), InputInset);
        entry[@"editable"] = @YES;
        [entries addObject:entry];
    }
    if ((layer = AXBInternalFormChild(sheet, @"action"))) [entries addObject:Entry(@"sheet/options", layer, NSAccessibilityPopUpButtonRole, Localized(@"Field options"), 0)];
    if ((layer = AXBInternalFormChild(sheet, @"field.list")))
        for (NSDictionary *item in AXBInternalListItems(layer, @"sheet/field/", NSAccessibilityButtonRole) ?: @[]) {
            NSMutableDictionary *entry = [item mutableCopy];
            entry[@"clicks"] = @2;
            [entries addObject:entry];
        }
    NSArray *moves = @[@[@"b.add.one", @"Add field"], @[@"b.add.all", @"Add all fields"], @[@"b.remove.one", @"Remove column"], @[@"b.remove.all", @"Remove all columns"]];
    for (NSArray *move in moves)
        if ((layer = AXBInternalFormChild(sheet, move[0]))) [entries addObject:Entry([@"sheet/" stringByAppendingString:move[0]], layer, NSAccessibilityButtonRole, Localized(move[1]), 0)];
    if ((layer = AXBInternalFormChild(sheet, @"report.list")))
        for (NSDictionary *item in AXBInternalListItems(layer, @"sheet/column/", NSAccessibilityButtonRole) ?: @[]) [entries addObject:item];
    if ((layer = AXBInternalFormChild(sheet, @"cancel"))) [entries addObject:Entry(@"sheet/cancel", layer, NSAccessibilityButtonRole, nil, 0)];
    if ((layer = AXBInternalFormChild(sheet, @"ok"))) [entries addObject:Entry(@"sheet/ok", layer, NSAccessibilityButtonRole, nil, 0)];
}

// The panel a toolbar button opens below the toolbar: its title and texts, its buttons, and
// Close. The destinations are radio buttons; 4D frames the chosen one.
static void AddPanel(CALayer *panel, NSString *name, NSMutableArray *entries) {
    NSRect bounds = panel.bounds;
    CALayer *chosen = AXBInternalFormChild(panel, @"select");
    NSSet *destinations = [NSSet setWithArray:@[@"file", @"printer", @"html"]];
    NSMutableArray<CALayer *> *layers = [NSMutableArray new];
    for (CALayer *layer in panel.sublayers) {
        // Objects parked outside the panel are not shown.
        if (layer.hidden || !NSIntersectsRect(layer.frame, bounds) || NSMinY(layer.frame) < 0) continue;
        if ([layer.name isEqual:@"close"] || [AXBDrawnTextForLayer(layer) count]) [layers addObject:layer];
    }
    // Reading order: top to bottom, then left to right.
    [layers sortUsingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
        if (fabs(NSMaxY(a.frame) - NSMaxY(b.frame)) > 8) return NSMaxY(a.frame) > NSMaxY(b.frame) ? NSOrderedAscending : NSOrderedDescending;
        return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (CALayer *layer in layers) {
        NSString *key = [NSString stringWithFormat:@"%@/%@", name, layer.name];
        if ([layer.name isEqual:@"close"]) [entries addObject:Entry(key, layer, NSAccessibilityButtonRole, Localized(@"Close"), 0)];
        else if ([destinations containsObject:layer.name]) {
            NSMutableDictionary *entry = Entry(key, layer, NSAccessibilityRadioButtonRole, nil, 0);
            entry[@"checked"] = @(chosen && !chosen.hidden && NSPointInRect(NSMakePoint(NSMidX(chosen.frame), NSMidY(chosen.frame)), layer.frame));
            [entries addObject:entry];
        } else if ([layer.name hasPrefix:@"Text"]) [entries addObject:Entry(key, layer, NSAccessibilityStaticTextRole, nil, 0)];
        else [entries addObject:Entry(key, layer, NSAccessibilityButtonRole, nil, 0)];
    }
}

// The editor's objects in reading order, or nil when the window is not the editor.
static NSArray<NSDictionary *> *ReportEntries(CALayer *form) {
    if (!AXBInternalFormChild(form, @"myQR") || !AXBInternalFormChild(form, @"toolbar.opened.run")) return nil;
    NSMutableArray *entries = [NSMutableArray new];
    CALayer *dial = AXBInternalFormChild(form, @"settings.dial");
    CALayer *sheet = dial && !dial.hidden ? AXBInternalSubformContext(dial) : nil;
    if (sheet && AXBInternalFormChild(sheet, @"field.list")) {
        // The sheet is modal; the editor behind it is masked.
        AddFieldsSheet(sheet, entries);
        return entries;
    }
    AddToolbar(form, entries);
    for (CALayer *layer in form.sublayers)
        if ([layer.name hasPrefix:@"tool."] && !layer.hidden && AXBInternalSubformContext(layer))
            AddPanel(AXBInternalSubformContext(layer), [layer.name substringFromIndex:5], entries);
    AddColumns(form, entries);
    CALayer *status = AXBInternalFormChild(form, @"status.records");
    if (status) [entries addObject:Entry(@"status", status, NSAccessibilityStaticTextRole, nil, 0)];
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

BOOL AXBQuickReportRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    CALayer *form = view ? AXBInternalFormContext(view) : nil;
    NSArray *entries = form ? ReportEntries(form) : nil;
    if (!entries) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:@"axb/report/"];
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
                                                              usingBlock:^(NSNotification *note) { AXBQuickReportRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
}

void AXBQuickReportInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(@"report", ReportNames(), ^(CALayer *layer) {
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBQuickReportRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBQuickReportShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(@"report", nil, nil);
    if (KeyObserver) [NSNotificationCenter.defaultCenter removeObserver:KeyObserver];
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    KeyObserver = CloseObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBQuickReportEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
