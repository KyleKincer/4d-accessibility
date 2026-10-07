#import "DrawnText.h"
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <os/lock.h>
#include <sys/mman.h>
#include <string.h>
#include <unistd.h>

// Drawing happens on 4D's render threads; every table below is guarded by TableLock.
// Keys are weak and compared by identity: a freed line, frame or image leaves its table.
static os_unfair_lock TableLock = OS_UNFAIR_LOCK_INIT;
static NSMapTable *LineText, *SetterText, *FrameText, *ImageText, *LayerText;
static NSMutableDictionary<NSValue *, NSMutableArray<NSString *> *> *ContextText;
// Each owner's observed layer names and observer.
static NSMutableDictionary<NSString *, NSDictionary *> *Observers;
static NSSet<NSString *> *ObservedNames;
static BOOL Installed, Available;

struct AXBTableGuard {
    AXBTableGuard() { os_unfair_lock_lock(&TableLock); }
    ~AXBTableGuard() { os_unfair_lock_unlock(&TableLock); }
};

typedef CTLineRef (*LineCreateFn)(CFAttributedStringRef);
typedef void (*LineDrawFn)(CTLineRef, CGContextRef);
typedef CTFramesetterRef (*SetterCreateFn)(CFAttributedStringRef);
typedef CTFrameRef (*FrameCreateFn)(CTFramesetterRef, CFRange, CGPathRef, CFDictionaryRef);
typedef void (*FrameDrawFn)(CTFrameRef, CGContextRef);
typedef CGImageRef (*ImageCreateFn)(CGContextRef);
typedef CGContextRef (*ContextCreateFn)(void *, size_t, size_t, size_t, size_t, CGColorSpaceRef, uint32_t);
typedef CGContextRef (*ContextCreateWithDataFn)(void *, size_t, size_t, size_t, size_t, CGColorSpaceRef, uint32_t, CGBitmapContextReleaseDataCallback, void *);
static LineCreateFn OriginalLineCreate;
static LineDrawFn OriginalLineDraw;
static SetterCreateFn OriginalSetterCreate;
static FrameCreateFn OriginalFrameCreate;
static FrameDrawFn OriginalFrameDraw;
static ImageCreateFn OriginalImageCreate;
static ContextCreateFn OriginalContextCreate;
static ContextCreateWithDataFn OriginalContextCreateWithData;

// A context that never becomes an image must not grow the tables without bound.
static const NSUInteger ContextLimit = 512, ContextTextLimit = 64;

static NSMapTable *WeakIdentityTable(void) {
    return [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                     valueOptions:NSPointerFunctionsStrongMemory capacity:0];
}

// An immutable copy: 4D may keep mutating the attributed string it drew.
static NSString *TextOf(NSString *text, CFRange range) {
    if (!text) return nil;
    if (range.length > 0 && range.location >= 0 && (NSUInteger)(range.location + range.length) <= text.length)
        return [text substringWithRange:NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length)];
    return [text copy];
}

static NSString *StringOf(CFAttributedStringRef string) {
    return string ? [[(__bridge NSAttributedString *)string string] copy] : nil;
}

static void RecordDraw(CGContextRef context, NSString *text) {
    if (!context || !text.length) return;
    AXBTableGuard guard;
    NSValue *key = [NSValue valueWithPointer:context];
    NSMutableArray *texts = ContextText[key];
    if (!texts) {
        if (ContextText.count >= ContextLimit) [ContextText removeAllObjects];
        texts = ContextText[key] = [NSMutableArray new];
    }
    if (texts.count < ContextTextLimit) [texts addObject:text];
}

// A new bitmap context can reuse a freed context's address; it starts with no text.
static void ForgetContext(CGContextRef context) {
    if (!context) return;
    AXBTableGuard guard;
    [ContextText removeObjectForKey:[NSValue valueWithPointer:context]];
}

static CGContextRef ObservedContextCreate(void *data, size_t width, size_t height, size_t bits, size_t row, CGColorSpaceRef space, uint32_t info) {
    CGContextRef context = OriginalContextCreate(data, width, height, bits, row, space, info);
    ForgetContext(context);
    return context;
}

