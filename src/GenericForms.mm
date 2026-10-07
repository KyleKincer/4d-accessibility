#import "GenericForms.h"
#import "InternalForms.h"
#import "DrawnText.h"
#include <vector>
#include <zlib.h>

// The project's forms, by name ("Name" or "table/Name"): each object's type, title, help tip,
// placeholder, enterability and size, as its definition states them.
static NSDictionary<NSString *, NSDictionary<NSString *, NSDictionary *> *> *Forms;
// Components' forms, by name, for the subforms that show them (such as 4D Widgets' pickers).
// They never match a window.
static NSDictionary<NSString *, NSDictionary<NSString *, NSDictionary *> *> *ComponentForms;
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
            for (NSString *key in @[@"type", @"text", @"tooltip", @"placeholder", @"enterable", @"width", @"height", @"style", @"showHeaders", @"headerHeight", @"detailForm", @"listForm"])
                if (object[key] && ![object[key] isKindOfClass:NSDictionary.class] && ![object[key] isKindOfClass:NSArray.class]) info[key] = object[key];
            // A list box's columns: their titles and widths, as defined.
            if ([object[@"columns"] isKindOfClass:NSArray.class]) {
                NSMutableArray *columns = [NSMutableArray new];
                for (NSDictionary *column in object[@"columns"]) {
                    if (![column isKindOfClass:NSDictionary.class]) continue;
                    NSDictionary *header = [column[@"header"] isKindOfClass:NSDictionary.class] ? column[@"header"] : nil;
                    // A title's "\\" is 4D's line break.
                    NSString *title = [header[@"text"] isKindOfClass:NSString.class] ? [header[@"text"] stringByReplacingOccurrencesOfString:@"\\" withString:@" "] : @"";
                    [columns addObject:@{@"header": title,
                                         // A column without a width is drawn at its minimum width.
                                         @"width": [column[@"width"] isKindOfClass:NSNumber.class] ? column[@"width"] :
                                                   [column[@"minWidth"] isKindOfClass:NSNumber.class] ? column[@"minWidth"] : @80,
                                         @"hidden": @([column[@"visibility"] isEqual:@"hidden"])}];
                }
                info[@"columns"] = columns;
            }
            objects[name] = info;
        }];
    }];
    return objects;
}

// The form definitions inside a component's archive (a .4DZ, which is a zip): each entry
// Project/Sources/Forms/<name>/form.4DForm, read from its central directory and inflated.
static NSDictionary<NSString *, NSData *> *ArchivedForms(NSURL *archive) {
    NSData *zip = [NSData dataWithContentsOfURL:archive options:NSDataReadingMappedIfSafe error:nil];
    const uint8_t *bytes = (const uint8_t *)zip.bytes;
    NSUInteger length = zip.length;
    auto u16 = [&](NSUInteger at) -> uint32_t { return at + 2 <= length ? (uint32_t)(bytes[at] | bytes[at + 1] << 8) : 0; };
    auto u32 = [&](NSUInteger at) -> uint32_t { return at + 4 <= length ? (uint32_t)(bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16 | (uint32_t)bytes[at + 3] << 24) : 0; };
    NSMutableDictionary *forms = [NSMutableDictionary new];
    if (length < 22) return forms;
    // The end of central directory record, within the last 64 KB.
    NSUInteger end = NSNotFound;
    for (NSUInteger at = length - 22; at + 65557 >= length && at > 0; at--) if (u32(at) == 0x06054b50) { end = at; break; }
    if (end == NSNotFound) return forms;
    NSUInteger count = u16(end + 10), at = u32(end + 16);
    NSString *prefix = @"Project/Sources/Forms/", *suffix = @"/form.4DForm";
    for (NSUInteger i = 0; i < count && at + 46 <= length && u32(at) == 0x02014b50; i++) {
        uint32_t method = u16(at + 10), compressed = u32(at + 20), size = u32(at + 24), local = u32(at + 42);
        NSUInteger nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32);
        NSString *name = at + 46 + nameLength <= length ? [[NSString alloc] initWithBytes:bytes + at + 46 length:nameLength encoding:NSUTF8StringEncoding] : nil;
        at += 46 + nameLength + extra + comment;
        if (![name hasPrefix:prefix] || ![name hasSuffix:suffix] || size > 4 * 1024 * 1024) continue;
        NSString *form = [name substringWithRange:NSMakeRange(prefix.length, name.length - prefix.length - suffix.length)];
        if ([form containsString:@"/"] || local + 30 > length || u32(local) != 0x04034b50) continue;
        NSUInteger data = local + 30 + u16(local + 26) + u16(local + 28);
        if (data + compressed > length) continue;
        if (method == 0) { forms[form] = [zip subdataWithRange:NSMakeRange(data, compressed)]; continue; }
        if (method != 8) continue;
        NSMutableData *out = [NSMutableData dataWithLength:size];
        z_stream stream = {};
        stream.next_in = (Bytef *)(bytes + data); stream.avail_in = compressed;
        stream.next_out = (Bytef *)out.mutableBytes; stream.avail_out = size;
        if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) continue;
        int status = inflate(&stream, Z_FINISH);
        inflateEnd(&stream);
        if (status == Z_STREAM_END && stream.total_out == size) forms[form] = out;
    }
    return forms;
}

