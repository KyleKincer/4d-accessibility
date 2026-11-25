#import "FormCatalog.h"
#include <cmath>
#include <cstring>
#include <dlfcn.h>
#include <zlib.h>
#include <list>
#include <unordered_map>

namespace {

constexpr NSUInteger kMaxCacheEntries = 256;
constexpr NSUInteger kMaxFormBytes = 4 * 1024 * 1024;
constexpr NSUInteger kMaxInheritanceDepth = 16;

struct ZipEntry {
    uint32_t method = 0;
    uint32_t compressedSize = 0;
    uint32_t uncompressedSize = 0;
    uint32_t localHeaderOffset = 0;
};

struct CatalogState {
    BOOL initialized = NO;
    BOOL isArchive = NO;
    NSString *structurePath = nil;
    NSURL *sourcesURL = nil;
    NSData *archiveData = nil;
    std::unordered_map<std::string, ZipEntry> zipEntries;
    NSDictionary<NSString *, NSString *> *tableNames = nil;
    NSDate *catalogMTime = nil;
    NSDictionary<NSString *, NSString *> *tips = nil;
    NSDate *tipsMTime = nil;
};

struct CachedEntry {
    NSString *json = nil;
    NSDictionary<NSString *, NSDate *> *mtimes = nil;
    NSDate *catalogMTime = nil;
    NSDate *tipsMTime = nil;
};

static NSObject *CatalogLock = nil;
static CatalogState State;
static std::list<std::string> LruOrder;
static std::unordered_map<std::string, std::pair<CachedEntry, std::list<std::string>::iterator>> LruMap;

static void EnsureLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CatalogLock = [NSObject new];
    });
}

static uint32_t ReadU16(const uint8_t *bytes, NSUInteger length, NSUInteger at) {
    return at + 2 <= length ? static_cast<uint32_t>(bytes[at] | (bytes[at + 1] << 8)) : 0;
}

static uint32_t ReadU32(const uint8_t *bytes, NSUInteger length, NSUInteger at) {
    return at + 4 <= length ? static_cast<uint32_t>(bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (static_cast<uint32_t>(bytes[at + 3]) << 24)) : 0;
}

static BOOL IsBoolNumber(id value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    return CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL IsIntNumber(id value) {
    if (![value isKindOfClass:NSNumber.class] || IsBoolNumber(value)) return NO;
    double d = [value doubleValue];
    return std::floor(d) == d && d >= -2147483648.0 && d <= 2147483647.0;
}

static NSString *TrimmedString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length ? trimmed : nil;
}

static NSDate *FileMTime(NSURL *url) {
    if (!url) return nil;
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    return attrs[NSFileModificationDate];
}

static BOOL MTimeEqual(NSDate *a, NSDate *b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    return [a isEqualToDate:b];
}

static void IndexArchive(NSData *zip) {
    State.zipEntries.clear();
    const uint8_t *bytes = static_cast<const uint8_t *>(zip.bytes);
    NSUInteger length = zip.length;
    if (!bytes || length < 22) return;
    NSUInteger end = NSNotFound;
    for (NSUInteger at = length - 22; at + 65557 >= length; at--) {
        if (ReadU32(bytes, length, at) == 0x06054b50) {
            end = at;
            break;
        }
        if (at == 0) break;
    }
    if (end == NSNotFound) return;
    NSUInteger count = ReadU16(bytes, length, end + 10);
    NSUInteger at = ReadU32(bytes, length, end + 16);
    for (NSUInteger i = 0; i < count && at + 46 <= length && ReadU32(bytes, length, at) == 0x02014b50; i++) {
        ZipEntry entry;
        entry.method = ReadU16(bytes, length, at + 10);
        entry.compressedSize = ReadU32(bytes, length, at + 20);
        entry.uncompressedSize = ReadU32(bytes, length, at + 24);
        entry.localHeaderOffset = ReadU32(bytes, length, at + 42);
        NSUInteger nameLen = ReadU16(bytes, length, at + 28);
        NSUInteger extraLen = ReadU16(bytes, length, at + 30);
        NSUInteger commentLen = ReadU16(bytes, length, at + 32);
        if (at + 46 + nameLen <= length) {
            std::string name(reinterpret_cast<const char *>(bytes + at + 46), nameLen);
            State.zipEntries.emplace(std::move(name), entry);
        }
        at += 46 + nameLen + extraLen + commentLen;
    }
}