static CGContextRef ObservedContextCreateWithData(void *data, size_t width, size_t height, size_t bits, size_t row, CGColorSpaceRef space, uint32_t info,
                                                  CGBitmapContextReleaseDataCallback callback, void *callbackInfo) {
    CGContextRef context = OriginalContextCreateWithData(data, width, height, bits, row, space, info, callback, callbackInfo);
    ForgetContext(context);
    return context;
}

static CTLineRef ObservedLineCreate(CFAttributedStringRef string) {
    CTLineRef line = OriginalLineCreate(string);
    NSString *text = StringOf(string);
    if (line && text) { AXBTableGuard guard; [LineText setObject:text forKey:(__bridge id)line]; }
    return line;
}

static void ObservedLineDraw(CTLineRef line, CGContextRef context) {
    NSString *text = nil;
    if (line) { AXBTableGuard guard; text = [LineText objectForKey:(__bridge id)line]; }
    RecordDraw(context, text);
    OriginalLineDraw(line, context);
}

static CTFramesetterRef ObservedSetterCreate(CFAttributedStringRef string) {
    CTFramesetterRef setter = OriginalSetterCreate(string);
    NSString *text = StringOf(string);
    if (setter && text) { AXBTableGuard guard; [SetterText setObject:text forKey:(__bridge id)setter]; }
    return setter;
}

static CTFrameRef ObservedFrameCreate(CTFramesetterRef setter, CFRange range, CGPathRef path, CFDictionaryRef attributes) {
    CTFrameRef frame = OriginalFrameCreate(setter, range, path, attributes);
    NSString *string = nil;
    if (setter) { AXBTableGuard guard; string = [SetterText objectForKey:(__bridge id)setter]; }
    if (frame && string) {
        CFRange visible = CTFrameGetVisibleStringRange(frame);
        NSString *text = TextOf(string, visible.length ? visible : range);
        if (text) { AXBTableGuard guard; [FrameText setObject:text forKey:(__bridge id)frame]; }
    }
    return frame;
}

static void ObservedFrameDraw(CTFrameRef frame, CGContextRef context) {
    NSString *text = nil;
    if (frame) { AXBTableGuard guard; text = [FrameText objectForKey:(__bridge id)frame]; }
    RecordDraw(context, text);
    OriginalFrameDraw(frame, context);
}

static CGImageRef ObservedImageCreate(CGContextRef context) {
    CGImageRef image = OriginalImageCreate(context);
    if (context) {
        AXBTableGuard guard;
        NSValue *key = [NSValue valueWithPointer:context];
        NSArray *texts = ContextText[key];
        [ContextText removeObjectForKey:key];
        if (image && texts.count) [ImageText setObject:texts forKey:(__bridge id)image];
    }
    return image;
}

// Record the text of a layer's new contents. Contents without drawn text clear the
// layer's previous text, so an emptied field does not keep its old value.
static void RecordContents(CALayer *layer, id contents) {
    NSString *name = layer.name;
    NSSet *names;
    BOOL changed = NO;
    {
        AXBTableGuard guard;
        names = ObservedNames;
        NSArray *texts = contents ? [ImageText objectForKey:contents] : nil;
        if (texts) { [LayerText setObject:texts forKey:layer]; changed = YES; }
        else if (name && [names containsObject:name] && [LayerText objectForKey:layer]) { [LayerText removeObjectForKey:layer]; changed = YES; }
    }
    if (!changed || !name || ![names containsObject:name]) return;
    // 4D's own modal loops do not drain the main dispatch queue. Schedule the observer in
    // every mode the main run loop knows, including 4D's own.
    __weak CALayer *weakLayer = layer;
    CFRunLoopRef main = CFRunLoopGetMain();
    CFArrayRef modes = CFRunLoopCopyAllModes(main);
    if (!modes) return;
    CFRunLoopPerformBlock(main, modes, ^{
        CALayer *strong = weakLayer;
        NSArray *current;
        { AXBTableGuard guard; current = Observers.allValues; }
        for (NSDictionary *entry in current)
            if (strong && [entry[@"names"] containsObject:strong.name]) ((void (^)(CALayer *))entry[@"observer"])(strong);
    });
    CFRelease(modes);
    CFRunLoopWakeUp(main);
}

