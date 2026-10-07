#import "GenericForms.h"
#import "InternalForms.h"
#import "DrawnText.h"

// The project's forms, by name ("Name" or "table/Name"): each object's type, title, help tip,
// placeholder, enterability and size, as its definition states them.
static NSDictionary<NSString *, NSDictionary<NSString *, NSDictionary *> *> *Forms;
// The forms that hold each object name, to match a window's objects quickly.
static NSDictionary<NSString *, NSArray<NSString *> *> *FormsByObject;
static NSMapTable<NSWindow *, AXBInternalFormOverlay *> *Overlays;
static NSMapTable<NSWindow *, NSDictionary *> *Matches;
static dispatch_source_t RefreshTimer;
static id KeyObserver, CloseObserver;

static NSDictionary *ReadDefinition(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    // 4D writes form definitions with a byte order mark.
    if (data.length >= 3 && !memcmp(data.bytes, "\xEF\xBB\xBF", 3)) data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

// The parts of a definition the provider uses, for every object on every page.
static NSDictionary<NSString *, NSDictionary *> *ObjectsOf(NSDictionary *definition) {
    NSMutableDictionary *objects = [NSMutableDictionary new];
    NSArray *pages = [definition[@"pages"] isKindOfClass:NSArray.class] ? definition[@"pages"] : @[];
    [pages enumerateObjectsUsingBlock:^(id page, NSUInteger number, BOOL *stop) {
        (void)stop;
        NSDictionary *items = [page isKindOfClass:NSDictionary.class] ? page[@"objects"] : nil;
        if (![items isKindOfClass:NSDictionary.class]) return;
        [items enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *object, BOOL *inner) {
            (void)inner;
            if (![object isKindOfClass:NSDictionary.class]) return;
            NSMutableDictionary *info = [@{@"page": @(number)} mutableCopy];
            for (NSString *key in @[@"type", @"text", @"tooltip", @"placeholder", @"enterable", @"width", @"height", @"style"])
                if (object[key] && ![object[key] isKindOfClass:NSDictionary.class] && ![object[key] isKindOfClass:NSArray.class]) info[key] = object[key];
            objects[name] = info;
        }];
    }];
    return objects;
}

// Index every form definition under a project's Sources folder.
static void LoadIndex(NSURL *sources, void (^done)(NSDictionary *, NSDictionary *)) {
    NSMutableDictionary *forms = [NSMutableDictionary new];
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *projectForms = [sources URLByAppendingPathComponent:@"Forms"];
    for (NSURL *folder in [files contentsOfDirectoryAtURL:projectForms includingPropertiesForKeys:nil options:0 error:nil] ?: @[]) {
        NSDictionary *definition = ReadDefinition([folder URLByAppendingPathComponent:@"form.4DForm"]);
        if (definition) forms[folder.lastPathComponent] = ObjectsOf(definition);
    }
    NSURL *tableForms = [sources URLByAppendingPathComponent:@"TableForms"];
    for (NSURL *table in [files contentsOfDirectoryAtURL:tableForms includingPropertiesForKeys:nil options:0 error:nil] ?: @[])
        for (NSURL *folder in [files contentsOfDirectoryAtURL:table includingPropertiesForKeys:nil options:0 error:nil] ?: @[]) {
            NSDictionary *definition = ReadDefinition([folder URLByAppendingPathComponent:@"form.4DForm"]);
            if (definition) forms[[NSString stringWithFormat:@"%@/%@", table.lastPathComponent, folder.lastPathComponent]] = ObjectsOf(definition);
        }
    NSMutableDictionary<NSString *, NSMutableArray *> *byObject = [NSMutableDictionary new];
    [forms enumerateKeysAndObjectsUsingBlock:^(NSString *form, NSDictionary *objects, BOOL *stop) {
        (void)stop;
        for (NSString *name in objects) {
            if (!byObject[name]) byObject[name] = [NSMutableArray new];
            [byObject[name] addObject:form];
        }
    }];
    done(forms, byObject);
}