static NSData *ReadArchiveEntry(const std::string &path) {
    if (!State.archiveData) return nil;
    auto it = State.zipEntries.find(path);
    if (it == State.zipEntries.end()) return nil;
    const ZipEntry &entry = it->second;
    if (entry.uncompressedSize > kMaxFormBytes) return nil;
    const uint8_t *bytes = static_cast<const uint8_t *>(State.archiveData.bytes);
    NSUInteger length = State.archiveData.length;
    NSUInteger local = entry.localHeaderOffset;
    if (local + 30 > length || ReadU32(bytes, length, local) != 0x04034b50) return nil;
    NSUInteger dataOffset = local + 30 + ReadU16(bytes, length, local + 26) + ReadU16(bytes, length, local + 28);
    if (dataOffset + entry.compressedSize > length) return nil;
    if (entry.method == 0) {
        return [State.archiveData subdataWithRange:NSMakeRange(dataOffset, entry.compressedSize)];
    }
    if (entry.method != 8) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:entry.uncompressedSize];
    z_stream stream = {};
    stream.next_in = const_cast<Bytef *>(bytes + dataOffset);
    stream.avail_in = entry.compressedSize;
    stream.next_out = static_cast<Bytef *>(out.mutableBytes);
    stream.avail_out = entry.uncompressedSize;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return nil;
    int status = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    if (status == Z_STREAM_END && stream.total_out == entry.uncompressedSize) return out;
    return nil;
}

static NSData *ReadSourceFile(NSString *relativePath, NSMutableDictionary<NSString *, NSDate *> *mtimes) {
    if (!State.initialized) return nil;
    if (State.isArchive) {
        std::string full = std::string("Project/Sources/") + relativePath.UTF8String;
        NSData *data = ReadArchiveEntry(full);
        if (!data) {
            std::string alt = std::string("Sources/") + relativePath.UTF8String;
            data = ReadArchiveEntry(alt);
        }
        return data;
    }
    if (!State.sourcesURL) return nil;
    NSURL *url = [State.sourcesURL URLByAppendingPathComponent:relativePath];
    NSDate *mtime = FileMTime(url);
    if (mtimes && mtime) mtimes[url.path] = mtime;
    return mtime ? [NSData dataWithContentsOfURL:url] : nil;
}

static id ParseJSONData(NSData *data) {
    if (!data || data.length == 0) return nil;
    if (data.length >= 3 && std::memcmp(data.bytes, "\xEF\xBB\xBF", 3) == 0) {
        data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

} // namespace

@interface AXBCatalogXMLDelegate : NSObject <NSXMLParserDelegate>
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *tables;
@end

@implementation AXBCatalogXMLDelegate
- (instancetype)init {
    self = [super init];
    if (self) _tables = [NSMutableDictionary new];
    return self;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {
    (void)parser; (void)namespaceURI; (void)qName;
    if ([elementName isEqualToString:@"table"]) {
        NSString *name = attributeDict[@"name"];
        NSString *tableId = attributeDict[@"id"];
        if (name.length && tableId.length) {
            self.tables[name] = tableId;
        }
    }
}
@end

namespace {

static void RefreshAuxiliaryFiles(void) {
    if (!State.initialized) return;
    if (State.isArchive) {
        if (!State.tableNames) {
            NSData *catalogData = ReadSourceFile(@"catalog.4DCatalog", nil);
            if (catalogData) {
                AXBCatalogXMLDelegate *delegate = [AXBCatalogXMLDelegate new];
                NSXMLParser *parser = [[NSXMLParser alloc] initWithData:catalogData];
                parser.delegate = delegate;
                [parser parse];
                State.tableNames = [delegate.tables copy];
            } else {
                State.tableNames = @{};
            }
        }
        if (!State.tips) {
            id parsed = ParseJSONData(ReadSourceFile(@"tips.json", nil));
            if ([parsed isKindOfClass:NSDictionary.class]) {
                NSMutableDictionary<NSString *, NSString *> *clean = [NSMutableDictionary new];
                [(NSDictionary *)parsed enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    (void)stop;
                    if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSString.class]) {
                        clean[key] = obj;
                    }
                }];
                State.tips = [clean copy];
            } else {
                State.tips = @{};
            }
        }
        return;
    }
    if (!State.sourcesURL) return;
    NSURL *catalogURL = [State.sourcesURL URLByAppendingPathComponent:@"catalog.4DCatalog"];
    NSDate *catalogMTime = FileMTime(catalogURL);
    if (!State.tableNames || !MTimeEqual(State.catalogMTime, catalogMTime)) {
        State.catalogMTime = catalogMTime;
        NSData *catalogData = catalogMTime ? [NSData dataWithContentsOfURL:catalogURL] : nil;
        if (catalogData) {
            AXBCatalogXMLDelegate *delegate = [AXBCatalogXMLDelegate new];
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:catalogData];
            parser.delegate = delegate;
            [parser parse];
            State.tableNames = [delegate.tables copy];
        } else {
            State.tableNames = @{};
        }
    }
    NSURL *tipsURL = [State.sourcesURL URLByAppendingPathComponent:@"tips.json"];
    NSDate *tipsMTime = FileMTime(tipsURL);
    if (!State.tips || !MTimeEqual(State.tipsMTime, tipsMTime)) {
        State.tipsMTime = tipsMTime;
        NSData *tipsData = tipsMTime ? [NSData dataWithContentsOfURL:tipsURL] : nil;
        id parsed = ParseJSONData(tipsData);
        if ([parsed isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary<NSString *, NSString *> *clean = [NSMutableDictionary new];
            [(NSDictionary *)parsed enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                (void)stop;
                if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSString.class]) {
                    clean[key] = obj;
                }
            }];
            State.tips = [clean copy];
        } else {
            State.tips = @{};
        }
    }
}