struct AXBRebinding { const char *name; void *replacement; };

// Replace one image's imported-symbol slots (its indirect symbol pointers). Only the
// calling image's own references change; other code keeps the original functions.
static NSUInteger RebindImage(const struct mach_header_64 *header, intptr_t slide, const struct AXBRebinding *rebindings, size_t count) {
    if (header->magic != MH_MAGIC_64) return 0;
    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, cursor += ((const struct load_command *)cursor)->cmdsize) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)command)->segname, SEG_LINKEDIT))
            linkedit = (const struct segment_command_64 *)command;
        else if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)command;
        else if (command->cmd == LC_DYSYMTAB) dysymtab = (const struct dysymtab_command *)command;
    }
    if (!linkedit || !symtab || !dysymtab || !dysymtab->nindirectsyms) return 0;
    uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);
    long page = getpagesize();
    NSUInteger replaced = 0;
    cursor = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, cursor += ((const struct load_command *)cursor)->cmdsize) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
        BOOL constant = !strcmp(segment->segname, "__DATA_CONST");
        if (strcmp(segment->segname, SEG_DATA) && !constant) continue;
        const struct section_64 *sections = (const struct section_64 *)(segment + 1);
        for (uint32_t s = 0; s < segment->nsects; s++) {
            uint32_t type = sections[s].flags & SECTION_TYPE;
            if (type != S_LAZY_SYMBOL_POINTERS && type != S_NON_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)((uintptr_t)slide + sections[s].addr);
            const uint32_t *indices = indirect + sections[s].reserved1;
            size_t slotCount = sections[s].size / sizeof(void *);
            for (size_t k = 0; k < slotCount; k++) {
                uint32_t index = indices[k];
                if (index & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL)) continue;
                if (index >= symtab->nsyms) continue;
                const char *name = strings + symbols[index].n_un.n_strx;
                if (name[0] != '_') continue;
                for (size_t r = 0; r < count; r++) {
                    if (strcmp(name + 1, rebindings[r].name)) continue;
                    uintptr_t start = (uintptr_t)&slots[k] & ~(uintptr_t)(page - 1);
                    if (mprotect((void *)start, (size_t)page, PROT_READ | PROT_WRITE)) continue;
                    slots[k] = rebindings[r].replacement;
                    // Constant data returns to read-only, as dyld left it.
                    if (constant) mprotect((void *)start, (size_t)page, PROT_READ);
                    replaced++;
                }
            }
        }
    }
    return replaced;
}