// Every component's forms: the project's own components and those 4D includes.
static NSDictionary *LoadComponentForms(NSURL *sources) {
    NSMutableDictionary *forms = [NSMutableDictionary new];
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *root = [[sources URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    NSArray *folders = @[[root URLByAppendingPathComponent:@"Components"], [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Contents/Components"]];
    for (NSURL *folder in folders)
        for (NSURL *component in [files contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil] ?: @[]) {
            if (![component.pathExtension isEqual:@"4dbase"]) continue;
            NSURL *loose = [component URLByAppendingPathComponent:@"Project/Sources/Forms"];
            for (NSURL *form in [files contentsOfDirectoryAtURL:loose includingPropertiesForKeys:nil options:0 error:nil] ?: @[]) {
                NSDictionary *definition = ReadDefinition([form URLByAppendingPathComponent:@"form.4DForm"]);
                if (definition && !forms[form.lastPathComponent]) forms[form.lastPathComponent] = ObjectsOf(definition);
            }
            for (NSURL *archive in [files contentsOfDirectoryAtURL:component includingPropertiesForKeys:nil options:0 error:nil] ?: @[]) {
                if (![archive.pathExtension.lowercaseString isEqual:@"4dz"]) continue;
                [ArchivedForms(archive) enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSData *data, BOOL *stop) {
                    (void)stop;
                    if (data.length >= 3 && !memcmp(data.bytes, "\xEF\xBB\xBF", 3)) data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
                    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([json isKindOfClass:NSDictionary.class] && !forms[name]) forms[name] = ObjectsOf(json);
                }];
            }
        }
    // 4D Widgets set these from their methods, so their definitions do not name them.
    NSDictionary *hints = @{
        @"SearchPicker": @{@"SearchText_Mac": @{@"tooltip": @"Search", @"placeholder": @"Search"}, @"SearchText_Win": @{@"tooltip": @"Search", @"placeholder": @"Search"},
                           @"CloseButton_Mac": @{@"tooltip": @"Clear search"}, @"CloseButton_Win": @{@"tooltip": @"Clear search"}},
        @"DateButton": @{@"bTinyCalendar": @{@"tooltip": @"Choose date"}},
        @"DateEntry": @{@"bTinyCalendar": @{@"tooltip": @"Choose date"}, @"bUp": @{@"tooltip": @"Increase"}, @"bDown": @{@"tooltip": @"Decrease"}}};
    [hints enumerateKeysAndObjectsUsingBlock:^(NSString *form, NSDictionary *objects, BOOL *stop) {
        (void)stop;
        NSMutableDictionary *described = [forms[form] mutableCopy];
        if (!described) return;
        [objects enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *hint, BOOL *inner) {
            (void)inner;
            if (!described[name]) return;
            NSMutableDictionary *info = [described[name] mutableCopy];
            [info addEntriesFromDictionary:hint];
            described[name] = info;
        }];
        forms[form] = described;
    }];
    return forms;
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
    ComponentForms = LoadComponentForms(sources);
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

// Whether most of a region of the layer's image (in points from its top left) is filled with a
// saturated color, as macOS fills an on checkbox or a selected row with the accent color. Nil
// when the accent color is a gray or the image cannot be read.
static NSNumber *AccentShare(CALayer *layer, CGRect region, int opacity);
static NSNumber *AccentFilled(CALayer *layer, CGRect region) {
    NSNumber *share = AccentShare(layer, region, 128);
    return share ? @(share.doubleValue > 0.25) : nil;
}

// The share of a region's pixels drawn in a saturated color at least this opaque; nil when the
// accent color is a gray or the image cannot be read.
static NSNumber *AccentShare(CALayer *layer, CGRect region, int opacity) {
    NSColor *accent = [NSColor.controlAccentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!accent || accent.saturationComponent < 0.3) return nil;
    id contents = layer.contents;
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return nil;
    CGImageRef image = (__bridge CGImageRef)contents;
    CGFloat height = NSHeight(layer.bounds), scale = height > 0 ? CGImageGetHeight(image) / height : 0;
    if (scale <= 0) return nil;
    CGRect box = CGRectMake(region.origin.x * scale, region.origin.y * scale, region.size.width * scale, region.size.height * scale);
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
        if (bytes[i * 4 + 3] > opacity && high > 60 && (high - low) / high > 0.35) colored++;
    }
    return width * rows ? @((double)colored / (width * rows)) : nil;
}

// macOS draws the keyboard focus ring, translucent in the accent color, just outside the
// focused control: for a field, drop-down or list box in the margin 4D leaves around it in its layer, for a
// checkbox or radio button around its box. Sample a strip just above it; a checked box's own fill
// starts below the strip.
static BOOL FocusRing(CALayer *layer, NSRect area, BOOL box) {
    CGFloat height = NSHeight(layer.bounds), top = height - NSMaxY(area);
    CGRect strip = box ? CGRectMake(NSMinX(area) + 4, height / 2 - 10, 10, 1.5) : CGRectMake(NSMinX(area) + 8, top - 2.5, NSWidth(area) - 16, 2);
    if (CGRectGetMinY(strip) < 0 || CGRectGetWidth(strip) < 8) return NO;
    return AccentShare(layer, strip, 40).doubleValue > 0.5;
}

// The box sits at the object's leading edge, centered vertically: sample its inner square.
static NSNumber *ReadDrawnState(CALayer *layer, CGFloat inset) {
    return AccentFilled(layer, CGRectMake(inset + 3, NSHeight(layer.bounds) / 2 - 4, 9, 8));
}

// The luminance of a region of the layer's image, in points from its top left, at the image's
// pixel density: one byte per pixel, row by row. Nil when the image cannot be read.
static NSData *Luminance(CALayer *layer, CGRect region, size_t *width, size_t *rows, CGFloat *density) {
    id contents = layer.contents;
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return nil;
    CGImageRef image = (__bridge CGImageRef)contents;
    CGFloat height = NSHeight(layer.bounds), scale = height > 0 ? CGImageGetHeight(image) / height : 0;
    if (scale <= 0) return nil;
    CGImageRef part = CGImageCreateWithImageInRect(image, CGRectMake(region.origin.x * scale, region.origin.y * scale, region.size.width * scale, region.size.height * scale));
    if (!part) return nil;
    size_t w = CGImageGetWidth(part), h = CGImageGetHeight(part);
    NSMutableData *pixels = [NSMutableData dataWithLength:w * h * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(part); return nil; }
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), part);
    CGContextRelease(context);
    CGImageRelease(part);
    NSMutableData *luminance = [NSMutableData dataWithLength:w * h];
    const uint8_t *rgba = (const uint8_t *)pixels.bytes;
    uint8_t *out = (uint8_t *)luminance.mutableBytes;
    for (size_t i = 0; i < w * h; i++) out[i] = (uint8_t)((rgba[i * 4] * 299 + rgba[i * 4 + 1] * 587 + rgba[i * 4 + 2] * 114) / 1000);
    *width = w; *rows = h; *density = scale;
    return luminance;
}