static NSString *ResolveTooltip(id raw) {
    NSString *text = nil;
    if ([raw isKindOfClass:NSString.class]) {
        text = (NSString *)raw;
    } else if ([raw isKindOfClass:NSDictionary.class]) {
        id ref = ((NSDictionary *)raw)[@"$ref"];
        if ([ref isKindOfClass:NSString.class]) text = (NSString *)ref;
    }
    if (!text) return nil;
    NSRange tipsRange = [text rangeOfString:@"tips.json#/"];
    if (tipsRange.location != NSNotFound) {
        NSString *key = [text substringFromIndex:NSMaxRange(tipsRange)];
        text = State.tips[key];
    } else {
        NSRange tipsHash = [text rangeOfString:@"tips.json#"];
        if (tipsHash.location != NSNotFound) {
            NSString *key = [text substringFromIndex:NSMaxRange(tipsHash)];
            text = State.tips[key];
        }
    }
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;
    if ([text hasPrefix:@":xliff:"] || [text hasPrefix:@":/tips.json"] || [text containsString:@"tips.json#"]) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    return trimmed.length > 512 ? [trimmed substringToIndex:512] : trimmed;
}

static NSDictionary *SanitizeFormOptions(id raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSDictionary *dict = (NSDictionary *)raw;
    NSString *label = TrimmedString(dict[@"label"]);
    if (label && label.length <= 512) out[@"label"] = dict[@"label"];
    NSString *key = TrimmedString(dict[@"automationKey"]);
    if (key && key.length <= 256) out[@"automationKey"] = dict[@"automationKey"];
    if (IsBoolNumber(dict[@"omitOutsideWindow"])) out[@"omitOutsideWindow"] = dict[@"omitOutsideWindow"];
    if (IsBoolNumber(dict[@"idleRefresh"])) out[@"idleRefresh"] = dict[@"idleRefresh"];
    return out.count ? out : nil;
}

static NSDictionary *SanitizeColumnMetadata(id raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSDictionary *dict = (NSDictionary *)raw;
    NSString *label = TrimmedString(dict[@"label"]);
    if (label && label.length <= 512) out[@"label"] = dict[@"label"];
    NSString *key = TrimmedString(dict[@"automationKey"]);
    if (key && key.length <= 256) out[@"automationKey"] = dict[@"automationKey"];
    if (IsBoolNumber(dict[@"decorative"])) out[@"decorative"] = dict[@"decorative"];
    return out.count ? out : nil;
}

