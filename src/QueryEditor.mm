#import "QueryEditor.h"
#import "InternalForms.h"
#import "DrawnText.h"

// 4D draws each object into a layer larger than the object by a margin that depends on
// its kind; clicks and frames use the object itself.
static const CGFloat InputInset = 16.5, DropdownInset = 10, ButtonInset = 5;

static NSString *Localized(NSString *key) {
    return [[NSBundle bundleForClass:AXBInternalFormOverlay.class] localizedStringForKey:key value:key table:@"AccessibilityBridge"];
}

// The objects the Query editor's form and its line form draw text into, so a change
// in any of them refreshes the window.
static NSSet<NSString *> *QueryNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"bottom.b.query", @"bottom.b.cancel", @"top.button.destination", @"top.button.recent", @"target", @"operator",
                                      @"popup.0", @"popup.3", @"popup.4", @"box.1", @"box.3", @"box.2.1", @"box.2.2", @"error.message", @"formula", @"table.list"]];
    });
    return names;
}

// The placeholders 4D's Query editor draws in an empty value, in 4D's own language, read
// from the strings of its internal runtime component.
static NSSet<NSString *> *Placeholders(void) {
    static NSSet *placeholders;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *found = [NSMutableSet new];
        NSString *resources = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Internal Components/runtime.4dbase/Resources"];
        NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
        for (NSString *candidate in @[language, @"en"]) {
            NSString *folder = [resources stringByAppendingPathComponent:[candidate stringByAppendingString:@".lproj"]];
            for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
                if (![file hasPrefix:@"Query"] || ![file.pathExtension isEqual:@"xlf"]) continue;
                NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:file]] options:0 error:nil];
                for (NSXMLElement *unit in [document nodesForXPath:@"//*[local-name()='trans-unit']" error:nil]) {
                    if (![[unit attributeForName:@"resname"].stringValue hasPrefix:@"Placeholder_"]) continue;
                    NSString *target = [[unit elementsForName:@"target"].firstObject stringValue];
                    if (target.length) [found addObject:target];
                }
            }
            if (found.count) break;
        }
        // 4D's English placeholders, should its strings be unavailable.
        placeholders = found.count ? found : [NSSet setWithArray:@[@"Value", @"Values separated by semicolons", @"Values separated by spaces", @"Size", @"Weight",
                                                                    @"Date", @"Number", @"Time", @"Number separated by semicolons"]];
    });
    return placeholders;
}

static NSMutableDictionary *Entry(NSString *key, CALayer *layer, NSString *role, NSString *label, CGFloat inset) {
    NSMutableDictionary *entry = [@{@"key": key, @"layer": layer, @"role": role, @"inset": @(inset)} mutableCopy];
    if (label) entry[@"label"] = label;
    return entry;
}

// The criterion lines, top to bottom.
static NSArray<CALayer *> *QueryLines(CALayer *form) {
    NSMutableArray<CALayer *> *lines = [NSMutableArray new];
    for (CALayer *layer in form.sublayers)
        if ([layer.name hasPrefix:@"queryLine"] && !layer.hidden && AXBInternalSubformContext(layer)) [lines addObject:layer];
    [lines sortUsingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
        CGFloat ya = NSMaxY(a.frame), yb = NSMaxY(b.frame);
        BOOL flipped = form.geometryFlipped;
        if (ya == yb) return NSOrderedSame;
        return (ya > yb) != flipped ? NSOrderedAscending : NSOrderedDescending;
    }];
    return lines;
}