BOOL AXBDrawnTextInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LineText = WeakIdentityTable();
        SetterText = WeakIdentityTable();
        FrameText = WeakIdentityTable();
        ImageText = WeakIdentityTable();
        if (!LayerText) LayerText = WeakIdentityTable();
        ContextText = [NSMutableDictionary new];
        OriginalLineCreate = (LineCreateFn)dlsym(RTLD_DEFAULT, "CTLineCreateWithAttributedString");
        OriginalLineDraw = (LineDrawFn)dlsym(RTLD_DEFAULT, "CTLineDraw");
        OriginalSetterCreate = (SetterCreateFn)dlsym(RTLD_DEFAULT, "CTFramesetterCreateWithAttributedString");
        OriginalFrameCreate = (FrameCreateFn)dlsym(RTLD_DEFAULT, "CTFramesetterCreateFrame");
        OriginalFrameDraw = (FrameDrawFn)dlsym(RTLD_DEFAULT, "CTFrameDraw");
        OriginalImageCreate = (ImageCreateFn)dlsym(RTLD_DEFAULT, "CGBitmapContextCreateImage");
        OriginalContextCreate = (ContextCreateFn)dlsym(RTLD_DEFAULT, "CGBitmapContextCreate");
        OriginalContextCreateWithData = (ContextCreateWithDataFn)dlsym(RTLD_DEFAULT, "CGBitmapContextCreateWithData");
        if (!OriginalLineCreate || !OriginalLineDraw || !OriginalSetterCreate || !OriginalFrameCreate || !OriginalFrameDraw || !OriginalImageCreate ||
            !OriginalContextCreate || !OriginalContextCreateWithData) return;
        const struct AXBRebinding rebindings[] = {
            {"CTLineCreateWithAttributedString", (void *)ObservedLineCreate}, {"CTLineDraw", (void *)ObservedLineDraw},
            {"CTFramesetterCreateWithAttributedString", (void *)ObservedSetterCreate}, {"CTFramesetterCreateFrame", (void *)ObservedFrameCreate},
            {"CTFrameDraw", (void *)ObservedFrameDraw}, {"CGBitmapContextCreateImage", (void *)ObservedImageCreate},
            {"CGBitmapContextCreate", (void *)ObservedContextCreate}, {"CGBitmapContextCreateWithData", (void *)ObservedContextCreateWithData}};
        // Only the host application's own images: its executable and embedded frameworks.
        NSString *host = [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"];
        Dl_info own = {};
        dladdr((const void *)&AXBDrawnTextInitialize, &own);
        NSUInteger replaced = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name || host.length < 2 || strncmp(name, host.fileSystemRepresentation, strlen(host.fileSystemRepresentation))) continue;
            if (own.dli_fname && !strcmp(name, own.dli_fname)) continue;
            replaced += RebindImage((const struct mach_header_64 *)_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i),
                                    rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
        }
        Method method = class_getInstanceMethod(CALayer.class, @selector(setContents:));
        if (replaced && method) {
            IMP original = method_getImplementation(method);
            method_setImplementation(method, imp_implementationWithBlock(^(CALayer *layer, id contents) {
                ((void (*)(id, SEL, id))original)(layer, @selector(setContents:), contents);
                // Only images can carry drawn text; other contents matter only to a named layer.
                if ((contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) || layer.name) RecordContents(layer, contents);
            }));
            Available = YES;
        }
        Installed = YES;
    });
    return Available;
}

BOOL AXBDrawnTextAvailable(void) { return Available; }

NSArray<NSString *> *AXBDrawnTextForLayer(CALayer *layer) {
    if (!layer) return nil;
    AXBTableGuard guard;
    return [[LayerText objectForKey:layer] copy];
}

void AXBDrawnTextSetObserver(NSString *owner, NSSet<NSString *> *names, void (^observer)(CALayer *layer)) {
    AXBTableGuard guard;
    if (!Observers) Observers = [NSMutableDictionary new];
    if (observer && names) Observers[owner] = @{@"names": [names copy], @"observer": [observer copy]};
    else [Observers removeObjectForKey:owner];
    NSMutableSet *all = [NSMutableSet new];
    for (NSDictionary *entry in Observers.allValues) [all unionSet:entry[@"names"]];
    ObservedNames = all;
}

void AXBDrawnTextRecordForTesting(CALayer *layer, NSArray<NSString *> *texts) {
    AXBTableGuard guard;
    if (!LayerText) LayerText = WeakIdentityTable();
    if (texts) [LayerText setObject:[texts copy] forKey:layer];
    else [LayerText removeObjectForKey:layer];
}

NSArray<NSString *> *AXBDrawnTextForImageForTesting(CGImageRef image) {
    AXBTableGuard guard;
    return image ? [ImageText objectForKey:(__bridge id)image] : nil;
}

void AXBDrawnTextRecordImageForTesting(CGImageRef image, NSArray<NSString *> *texts) {
    AXBTableGuard guard;
    if (!ImageText) ImageText = WeakIdentityTable();
    [ImageText setObject:[texts copy] forKey:(__bridge id)image];
}