static NSDictionary *SanitizeGridMetadata(id raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSDictionary *dict = (NSDictionary *)raw;
    static NSSet<NSString *> *kinds = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kinds = [NSSet setWithArray:@[@"array", @"outline", @"areaList", @"collection", @"entity", @"selection", @"listSubform", @"hierarchicalList"]];
    });
    if ([dict[@"kind"] isKindOfClass:NSString.class] && [kinds containsObject:dict[@"kind"]]) {
        out[@"kind"] = dict[@"kind"];
    }
    NSString *label = TrimmedString(dict[@"label"]);
    if (label && label.length <= 512) out[@"label"] = dict[@"label"];
    NSString *keyProp = TrimmedString(dict[@"keyProperty"]);
    if (keyProp && keyProp.length <= 256) out[@"keyProperty"] = dict[@"keyProperty"];
    id keyCol = dict[@"keyColumn"];
    if ([keyCol isKindOfClass:NSString.class]) {
        if (TrimmedString(keyCol) && [(NSString *)keyCol length] <= 256) out[@"keyColumn"] = keyCol;
    } else if (IsIntNumber(keyCol) && [keyCol integerValue] >= 1) {
        out[@"keyColumn"] = keyCol;
    }
    if (IsBoolNumber(dict[@"positionalKeys"])) out[@"positionalKeys"] = dict[@"positionalKeys"];
    if ([dict[@"columns"] isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *cols = [NSMutableDictionary new];
        [(NSDictionary *)dict[@"columns"] enumerateKeysAndObjectsUsingBlock:^(id colKey, id colVal, BOOL *stop) {
            (void)stop;
            if (![colKey isKindOfClass:NSString.class] || ![(NSString *)colKey length]) return;
            NSDictionary *clean = SanitizeColumnMetadata(colVal);
            if (clean) cols[colKey] = clean;
        }];
        if (cols.count) out[@"columns"] = cols;
    }
    return out.count ? out : nil;
}

// Splits object-level "axb" into control metadata (stored in *controlOut) and grid metadata (*gridOut),
// matching install_host_methods.py:212-220 verbatim.
static void SanitizeControlMetadata(id raw, NSDictionary **controlOut, NSDictionary **gridOut) {
    *controlOut = nil;
    *gridOut = nil;
    if (![raw isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dict = (NSDictionary *)raw;
    NSMutableDictionary *control = [NSMutableDictionary new];
    if (dict[@"grid"]) {
        *gridOut = SanitizeGridMetadata(dict[@"grid"]);
    }
    NSString *label = TrimmedString(dict[@"label"]);
    if (label && label.length <= 512) control[@"label"] = dict[@"label"];
    NSString *key = TrimmedString(dict[@"automationKey"]);
    if (key && key.length <= 256) control[@"automationKey"] = dict[@"automationKey"];
    for (NSString *flag in @[@"decorative", @"multiline", @"protected"]) {
        if (IsBoolNumber(dict[flag])) control[flag] = dict[flag];
    }
    if (IsIntNumber(dict[@"layer"])) {
        NSInteger layer = [dict[@"layer"] integerValue];
        if (layer >= -32767 && layer <= 32767) control[@"layer"] = dict[@"layer"];
    }
    if ([dict[@"step"] isKindOfClass:NSNumber.class] && !IsBoolNumber(dict[@"step"]) && [dict[@"step"] doubleValue] > 0) {
        control[@"step"] = dict[@"step"];
    }
    if ([dict[@"cells"] isKindOfClass:NSArray.class]) {
        NSArray *cells = (NSArray *)dict[@"cells"];
        if (cells.count >= 1 && cells.count <= 256) {
            BOOL allValid = YES;
            for (id item in cells) {
                if (![item isKindOfClass:NSString.class] || ![(NSString *)item length] || [(NSString *)item length] > 512) {
                    allValid = NO;
                    break;
                }
            }
            if (allValid) control[@"cells"] = cells;
        }
    }
    if (control.count) *controlOut = control;
}

static NSString *Strip4DTokens(NSString *value) {
    if (!value.length || [value rangeOfString:@":"].location == NSNotFound) return value;
    static NSRegularExpression *re = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@":(?:C[0-9]+|K[0-9]+:[0-9]+|[0-9]+)" options:0 error:nil];
    });
    if (!re) return value;
    return [re stringByReplacingMatchesInString:value options:0 range:NSMakeRange(0, value.length) withTemplate:@""];
}