// The editor's objects in reading order, or nil when the window is not the Query editor.
static NSArray<NSDictionary *> *QueryEntries(CALayer *form) {
    CALayer *query = AXBInternalFormChild(form, @"bottom.b.query"), *cancel = AXBInternalFormChild(form, @"bottom.b.cancel");
    NSArray<CALayer *> *lines = QueryLines(form);
    if (!query || !cancel || !lines.count) return nil;
    NSMutableArray *entries = [NSMutableArray new];
    CALayer *layer;
    if ((layer = AXBInternalFormChild(form, @"top.button.action"))) [entries addObject:Entry(@"options", layer, NSAccessibilityPopUpButtonRole, Localized(@"Query options"), ButtonInset)];
    if ((layer = AXBInternalFormChild(form, @"top.button.recent"))) [entries addObject:Entry(@"recent", layer, NSAccessibilityButtonRole, nil, ButtonInset)];
    if ((layer = AXBInternalFormChild(form, @"top.button.destination"))) [entries addObject:Entry(@"destination", layer, NSAccessibilityPopUpButtonRole, Localized(@"Destination"), ButtonInset)];
    if ((layer = AXBInternalFormChild(form, @"reset"))) [entries addObject:Entry(@"reset", layer, NSAccessibilityButtonRole, Localized(@"Reset"), ButtonInset)];
    [lines enumerateObjectsUsingBlock:^(CALayer *line, NSUInteger index, BOOL *stop) {
        (void)stop;
        CALayer *context = AXBInternalSubformContext(line), *part;
        NSString *prefix = [NSString stringWithFormat:@"line%lu/", (unsigned long)index + 1];
        // Each object, with its label, as the line reads from left to right.
        NSArray *objects = @[
            @[@"operator", NSAccessibilityPopUpButtonRole, @"Conjunction", @(DropdownInset)],
            @[@"target", NSAccessibilityPopUpButtonRole, @"Field", @(InputInset)],
            @[@"formula", NSAccessibilityTextFieldRole, @"Formula", @(InputInset)],
            @[@"popup.0", NSAccessibilityPopUpButtonRole, @"Comparison", @(DropdownInset)],
            @[@"box.1", NSAccessibilityTextFieldRole, @"Value", @(InputInset)],
            @[@"box.3", NSAccessibilityTextFieldRole, @"Value", @(InputInset)],
            @[@"popup.4", NSAccessibilityPopUpButtonRole, @"Value", @(DropdownInset)],
            @[@"popup.3", NSAccessibilityPopUpButtonRole, @"Value", @(DropdownInset)],
            @[@"box.2.1", NSAccessibilityTextFieldRole, @"From", @(InputInset)],
            @[@"box.2.2", NSAccessibilityTextFieldRole, @"To", @(InputInset)],
            @[@"b.edit", NSAccessibilityButtonRole, @"Edit list", @(ButtonInset)],
            @[@"3D Button3", NSAccessibilityButtonRole, @"Fields", @(ButtonInset)],
            @[@"3D Button4", NSAccessibilityButtonRole, @"Operators", @(ButtonInset)],
            @[@"3D Button5", NSAccessibilityButtonRole, @"Commands", @(ButtonInset)],
            @[@"error.message", NSAccessibilityStaticTextRole, @"", @0],
            @[@"delete", NSAccessibilityButtonRole, @"Remove line", @(ButtonInset)],
            @[@"add", NSAccessibilityButtonRole, @"Add line", @(ButtonInset)],
        ];
        for (NSArray *object in objects) {
            if (!(part = AXBInternalFormChild(context, object[0]))) continue;
            NSString *label = [object[2] length] ? Localized(object[2]) : nil;
            NSMutableDictionary *entry = Entry([prefix stringByAppendingString:object[0]], part, object[1], label, [object[3] doubleValue]);
            // The field is chosen from the list its arrow opens: one control, as it reads.
            CALayer *arrow = AXBInternalFormChild(context, @"b.field");
            if ([object[0] isEqual:@"target"] && arrow) { entry[@"press"] = arrow; entry[@"pressInset"] = @(ButtonInset); }
            if ([object[1] isEqual:NSAccessibilityTextFieldRole]) {
                entry[@"editable"] = @YES;
                entry[@"placeholders"] = Placeholders();
            }
            [entries addObject:entry];
        }
    }];
    [entries addObject:Entry(@"cancel", cancel, NSAccessibilityButtonRole, nil, ButtonInset)];
    [entries addObject:Entry(@"query", query, NSAccessibilityButtonRole, nil, ButtonInset)];
    return entries;
}

// The field chooser that the line's field button opens: a list of the table and its fields,
// drawn as a whole into one layer. Each item is published as a button over its own line,
// found from where its text is drawn; pressing it clicks that line, as the mouse chooses.
static NSArray<NSDictionary *> *ChooserEntries(CALayer *form) {
    CALayer *list = AXBInternalFormChild(form, @"table.list");
    if (!list || !AXBInternalFormChild(form, @"b.done") || AXBInternalFormChild(form, @"bottom.b.query")) return nil;
    NSArray *items = AXBInternalListItems(list, @"item/", NSAccessibilityButtonRole);
    if (!items.count) return nil;
    // The window holds this one list, whose fields stay its own elements: VoiceOver, which starts
    // on the current field, cannot move on from a line nested in a list in this window. The list's
    // scroll bar pages through a table longer than its box.
    NSMutableArray *entries = [NSMutableArray new];
    CALayer *scroller = AXBInternalFormChild(list, @"vertical_scrollbar");
    for (NSDictionary *item in items) {
        NSMutableDictionary *entry = [item mutableCopy];
        if (scroller) entry[@"list"] = @"scroll";
        [entries addObject:entry];
    }
    if (scroller) [entries addObject:Entry(@"scroll", scroller, NSAccessibilityScrollBarRole, Localized(@"Fields"), 0)];
    return entries;
}