// The x of each separator line 4D draws between the visible columns' titles, in the layer's
// points: a one or two pixel line, unlike the header on both sides of it, through the band.
static NSArray<NSNumber *> *HeaderSeparators(CALayer *layer, NSRect object, CGFloat header) {
    CGFloat top = NSHeight(layer.bounds) - NSMaxY(object);
    size_t width = 0, rows = 0;
    CGFloat density = 1;
    NSData *strip = Luminance(layer, CGRectMake(NSMinX(object), top + header * 0.3, NSWidth(object), MAX(header * 0.4, 2)), &width, &rows, &density);
    if (!strip || width < 12 || !rows) return @[];
    const uint8_t *pixels = (const uint8_t *)strip.bytes;
    NSMutableArray<NSNumber *> *lines = [NSMutableArray new];
    size_t gap = (size_t)MAX(3, round(3 * density));
    NSInteger run = -1;
    for (size_t x = gap; x + gap < width; x++) {
        BOOL line = YES;
        for (size_t y = 0; y < rows && line; y++) {
            const uint8_t *row = pixels + y * width;
            int left = row[x - gap], right = row[x + gap], here = row[x];
            line = abs(left - right) < 8 && abs(here - (left + right) / 2) > 12;
        }
        if (line && run < 0) run = (NSInteger)x;
        if (!line && run >= 0) {
            // A line is at most two points wide; wider differences are content.
            if ((CGFloat)(x - run) <= 2 * density) [lines addObject:@(NSMinX(object) + ((run + x) / 2.0) / density)];
            run = -1;
        }
    }
    return lines;
}