static NSDictionary *ExtractObjectHint(NSDictionary *obj) {
    NSMutableDictionary *hint = [NSMutableDictionary new];
    if ([obj[@"type"] isKindOfClass:NSString.class]) hint[@"type"] = obj[@"type"];
    if (IsBoolNumber(obj[@"display"]) && ![obj[@"display"] boolValue]) hint[@"display"] = @NO;
    NSString *tooltip = ResolveTooltip(obj[@"tooltip"]);
    if (tooltip) hint[@"tooltip"] = tooltip;
    NSString *placeholder = TrimmedString(obj[@"placeholder"]);
    if (placeholder && ![placeholder hasPrefix:@":xliff:"]) {
        hint[@"placeholder"] = placeholder.length > 256 ? [placeholder substringToIndex:256] : placeholder;
    }
    NSString *icon = TrimmedString(obj[@"icon"]) ?: TrimmedString(obj[@"picture"]);
    if (icon) hint[@"icon"] = icon.length > 256 ? [icon substringToIndex:256] : icon;
    NSString *dataSource = Strip4DTokens(TrimmedString(obj[@"dataSource"]));
    if (dataSource && dataSource.length <= 256) hint[@"dataSource"] = dataSource;
    if ([obj[@"type"] isEqualToString:@"listbox"]) {
        if ([obj[@"listboxType"] isKindOfClass:NSString.class]) hint[@"listboxType"] = obj[@"listboxType"];
        NSString *currentItem = Strip4DTokens(TrimmedString(obj[@"currentItemSource"]));
        if (currentItem && currentItem.length <= 256) hint[@"currentItemSource"] = currentItem;
        NSString *selectedItems = Strip4DTokens(TrimmedString(obj[@"selectedItemsSource"]));
        if (selectedItems && selectedItems.length <= 256) hint[@"selectedItemsSource"] = selectedItems;
        if (IsBoolNumber(obj[@"singleClickEdit"]) && [obj[@"singleClickEdit"] boolValue]) hint[@"singleClickEdit"] = @YES;
    }
    return hint.count ? hint : nil;
}