// The form whose objects the window draws: the one holding most of its object layers. Too few,
// or too ambiguous a match, leaves the window untouched.
static NSString *MatchForm(NSArray<NSString *> *names) {
    if (names.count < 3 || !FormsByObject) return nil;
    NSCountedSet *votes = [NSCountedSet new];
    for (NSString *name in names) for (NSString *form in FormsByObject[name] ?: @[]) [votes addObject:form];
    NSString *best = nil;
    NSUInteger top = 0, second = 0;
    for (NSString *form in votes) {
        NSUInteger count = [votes countForObject:form];
        if (count > top) { second = top; top = count; best = form; }
        else if (count > second) second = count;
    }
    if (!best || top < 3 || top * 10 < names.count * 8 || top == second) return nil;
    return best;
}

static NSString *Plain(id text) {
    // Localized and computed titles (":xliff:…", "<variable>") are not plain text.
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length && ![trimmed hasPrefix:@":"] && ![trimmed hasPrefix:@"<"] ? trimmed : nil;
}

// The object's own rectangle within its layer, in the layer's points from its bottom left.
// 4D draws an object with a margin of up to 10 points on its leading and top edges, and the
// rest of the extra size on its trailing and bottom edges (an input's is wider there).
static NSRect ObjectArea(CALayer *layer, NSDictionary *info) {
    CGFloat width = [info[@"width"] doubleValue], height = [info[@"height"] doubleValue];
    NSRect bounds = layer.bounds;
    if (width <= 0 || height <= 0 || width > NSWidth(bounds) || height > NSHeight(bounds)) return bounds;
    CGFloat leading = MIN(10, (NSWidth(bounds) - width) / 2), top = MIN(10, (NSHeight(bounds) - height) / 2);
    return NSMakeRect(leading, NSHeight(bounds) - top - height, width, height);
}

// Whether a standard checkbox or radio button is on, from the image 4D drew: macOS fills an
// on box or button with the accent color. Unknown (nil) when the accent color is a gray, or
// the image cannot be read.
static NSNumber *ReadDrawnState(CALayer *layer, CGFloat inset);
static NSMapTable<CALayer *, NSDictionary *> *States;

// Read once for each image 4D draws: forms are refreshed a few times a second.
static NSNumber *DrawnState(CALayer *layer, CGFloat inset) {
    id contents = layer.contents;
    if (!States) States = [NSMapTable weakToStrongObjectsMapTable];
    NSDictionary *cached = [States objectForKey:layer];
    if (cached && cached[@"contents"] == contents) return cached[@"state"] == NSNull.null ? nil : cached[@"state"];
    NSNumber *state = ReadDrawnState(layer, inset);
    if (contents) [States setObject:@{@"contents": contents, @"state": state ?: NSNull.null} forKey:layer];
    return state;
}

static NSNumber *ReadDrawnState(CALayer *layer, CGFloat inset) {
    NSColor *accent = [NSColor.controlAccentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!accent || accent.saturationComponent < 0.3) return nil;
    id contents = layer.contents;
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return nil;
    CGImageRef image = (__bridge CGImageRef)contents;
    CGFloat height = NSHeight(layer.bounds), scale = height > 0 ? CGImageGetHeight(image) / height : 0;
    if (scale <= 0) return nil;
    // The box sits at the object's leading edge, centered vertically: sample its inner square.
    CGRect box = CGRectMake((inset + 3) * scale, (height / 2 - 4) * scale, 9 * scale, 8 * scale);
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
    NSUInteger colored = 0;
    for (size_t i = 0; i < width * rows; i++) {
        double r = bytes[i * 4], g = bytes[i * 4 + 1], b = bytes[i * 4 + 2], high = MAX(r, MAX(g, b)), low = MIN(r, MIN(g, b));
        if (bytes[i * 4 + 3] > 128 && high > 60 && (high - low) / high > 0.35) colored++;
    }
    return @(colored * 4 > width * rows);
}