// Match the visible columns' widths to the defined columns in order, skipping the ones the
// application hides; the last visible column can grow with the list box. Titles are kept
// only when the widths agree.
static NSArray<NSString *> *MatchTitles(NSArray<NSNumber *> *widths, NSArray<NSDictionary *> *defined) {
    NSUInteger n = widths.count, m = defined.count;
    if (!n || !m || n > m) return nil;
    // cost[i][j]: best cost placing the first i visible columns among the first j defined ones.
    std::vector<std::vector<double>> cost(n + 1, std::vector<double>(m + 1, INFINITY));
    std::vector<std::vector<int>> pick(n + 1, std::vector<int>(m + 1, 0));
    for (NSUInteger j = 0; j <= m; j++) cost[0][j] = 0.3 * j;
    for (NSUInteger i = 1; i <= n; i++)
        for (NSUInteger j = i; j <= m; j++) {
            double skip = cost[i][j - 1] + 0.3;
            double want = [defined[j - 1][@"width"] doubleValue], have = widths[i - 1].doubleValue;
            double miss = want > 0 ? fabs(have - want) / want : 1;
            if (i == n && have > want) miss = 0;
            double take = cost[i - 1][j - 1] + MIN(miss, 1.0);
            if (take <= skip) { cost[i][j] = take; pick[i][j] = 1; } else { cost[i][j] = skip; pick[i][j] = 0; }
        }
    NSUInteger best = n;
    for (NSUInteger j = n; j <= m; j++) if (cost[n][j] < cost[n][best]) best = j;
    if (cost[n][best] - 0.3 * (best - n) > 0.2 * n) return nil;
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) [titles addObject:@""];
    // A title is kept only for a column drawn at its defined width: a resized one could be
    // another column, and is left unnamed rather than misnamed.
    for (NSUInteger i = n, j = best; i > 0 && j > 0;) {
        if (pick[i][j]) {
            if (fabs(widths[i - 1].doubleValue - [defined[j - 1][@"width"] doubleValue]) <= 3) titles[i - 1] = defined[j - 1][@"header"] ?: @"";
            i--; j--;
        } else j--;
    }
    return titles;
}