static NSDictionary *LoadFormDefinition(NSString *formKey, NSMutableDictionary<NSString *, NSDate *> *mtimes) {
    NSString *rel = [formKey stringByAppendingString:@"/form.4DForm"];
    NSData *data = ReadSourceFile(rel, mtimes);
    id parsed = ParseJSONData(data);
    return [parsed isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsed : nil;
}

static void CollectFormRecursive(NSString *formKey,
                                 NSMutableSet<NSString *> *visited,
                                 NSUInteger depth,
                                 NSMutableDictionary<NSString *, NSDate *> *mtimes,
                                 NSMutableDictionary *accumulated,
                                 BOOL isRoot) {
    if (depth >= kMaxInheritanceDepth || [visited containsObject:formKey]) return;
    NSDictionary *form = LoadFormDefinition(formKey, mtimes);
    if (!form) return;
    [visited addObject:formKey];
    if (isRoot) accumulated[@"found"] = @YES;

    id inheritedObj = form[@"inheritedForm"];
    if ([inheritedObj isKindOfClass:NSString.class]) {
        NSString *inherited = TrimmedString(inheritedObj);
        if (inherited && [inherited rangeOfString:@"/"].location == NSNotFound && [inherited rangeOfString:@"\\"].location == NSNotFound) {
            id tableObj = form[@"inheritedFormTable"];
            NSString *parentKey = [@"Forms/" stringByAppendingString:inherited];
            if (tableObj && ![tableObj isEqual:NSNull.null]) {
                NSString *tableStr = nil;
                if ([tableObj isKindOfClass:NSString.class]) {
                    tableStr = TrimmedString(tableObj);
                } else if ([tableObj isKindOfClass:NSNumber.class] && [tableObj integerValue] > 0) {
                    tableStr = [tableObj stringValue];
                }
                if (tableStr.length && ![tableStr isEqualToString:@"0"]) {
                    NSString *resolvedTable = State.tableNames[tableStr] ?: tableStr;
                    parentKey = [NSString stringWithFormat:@"TableForms/%@/%@", resolvedTable, inherited];
                }
            }
            CollectFormRecursive(parentKey, visited, depth + 1, mtimes, accumulated, NO);
        }
    }

    if (IsIntNumber(form[@"markerHeader"])) accumulated[@"markerHeader"] = form[@"markerHeader"];
    if (IsIntNumber(form[@"markerBody"])) accumulated[@"markerBody"] = form[@"markerBody"];

    if (isRoot) {
        if ([form[@"destination"] isKindOfClass:NSString.class]) {
            accumulated[@"destination"] = form[@"destination"];
        }
        // Form root options describe this form only; derived forms do not inherit them.
        NSDictionary *options = SanitizeFormOptions(form[@"axb"]);
        if (options) accumulated[@"options"] = options;
    }

    NSMutableDictionary *lists = accumulated[@"lists"];
    NSMutableDictionary *controls = accumulated[@"controls"];
    NSMutableDictionary *grids = accumulated[@"grids"];
    NSMutableDictionary *hints = accumulated[@"hints"];

    NSArray *pages = [form[@"pages"] isKindOfClass:NSArray.class] ? form[@"pages"] : @[];
    for (id pageObj in pages) {
        if (![pageObj isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *objects = [pageObj[@"objects"] isKindOfClass:NSDictionary.class] ? pageObj[@"objects"] : nil;
        if (!objects) continue;
        [objects enumerateKeysAndObjectsUsingBlock:^(id nameObj, id controlObj, BOOL *stop) {
            (void)stop;
            if (![nameObj isKindOfClass:NSString.class] || ![controlObj isKindOfClass:NSDictionary.class]) return;
            NSString *name = (NSString *)nameObj;
            NSDictionary *control = (NSDictionary *)controlObj;

            if (control[@"axb"]) {
                NSDictionary *storedControl = nil;
                NSDictionary *storedGrid = nil;
                SanitizeControlMetadata(control[@"axb"], &storedControl, &storedGrid);
                if (storedGrid) grids[name] = [storedGrid mutableCopy];
                if (storedControl) {
                    controls[name] = storedControl;
                } else {
                    [controls removeObjectForKey:name];
                }
            }

            if ([control[@"columns"] isKindOfClass:NSArray.class]) {
                NSMutableDictionary *columnMeta = [NSMutableDictionary new];
                for (id colObj in (NSArray *)control[@"columns"]) {
                    if (![colObj isKindOfClass:NSDictionary.class]) continue;
                    NSDictionary *col = (NSDictionary *)colObj;
                    if (!col[@"axb"]) continue;
                    NSString *colName = [col[@"name"] isKindOfClass:NSString.class] ? col[@"name"] : nil;
                    if (!colName.length) continue;
                    NSDictionary *cleanCol = SanitizeColumnMetadata(col[@"axb"]);
                    if (cleanCol) columnMeta[colName] = cleanCol;
                }
                if (columnMeta.count) {
                    NSMutableDictionary *grid = grids[name] ? [grids[name] mutableCopy] : [NSMutableDictionary new];
                    NSMutableDictionary *merged = grid[@"columns"] ? [grid[@"columns"] mutableCopy] : [NSMutableDictionary new];
                    [columnMeta enumerateKeysAndObjectsUsingBlock:^(NSString *colName, NSDictionary *colData, BOOL *innerStop) {
                        (void)innerStop;
                        NSMutableDictionary *dest = merged[colName] ? [merged[colName] mutableCopy] : [NSMutableDictionary new];
                        [dest addEntriesFromDictionary:colData];
                        merged[colName] = dest;
                    }];
                    grid[@"columns"] = merged;
                    grids[name] = grid;
                }
            }

            if ([control[@"type"] isEqualToString:@"subform"] && [control[@"listForm"] isKindOfClass:NSString.class] && [(NSString *)control[@"listForm"] length]) {
                NSString *mode = [control[@"selectionMode"] isKindOfClass:NSString.class] ? control[@"selectionMode"] : @"none";
                if (![@[@"none", @"single", @"multiple"] containsObject:mode]) mode = @"none";
                BOOL enterable = IsBoolNumber(control[@"enterableInList"]) && [control[@"enterableInList"] boolValue];
                lists[name] = @{@"selection": mode, @"enterable": @(enterable)};
            }

            NSDictionary *hint = ExtractObjectHint(control);
            if (hint) hints[name] = hint;
        }];
    }
}

static NSString *SerializeJSON(NSDictionary *dict) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!data) return @"{\"ok\":false,\"error\":\"serializationFailed\"}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{\"ok\":false,\"error\":\"serializationFailed\"}";
}

static void ClearCache(void) {
    LruOrder.clear();
    LruMap.clear();
}

static NSString *ResolvePOSIXStructurePath(NSString *projectFile) {
    if (!projectFile.length) return nil;
    NSString *path = projectFile;
    if (![path containsString:@":"] && ![path containsString:@"/"]) {
        Dl_info own = {};
        dladdr(reinterpret_cast<const void *>(&AXBFormCatalogInitialize), &own);
        NSString *binary = own.dli_fname ? @(own.dli_fname) : nil;
        NSRange bundle = [binary rangeOfString:@"/Plugins/" options:NSBackwardsSearch];
        if (bundle.location == NSNotFound) return nil;
        path = [[binary substringToIndex:bundle.location] stringByAppendingPathComponent:[path stringByAppendingPathExtension:@"4DZ"]];
    } else if (![path hasPrefix:@"/"]) {
        NSMutableArray<NSString *> *parts = [[path componentsSeparatedByString:@":"] mutableCopy];
        NSString *volume = parts.firstObject;
        [parts removeObjectAtIndex:0];
        NSString *mounted = [@"/Volumes" stringByAppendingPathComponent:volume];
        BOOL boot = ![NSFileManager.defaultManager fileExistsAtPath:mounted] || [[mounted stringByResolvingSymlinksInPath] isEqual:@"/"];
        path = [(boot ? @"/" : mounted) stringByAppendingPathComponent:[parts componentsJoinedByString:@"/"]];
    }
    return path;
}

static void ConfigureProject(NSString *structurePath) {
    ClearCache();
    State = CatalogState{};
    NSString *resolved = ResolvePOSIXStructurePath(structurePath);
    if (!resolved.length) return;
    State.structurePath = [resolved copy];
    State.initialized = YES;
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL isDir = NO;
    BOOL exists = [files fileExistsAtPath:resolved isDirectory:&isDir];
    NSURL *archive = (!isDir && [resolved.pathExtension.lowercaseString isEqualToString:@"4dz"]) ? [NSURL fileURLWithPath:resolved] : nil;
    if (isDir && ![files fileExistsAtPath:[resolved stringByAppendingPathComponent:@"Sources"]]) {
        for (NSString *entry in [[files contentsOfDirectoryAtPath:resolved error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            if ([entry.pathExtension.lowercaseString isEqualToString:@"4dz"]) {
                archive = [NSURL fileURLWithPath:[resolved stringByAppendingPathComponent:entry]];
                isDir = NO;
                break;
            }
        }
    }
    if (archive) {
        State.isArchive = YES;
        State.archiveData = [NSData dataWithContentsOfURL:archive options:NSDataReadingMappedIfSafe error:nil];
        if (State.archiveData) IndexArchive(State.archiveData);
        return;
    }
    State.isArchive = NO;
    NSURL *url = [NSURL fileURLWithPath:resolved];
    NSURL *candidate = (exists && isDir) ? url : [url URLByDeletingLastPathComponent];
    BOOL sourcesDir = NO;
    NSURL *sources = [candidate URLByAppendingPathComponent:@"Sources"];
    if ([files fileExistsAtPath:sources.path isDirectory:&sourcesDir] && sourcesDir) {
        State.sourcesURL = sources;
    } else {
        NSURL *projectSources = [[candidate URLByAppendingPathComponent:@"Project"] URLByAppendingPathComponent:@"Sources"];
        if ([files fileExistsAtPath:projectSources.path isDirectory:&sourcesDir] && sourcesDir) {
            State.sourcesURL = projectSources;
        }
    }
}

} // namespace

void AXBFormCatalogInitialize(NSString *structurePath) {
    EnsureLock();
    @synchronized(CatalogLock) {
        ConfigureProject(structurePath);
    }
}

void AXBFormCatalogShutdown(void) {
    EnsureLock();
    @synchronized(CatalogLock) {
        ClearCache();
        State = CatalogState{};
    }
}

void AXBFormCatalogSetProjectForTesting(NSString *structurePath) {
    AXBFormCatalogInitialize(structurePath);
}

NSString *AXBFormCatalogMetadataJSON(NSInteger tableNum, NSString *formName) {
    EnsureLock();
    if (!formName.length || [formName rangeOfString:@"/"].location != NSNotFound || [formName rangeOfString:@"\\"].location != NSNotFound) {
        return @"{\"ok\":true,\"found\":false}";
    }
    @synchronized(CatalogLock) {
        if (!State.initialized) {
            return @"{\"ok\":false,\"error\":\"catalogNotInitialized\"}";
        }
        RefreshAuxiliaryFiles();
        NSString *formKey = tableNum > 0
            ? [NSString stringWithFormat:@"TableForms/%ld/%@", (long)tableNum, formName]
            : [@"Forms/" stringByAppendingString:formName];
        std::string cacheKey(formKey.UTF8String);

        auto it = LruMap.find(cacheKey);
        if (it != LruMap.end()) {
            BOOL fresh = YES;
            if (!State.isArchive) {
                if (!MTimeEqual(it->second.first.catalogMTime, State.catalogMTime) ||
                    !MTimeEqual(it->second.first.tipsMTime, State.tipsMTime)) {
                    fresh = NO;
                } else {
                    for (NSString *path in it->second.first.mtimes) {
                        NSDate *nowMTime = FileMTime([NSURL fileURLWithPath:path]);
                        if (!MTimeEqual(it->second.first.mtimes[path], nowMTime)) {
                            fresh = NO;
                            break;
                        }
                    }
                }
            }
            if (fresh) {
                LruOrder.splice(LruOrder.begin(), LruOrder, it->second.second);
                return it->second.first.json;
            }
            LruOrder.erase(it->second.second);
            LruMap.erase(it);
        }

        NSMutableDictionary<NSString *, NSDate *> *mtimes = [NSMutableDictionary new];
        NSMutableDictionary *accumulated = [@{
            @"found": @NO,
            @"lists": [NSMutableDictionary new],
            @"controls": [NSMutableDictionary new],
            @"grids": [NSMutableDictionary new],
            @"hints": [NSMutableDictionary new],
        } mutableCopy];
        NSMutableSet<NSString *> *visited = [NSMutableSet new];
        CollectFormRecursive(formKey, visited, 0, mtimes, accumulated, YES);

        NSMutableDictionary *reply = [@{@"ok": @YES, @"found": accumulated[@"found"]} mutableCopy];
        if ([accumulated[@"found"] boolValue]) {
            if (accumulated[@"destination"]) reply[@"destination"] = accumulated[@"destination"];
            if (accumulated[@"options"]) reply[@"options"] = accumulated[@"options"];
            if ([accumulated[@"controls"] count]) reply[@"controls"] = accumulated[@"controls"];
            if ([accumulated[@"grids"] count]) reply[@"grids"] = accumulated[@"grids"];
            if ([accumulated[@"lists"] count]) reply[@"lists"] = accumulated[@"lists"];
            if ([accumulated[@"hints"] count]) reply[@"hints"] = accumulated[@"hints"];
            NSInteger header = accumulated[@"markerHeader"] ? [accumulated[@"markerHeader"] integerValue] : 0;
            if (accumulated[@"markerBody"]) {
                NSInteger body = [accumulated[@"markerBody"] integerValue];
                if (header >= 0 && header < body && body <= 32767) {
                    reply[@"header"] = @(header);
                    reply[@"body"] = @(body);
                }
            }
        }
        NSString *json = SerializeJSON(reply);

        if ([accumulated[@"found"] boolValue] || State.isArchive) {
            if (LruMap.size() >= kMaxCacheEntries && !LruOrder.empty()) {
                LruMap.erase(LruOrder.back());
                LruOrder.pop_back();
            }
            LruOrder.push_front(cacheKey);
            CachedEntry entry;
            entry.json = json;
            entry.mtimes = [mtimes copy];
            entry.catalogMTime = State.catalogMTime;
            entry.tipsMTime = State.tipsMTime;
            LruMap[cacheKey] = std::make_pair(entry, LruOrder.begin());
        }
        return json;
    }
}