static NSArray<NSDictionary *> *FormEntries(CALayer *form, NSDictionary<NSString *, NSDictionary *> *objects) {
    NSMutableArray<CALayer *> *layers = [NSMutableArray new];
    for (CALayer *layer in form.sublayers)
        if (layer.name && objects[layer.name] && !layer.hidden && NSIntersectsRect(layer.frame, form.bounds)) [layers addObject:layer];
    // Reading order: top to bottom, then left to right, by each object's own frame within its
    // layer's margin; the form's origin is at its bottom.
    BOOL flipped = form.geometryFlipped;
    NSRect (^object)(CALayer *) = ^NSRect(CALayer *layer) {
        NSRect area = ObjectArea(layer, objects[layer.name]);
        return NSOffsetRect(area, NSMinX(layer.frame), NSMinY(layer.frame));
    };
    [layers sortUsingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
        NSRect ra = object(a), rb = object(b);
        CGFloat ta = flipped ? -NSMinY(ra) : NSMaxY(ra), tb = flipped ? -NSMinY(rb) : NSMaxY(rb);
        if (fabs(ta - tb) > 8) return ta > tb ? NSOrderedAscending : NSOrderedDescending;
        return NSMinX(ra) < NSMinX(rb) ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray *entries = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *captions = [NSMutableArray new];
    for (CALayer *layer in layers) {
        NSDictionary *info = objects[layer.name];
        NSString *type = info[@"type"];
        NSString *drawn = [AXBDrawnTextForLayer(layer) componentsJoinedByString:@" "];
        NSString *title = Plain(drawn) ?: Plain(info[@"text"]);
        NSString *help = Plain(info[@"tooltip"]);
        NSRect area = ObjectArea(layer, info);
        NSMutableDictionary *entry = [@{@"key": layer.name, @"layer": layer} mutableCopy];
        if (!NSEqualRects(area, layer.bounds)) entry[@"area"] = [NSValue valueWithRect:area];
        if ([@[@"button", @"pictureButton"] containsObject:type]) {
            if (!title && !help) continue; // An unlabelled button cannot be named.
            entry[@"role"] = NSAccessibilityButtonRole;
            if (!Plain(drawn)) entry[@"label"] = title ?: help;
        } else if ([type isEqual:@"checkbox"] || [type isEqual:@"radio"]) {
            if (!title && !help) continue;
            entry[@"role"] = [type isEqual:@"radio"] ? NSAccessibilityRadioButtonRole : NSAccessibilityCheckBoxRole;
            entry[@"label"] = title ?: help;
            // Only the standard look draws its state as macOS does.
            if (!info[@"style"] || [info[@"style"] isEqual:@"regular"]) {
                NSNumber *state = DrawnState(layer, NSMinX(area));
                if (state) entry[@"checked"] = state;
            }
        } else if ([type isEqual:@"text"] || [type isEqual:@"groupBox"]) {
            if (!title) continue;
            entry[@"role"] = NSAccessibilityStaticTextRole;
            entry[@"text"] = title;
            [captions addObject:@{@"layer": layer, @"text": title}];
        } else if ([type isEqual:@"dropdown"]) {
            entry[@"role"] = NSAccessibilityPopUpButtonRole;
            if (help) entry[@"label"] = help;
        } else if ([type isEqual:@"input"] || [type isEqual:@"combo"]) {
            entry[@"role"] = NSAccessibilityTextFieldRole;
            entry[@"editable"] = @(![info[@"enterable"] isEqual:@NO]);
            if (Plain(info[@"placeholder"])) entry[@"placeholders"] = [NSSet setWithObject:Plain(info[@"placeholder"])];
            entry[@"caption"] = @YES;
            if (help) entry[@"label"] = help;
        } else continue;
        [entries addObject:entry];
    }
    // An input is labelled by the caption on its left, or just above it, as it reads.
    for (NSMutableDictionary *entry in entries) {
        if (![entry[@"caption"] boolValue]) continue;
        [entry removeObjectForKey:@"caption"];
        if (entry[@"label"]) continue;
        NSRect field = object(entry[@"layer"]);
        NSString *best = nil;
        CGFloat distance = CGFLOAT_MAX;
        for (NSDictionary *caption in captions) {
            NSRect text = object(caption[@"layer"]);
            CGFloat gap = CGFLOAT_MAX;
            if (fabs(NSMidY(text) - NSMidY(field)) < 10 && NSMaxX(text) <= NSMinX(field) + 20) gap = NSMinX(field) - NSMaxX(text);
            else if (NSMinX(text) < NSMaxX(field) && NSMaxX(text) > NSMinX(field)) {
                CGFloat above = flipped ? NSMinY(field) - NSMaxY(text) : NSMinY(text) - NSMaxY(field);
                if (above >= -4 && above < 30) gap = above + 40;
            }
            if (gap >= -20 && gap < 120 && gap < distance) { distance = gap; best = caption[@"text"]; }
        }
        if (best) entry[@"label"] = [best stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@": "]];
    }
    return entries;
}