// A list box's visible rows, rebuilt from where 4D draws each cell's text: a row per
// baseline, each text in the column whose span holds it. Rows are selected with the mouse;
// a selected row is filled with the accent color behind its first column's text.
static NSDictionary *ListboxModel(CALayer *layer, NSDictionary *info, NSRect object) {
    NSMutableArray *defined = [NSMutableArray new];
    for (NSDictionary *column in info[@"columns"] ?: @[]) if (![column[@"hidden"] boolValue]) [defined addObject:column];
    NSMutableArray *columns = [NSMutableArray new];
    // The visible columns as 4D draws them: between the separators of the titles' band. An
    // application can hide and resize columns, so the definition alone does not place them.
    CGFloat band = [info[@"headerHeight"] doubleValue];
    if (band <= 0 && ![info[@"showHeaders"] isEqual:@NO]) band = 22;
    NSArray<NSNumber *> *separators = band > 0 ? HeaderSeparators(layer, object, band) : @[];
    if (separators.count) {
        NSMutableArray<NSNumber *> *edges = [NSMutableArray arrayWithObject:@(NSMinX(object) + 1)];
        for (NSNumber *x in separators) if (x.doubleValue - edges.lastObject.doubleValue >= 8) [edges addObject:x];
        CGFloat end = NSMaxX(object) - 1;
        NSMutableArray<NSNumber *> *widths = [NSMutableArray new];
        for (NSUInteger i = 0; i < edges.count; i++) {
            CGFloat next = i + 1 < edges.count ? edges[i + 1].doubleValue : end;
            if (next - edges[i].doubleValue >= 8) [widths addObject:@(next - edges[i].doubleValue)];
        }
        // The vertical scroll bar's corner of the header is not a column.
        if (widths.count > 1 && widths.lastObject.doubleValue < 17 && edges.count == widths.count) { [widths removeLastObject]; [edges removeLastObject]; }
        NSArray *titles = MatchTitles(widths, defined);
        for (NSUInteger i = 0; i < widths.count; i++)
            [columns addObject:@{@"header": titles ? titles[i] : @"", @"x": edges[i], @"width": widths[i]}];
    } else {
        CGFloat x = NSMinX(object) + 1;
        for (NSDictionary *column in defined) {
            // Columns scrolled out of the list box's width are not drawn.
            if (x >= NSMaxX(object) - 2) break;
            CGFloat width = [column[@"width"] doubleValue];
            [columns addObject:@{@"header": column[@"header"] ?: @"", @"x": @(x), @"width": @(width)}];
            x += width;
        }
    }
    // 4D's GUI framework draws the column titles with HIToolbox, in the same image as the cells.
    NSArray<NSString *> *texts = AXBDrawnTextWithThemedForLayer(layer);
    NSArray<NSValue *> *origins = AXBDrawnTextOriginsWithThemedForLayer(layer);
    NSMutableArray *rows = [NSMutableArray new];
    if (!columns.count || !texts.count || origins.count != texts.count) return @{@"columns": columns, @"rows": rows};
    // Group the texts by baseline, top to bottom.
    NSMutableDictionary<NSNumber *, NSMutableArray *> *lines = [NSMutableDictionary new];
    [texts enumerateObjectsUsingBlock:^(NSString *text, NSUInteger index, BOOL *stop) {
        (void)stop;
        NSPoint origin = origins[index].pointValue;
        if (isnan(origin.y)) return;
        NSNumber *key = @(round(origin.y * 2) / 2);
        if (!lines[key]) lines[key] = [NSMutableArray new];
        [lines[key] addObject:@{@"text": text, @"x": @(origin.x)}];
    }];
    NSArray<NSNumber *> *baselines = [lines.allKeys sortedArrayUsingSelector:@selector(compare:)];
    CGFloat height = 0;
    for (NSUInteger i = 1; i < baselines.count; i++) {
        CGFloat step = baselines[i].doubleValue - baselines[i - 1].doubleValue;
        if (step > 6 && (!height || step < height)) height = step;
    }
    if (!height) height = 18;
    CGFloat bounds = NSHeight(layer.bounds), top = bounds - NSMaxY(object);
    // The titles drawn in the header band name the columns that hold them.
    NSMutableArray *named = [NSMutableArray new];
    for (NSDictionary *column in columns) [named addObject:[column mutableCopy]];
    // Each column's titles, by baseline: a title wrapped over two lines is two texts in one column.
    NSMutableArray<NSMutableArray<NSDictionary *> *> *drawn = [NSMutableArray new];
    for (NSUInteger c = 0; c < named.count; c++) [drawn addObject:[NSMutableArray new]];
    BOOL drawnTitles = NO;
    for (NSNumber *baseline in baselines) {
        if (band <= 0 || baseline.doubleValue < top || baseline.doubleValue > top + band) continue;
        for (NSDictionary *item in lines[baseline]) {
            CGFloat at = [item[@"x"] doubleValue];
            for (NSUInteger c = 0; c < named.count; c++) {
                CGFloat start = [named[c][@"x"] doubleValue], width = [named[c][@"width"] doubleValue];
                if (at < start - 2 || at >= start + width - 2) continue;
                NSString *text = [item[@"text"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (text.length) [drawn[c] addObject:@{@"text": text, @"x": @(at), @"baseline": baseline}];
                drawnTitles = YES;
                break;
            }
        }
    }
    if (drawnTitles) {
        NSMutableArray *split = [NSMutableArray new];
        for (NSUInteger c = 0; c < named.count; c++) {
            // Two titles side by side on one line are two columns whose separator was not found:
            // each title starts its own column, just inside its left edge.
            NSMutableArray<NSNumber *> *starts = [NSMutableArray arrayWithObject:named[c][@"x"]];
            NSMutableDictionary<NSNumber *, NSMutableArray *> *byLine = [NSMutableDictionary new];
            for (NSDictionary *item in drawn[c]) {
                if (!byLine[item[@"baseline"]]) byLine[item[@"baseline"]] = [NSMutableArray new];
                [byLine[item[@"baseline"]] addObject:item[@"x"]];
            }
            NSArray<NSNumber *> *widest = nil;
            for (NSArray *xs in byLine.allValues) if (xs.count > widest.count) widest = [xs sortedArrayUsingSelector:@selector(compare:)];
            for (NSUInteger i = 1; i < widest.count; i++)
                if (widest[i].doubleValue - widest[i - 1].doubleValue >= 12 && widest[i].doubleValue - 3 > starts.lastObject.doubleValue + 8)
                    [starts addObject:@(widest[i].doubleValue - 3)];
            CGFloat end = [named[c][@"x"] doubleValue] + [named[c][@"width"] doubleValue];
            for (NSUInteger i = 0; i < starts.count; i++) {
                CGFloat from = starts[i].doubleValue, to = i + 1 < starts.count ? starts[i + 1].doubleValue : end;
                NSMutableArray *parts = [NSMutableArray new];
                for (NSDictionary *item in drawn[c]) {
                    CGFloat at = [item[@"x"] doubleValue];
                    if ((i == 0 || at >= from - 2) && (i + 1 == starts.count || at < to - 2)) [parts addObject:item[@"text"]];
                }
                [split addObject:[@{@"header": [parts componentsJoinedByString:@" "], @"x": @(from), @"width": @(to - from)} mutableCopy]];
            }
        }
        named = split;
    }
    columns = named;
    NSSet *titles = [NSSet setWithArray:[columns valueForKey:@"header"]];
    for (NSNumber *baseline in baselines) {
        NSMutableArray *cells = [NSMutableArray new];
        for (NSUInteger c = 0; c < columns.count; c++) [cells addObject:[NSMutableArray new]];
        NSUInteger placed = 0;
        for (NSDictionary *item in lines[baseline]) {
            CGFloat at = [item[@"x"] doubleValue];
            for (NSUInteger c = 0; c < columns.count; c++) {
                CGFloat start = [columns[c][@"x"] doubleValue], width = [columns[c][@"width"] doubleValue];
                if (at >= start - 2 && at < start + width - 2) { [cells[c] addObject:item[@"text"]]; placed++; break; }
            }
        }
        NSMutableArray *values = [NSMutableArray new];
        for (NSArray *parts in cells)
            [values addObject:[[parts componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        // The header row's titles are drawn in the same image.
        BOOL header = placed && [[NSSet setWithArray:[values filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]] isSubsetOfSet:titles];
        if (!placed || header) continue;
        CGFloat line = baseline.doubleValue;
        if (line < top || (band > 0 && line <= top + band)) continue;
        NSRect area = NSMakeRect(NSMinX(object), bounds - line - height / 4, NSWidth(object), height);
        NSMutableDictionary *row = [@{@"cells": values, @"area": [NSValue valueWithRect:area]} mutableCopy];
        CGFloat first = [columns[0][@"x"] doubleValue];
        NSNumber *selected = AccentFilled(layer, CGRectMake(first + 1, line - height * 0.6, 4, height * 0.4));
        if (selected) row[@"selected"] = selected;
        [rows addObject:row];
    }
    // The titles' band: from the object's top to its first row.
    CGFloat first = rows.count ? NSMaxY([rows.firstObject[@"area"] rectValue]) : NSMaxY(object) - 20;
    NSRect header = NSMakeRect(NSMinX(object), first, NSWidth(object), MAX(NSMaxY(object) - first, 0));
    return @{@"columns": columns, @"rows": rows, @"header": [NSValue valueWithRect:header]};
}

// A tab control's tabs: 4D draws each label with HIToolbox in its segment's box. A press is an
// ordinary click on the segment. macOS draws the chosen segment lighter than the others' track.
static NSArray<NSDictionary *> *TabEntries(CALayer *layer, NSString *key) {
    NSArray<NSString *> *labels = AXBDrawnTextWithThemedForLayer(layer);
    NSDictionary<NSNumber *, NSValue *> *boxes = AXBDrawnTextThemedBoxesForLayer(layer);
    NSMutableArray<NSDictionary *> *tabs = [NSMutableArray new];
    for (NSNumber *index in boxes) {
        NSString *label = index.unsignedIntegerValue < labels.count ? labels[index.unsignedIntegerValue] : nil;
        NSRect box = boxes[index].rectValue;
        if (label.length && NSWidth(box) >= 8 && NSHeight(box) >= 8) [tabs addObject:@{@"label": label, @"box": boxes[index]}];
    }
    [tabs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSRect ra = [a[@"box"] rectValue], rb = [b[@"box"] rectValue];
        if (fabs(NSMinY(ra) - NSMinY(rb)) > 4) return NSMinY(ra) < NSMinY(rb) ? NSOrderedAscending : NSOrderedDescending;
        return NSMinX(ra) < NSMinX(rb) ? NSOrderedAscending : NSOrderedDescending;
    }];
    // The segment's background, just inside its leading edge, beside the centered label.
    NSMutableArray<NSNumber *> *shades = [NSMutableArray new];
    for (NSDictionary *tab in tabs) {
        NSRect box = [tab[@"box"] rectValue];
        size_t width = 0, rows = 0;
        CGFloat density = 1;
        NSData *strip = Luminance(layer, CGRectMake(NSMinX(box) + 2, NSMidY(box) - 2, 3, 4), &width, &rows, &density);
        double total = 0;
        for (NSUInteger i = 0; i < strip.length; i++) total += ((const uint8_t *)strip.bytes)[i];
        [shades addObject:@(strip.length ? total / strip.length : -1)];
    }
    NSUInteger chosen = NSNotFound;
    double best = -1, next = -1;
    for (NSUInteger i = 0; i < shades.count; i++) {
        double shade = shades[i].doubleValue;
        if (shade > best) { next = best; best = shade; chosen = i; } else if (shade > next) next = shade;
    }
    if (tabs.count < 2 || best < 0 || next < 0 || best - next < 6) chosen = NSNotFound;
    NSMutableArray *entries = [NSMutableArray new];
    NSMutableSet *used = [NSMutableSet new];
    CGFloat height = NSHeight(layer.bounds);
    for (NSUInteger i = 0; i < tabs.count; i++) {
        NSRect box = [tabs[i][@"box"] rectValue];
        NSString *name = [NSString stringWithFormat:@"%@/%@", key, tabs[i][@"label"]];
        if ([used containsObject:name]) name = [NSString stringWithFormat:@"%@/%lu", name, (unsigned long)i + 1];
        [used addObject:name];
        NSMutableDictionary *entry = [@{@"key": name, @"layer": layer, @"role": NSAccessibilityRadioButtonRole, @"label": tabs[i][@"label"],
                                        @"area": [NSValue valueWithRect:NSMakeRect(NSMinX(box), height - NSMaxY(box), NSWidth(box), NSHeight(box))]} mutableCopy];
        if (chosen != NSNotFound) entry[@"checked"] = @(i == chosen);
        [entries addObject:entry];
    }
    return entries;
}

static NSArray<NSDictionary *> *FormEntries(CALayer *form, NSDictionary<NSString *, NSDictionary *> *objects, NSString *prefix, NSUInteger depth) {
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
        NSMutableDictionary *entry = [@{@"key": [prefix stringByAppendingString:layer.name], @"layer": layer} mutableCopy];
        if (!NSEqualRects(area, layer.bounds)) entry[@"area"] = [NSValue valueWithRect:area];
        if ([type isEqual:@"subform"]) {
            // A page subform shows a project form of its own: its objects take its place.
            CALayer *context = AXBInternalSubformContext(layer);
            NSString *detail = [info[@"detailForm"] isKindOfClass:NSString.class] && !info[@"listForm"] ? info[@"detailForm"] : nil;
            NSDictionary *inner = detail ? (Forms[detail] ?: ComponentForms[detail]) : nil;
            if (context && inner && depth < 3)
                [entries addObjectsFromArray:FormEntries(context, inner, [NSString stringWithFormat:@"%@%@/", prefix, layer.name], depth + 1)];
            continue;
        } else if ([@[@"button", @"pictureButton"] containsObject:type]) {
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
                if (FocusRing(layer, area, YES)) entry[@"focused"] = @YES;
            }
        } else if ([type isEqual:@"text"] || [type isEqual:@"groupBox"]) {
            if (!title) continue;
            entry[@"role"] = NSAccessibilityStaticTextRole;
            entry[@"text"] = title;
            // Only words name a control; an arrow or a separator does not.
            if ([title rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location != NSNotFound) [captions addObject:@{@"layer": layer, @"text": title}];
        } else if ([type isEqual:@"listbox"]) {
            entry[@"role"] = NSAccessibilityTableRole;
            entry[@"table"] = ListboxModel(layer, info, area);
            if (FocusRing(layer, area, NO)) entry[@"focused"] = @YES;
            entry[@"caption"] = @YES;
            if (help) entry[@"label"] = help;
        } else if ([type isEqual:@"tab"]) {
            [entries addObjectsFromArray:TabEntries(layer, [prefix stringByAppendingString:layer.name])];
            continue;
        } else if ([type isEqual:@"dropdown"]) {
            entry[@"role"] = NSAccessibilityPopUpButtonRole;
            if (FocusRing(layer, area, NO)) entry[@"focused"] = @YES;
            if (help) entry[@"label"] = help;
        } else if ([type isEqual:@"input"] || [type isEqual:@"combo"]) {
            entry[@"role"] = NSAccessibilityTextFieldRole;
            entry[@"editable"] = @(![info[@"enterable"] isEqual:@NO]);
            if (FocusRing(layer, area, NO)) entry[@"focused"] = @YES;
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
    NSArray *entries = objects ? FormEntries(form, objects, @"", 0) : nil;
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
    Overlays = nil; Matches = nil; Forms = nil; FormsByObject = nil; States = nil; ComponentForms = nil;
}

NSDictionary<NSString *, NSDictionary *> *AXBGenericFormsArchivedFormsForTesting(NSString *path) {
    NSMutableDictionary *forms = [NSMutableDictionary new];
    [ArchivedForms([NSURL fileURLWithPath:path]) enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSData *data, BOOL *stop) {
        (void)stop;
        if (data.length >= 3 && !memcmp(data.bytes, "\xEF\xBB\xBF", 3)) data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) forms[name] = ObjectsOf(json);
    }];
    return forms;
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