static NSMapTable<NSWindow *, AXBInternalFormOverlay *> *Overlays;
static id KeyObserver, CloseObserver;

// The criterion's field that the open field list chooses for.
static __weak AXBInternalFormElement *ChooserField;

static void RemoveOverlay(NSWindow *window, AXBInternalFormOverlay *overlay) {
    if (!overlay) return;
    BOOL chooser = [overlay.identifierPrefix hasSuffix:@"/fields/"];
    BOOL focused = [overlay.elements.allValues containsObject:NSApp.accessibilityApplicationFocusedUIElement];
    [overlay releaseFocus];
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
    // Closing the field list leaves assistive focus on nothing: return it to the field it chose for,
    // as AppKit returns focus from a closed pop-up, so VoiceOver goes on from there.
    AXBInternalFormElement *field = ChooserField;
    if (!chooser || !focused || !field.isAccessibilityElement) return;
    ChooserField = nil;
    NSApp.accessibilityApplicationFocusedUIElement = field;
    NSAccessibilityPostNotification(field, NSAccessibilityFocusedUIElementChangedNotification);
}

BOOL AXBQueryEditorRefreshWindow(NSWindow *window) {
    if (!window || !Overlays) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = AXBInternalFormView(window);
    CALayer *form = view ? AXBInternalFormContext(view) : nil;
    NSArray *entries = form ? (QueryEntries(form) ?: ChooserEntries(form)) : nil;
    if (!entries) {
        RemoveOverlay(window, overlay);
        return NO;
    }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:AXBInternalFormChild(form, @"table.list") ? @"axb/query/fields/" : @"axb/query/"];
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
    if (created && [overlay.identifierPrefix hasSuffix:@"/fields/"]) {
        // The chooser opens beside the field it chooses for, and starts on that field: move
        // assistive focus there, since the chooser's window does not become key.
        AXBInternalFormElement *field = nil;
        CGFloat best = CGFLOAT_MAX;
        for (NSWindow *other in Overlays.keyEnumerator.allObjects)
            for (AXBInternalFormElement *element in [Overlays objectForKey:other].elements.allValues) {
                if (![element.key hasSuffix:@"/target"]) continue;
                NSRect frame = element.screenFrame;
                CGFloat distance = hypot(NSMinX(frame) - NSMinX(window.frame), NSMinY(frame) - NSMaxY(window.frame));
                if (distance < best) { best = distance; field = element; }
            }
        NSString *name = [field.currentText componentsSeparatedByString:@"]"].lastObject;
        AXBInternalFormElement *focus = name.length ? overlay.elements[[@"item/" stringByAppendingString:name]] : nil;
        focus = focus ?: overlay.elements[overlay.order.firstObject];
        ChooserField = field;
        if (focus) {
            overlay.placedFocus = focus;
            NSApp.accessibilityApplicationFocusedUIElement = focus;
            NSAccessibilityPostNotification(focus, NSAccessibilityFocusedUIElementChangedNotification);
        }
    }
    return YES;
}

// The window whose form draws this layer: a published overlay first, then any open window.
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
                                                              usingBlock:^(NSNotification *note) { AXBQueryEditorRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
}

void AXBQueryEditorInitialize(void) {
    if (Overlays) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    AXBDrawnTextSetObserver(@"query", QueryNames(), ^(CALayer *layer) {
        NSWindow *window = WindowForLayer(layer);
        if (window) AXBQueryEditorRefreshWindow(window);
    });
    ObserveWindows();
}

void AXBQueryEditorShutdown(void) {
    if (!Overlays) return;
    AXBDrawnTextSetObserver(@"query", nil, nil);
    if (KeyObserver) [NSNotificationCenter.defaultCenter removeObserver:KeyObserver];
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    KeyObserver = CloseObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil;
}

void AXBQueryEditorEnableForTesting(void) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    ObserveWindows();
}