static void RemoveOverlay(NSWindow *window, AXBInternalFormOverlay *overlay) {
    [Matches removeObjectForKey:window];
    if (!overlay) return;
    [overlay releaseFocus];
    [overlay removeFromSuperview];
    [Overlays removeObjectForKey:window];
}

BOOL AXBGenericFormsRefreshWindow(NSWindow *window) {
    if (!window || !Overlays || !Forms) return NO;
    AXBInternalFormOverlay *overlay = [Overlays objectForKey:window];
    NSView *view = window.isVisible ? AXBInternalFormView(window) : nil;
    CALayer *form = view ? AXBInternalFormContext(view) : nil;
    if (!form) { RemoveOverlay(window, overlay); return NO; }
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (CALayer *layer in form.sublayers) if (layer.name) [names addObject:layer.name];
    // Match once for each set of objects the window shows.
    NSString *signature = [names componentsJoinedByString:@"\n"];
    NSDictionary *match = [Matches objectForKey:window];
    if (![match[@"signature"] isEqual:signature]) {
        NSString *name = MatchForm(names);
        match = @{@"signature": signature, @"form": name ?: @""};
        [Matches setObject:match forKey:window];
    }
    NSDictionary *objects = [match[@"form"] length] ? Forms[match[@"form"]] : nil;
    NSArray *entries = objects ? FormEntries(form, objects) : nil;
    if (!entries.count) { RemoveOverlay(window, overlay); return NO; }
    BOOL created = NO;
    if (!overlay || overlay.formView != view) {
        RemoveOverlay(window, overlay);
        [Matches setObject:match forKey:window];
        overlay = [[AXBInternalFormOverlay alloc] initWithFormView:view prefix:@"axb/form/"];
        created = YES;
    }
    if (![overlay updateWithEntries:entries]) { RemoveOverlay(window, overlay); return NO; }
    if (created) {
        [view addSubview:overlay];
        [Overlays setObject:overlay forKey:window];
    }
    return YES;
}

static void RefreshVisibleWindows(void) {
    for (NSWindow *window in NSApp.windows) if (window.isVisible || [Overlays objectForKey:window]) AXBGenericFormsRefreshWindow(window);
}

static void ObserveWindows(void) {
    if (KeyObserver) return;
    KeyObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil
                                                              usingBlock:^(NSNotification *note) { AXBGenericFormsRefreshWindow(note.object); }];
    CloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { RemoveOverlay(note.object, [Overlays objectForKey:note.object]); }];
}

// Forms redraw their objects as their data change; refresh the open windows a few times a
// second, through every run-loop mode, since 4D's own loops do not drain the main queue.
static void StartRefreshing(void) {
    if (RefreshTimer) return;
    RefreshTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(RefreshTimer, DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC, 100 * NSEC_PER_MSEC);
    __block BOOL pending = NO;
    dispatch_source_set_event_handler(RefreshTimer, ^{
        if (pending) return;
        CFRunLoopRef main = CFRunLoopGetMain();
        CFArrayRef modes = CFRunLoopCopyAllModes(main);
        if (!modes) return;
        pending = YES;
        CFRunLoopPerformBlock(main, modes, ^{ RefreshVisibleWindows(); pending = NO; });
        CFRelease(modes);
        CFRunLoopWakeUp(main);
    });
    dispatch_resume(RefreshTimer);
}

void AXBGenericFormsInitialize(NSString *projectFile) {
    if (Overlays || !projectFile.length) return;
    if (!AXBDrawnTextInitialize()) return;
    Overlays = [NSMapTable weakToStrongObjectsMapTable];
    Matches = [NSMapTable weakToStrongObjectsMapTable];
    // 4D reports the project folder as an HFS path (volume:folder:…:Project:).
    NSString *path = projectFile;
    if (![path hasPrefix:@"/"]) {
        NSMutableArray<NSString *> *parts = [[path componentsSeparatedByString:@":"] mutableCopy];
        NSString *volume = parts.firstObject;
        [parts removeObjectAtIndex:0];
        NSString *mounted = [@"/Volumes" stringByAppendingPathComponent:volume];
        BOOL boot = ![NSFileManager.defaultManager fileExistsAtPath:mounted] || [[mounted stringByResolvingSymlinksInPath] isEqual:@"/"];
        path = [(boot ? @"/" : mounted) stringByAppendingPathComponent:[parts componentsJoinedByString:@"/"]];
    }
    BOOL folder = NO;
    [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&folder];
    NSURL *project = folder ? [NSURL fileURLWithPath:path isDirectory:YES] : [[NSURL fileURLWithPath:path] URLByDeletingLastPathComponent];
    NSURL *sources = [project URLByAppendingPathComponent:@"Sources"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LoadIndex(sources, ^(NSDictionary *forms, NSDictionary *byObject) {
            dispatch_async(dispatch_get_main_queue(), ^{ FormsByObject = byObject; Forms = forms; });
            // The main queue can be held by a modal loop; publish the index through every mode too.
            CFRunLoopRef main = CFRunLoopGetMain();
            CFArrayRef modes = CFRunLoopCopyAllModes(main);
            if (modes) {
                CFRunLoopPerformBlock(main, modes, ^{ FormsByObject = byObject; Forms = forms; });
                CFRelease(modes);
                CFRunLoopWakeUp(main);
            }
        });
    });
    ObserveWindows();
    StartRefreshing();
}

void AXBGenericFormsShutdown(void) {
    if (!Overlays) return;
    if (RefreshTimer) dispatch_source_cancel(RefreshTimer);
    RefreshTimer = nil;
    if (KeyObserver) [NSNotificationCenter.defaultCenter removeObserver:KeyObserver];
    if (CloseObserver) [NSNotificationCenter.defaultCenter removeObserver:CloseObserver];
    KeyObserver = CloseObserver = nil;
    for (NSWindow *window in Overlays.keyEnumerator.allObjects) RemoveOverlay(window, [Overlays objectForKey:window]);
    Overlays = nil; Matches = nil; Forms = nil; FormsByObject = nil; States = nil;
}

void AXBGenericFormsEnableForTesting(NSDictionary<NSString *, NSDictionary *> *definitions) {
    if (!Overlays) Overlays = [NSMapTable weakToStrongObjectsMapTable];
    if (!Matches) Matches = [NSMapTable weakToStrongObjectsMapTable];
    NSMutableDictionary *forms = [NSMutableDictionary new];
    [definitions enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *definition, BOOL *stop) { (void)stop; forms[name] = ObjectsOf(definition); }];
    NSMutableDictionary<NSString *, NSMutableArray *> *byObject = [NSMutableDictionary new];
    [forms enumerateKeysAndObjectsUsingBlock:^(NSString *form, NSDictionary *objects, BOOL *stop) {
        (void)stop;
        for (NSString *name in objects) { if (!byObject[name]) byObject[name] = [NSMutableArray new]; [byObject[name] addObject:form]; }
    }];
    Forms = forms; FormsByObject = byObject;
    ObserveWindows();
}
