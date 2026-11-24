#import "Watcher.h"
#import "Bridge.h"
#import "GenericForms.h"
#import "Activation.h"
#import <Cocoa/Cocoa.h>
#include "4DPluginAPI.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mutex>
#include <vector>

namespace {

constexpr int kMaxUnattachedProbes = 6;
constexpr PA_long32 kWatcherStackSize = 256 * 1024;

static NSObject *WatcherLock = nil;
static NSString *WatcherStructurePath = nil;
static BOOL WatcherEnabled = NO;
static BOOL WatcherConfirmed = NO;
static BOOL WatcherStopped = NO;
static BOOL WatcherThreadStarted = NO;
static NSMutableArray<id> *WatcherObservers = nil;
static dispatch_source_t WatcherRetryTimer = nil;
static dispatch_source_t WatcherFallbackTimer = nil;
static NSMapTable<NSWindow *, NSNumber *> *WindowProbeCounts = nil;

static std::mutex SignalMutex;
static bool SignalPending = false;
static bool SignalStop = false;

static void EnsureWatcherState(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WatcherLock = [NSObject new];
        WatcherObservers = [NSMutableArray new];
        WindowProbeCounts = [NSMapTable weakToStrongObjectsMapTable];
    });
}

static NSString *JSONReply(NSDictionary *dict) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!data) return @"{\"ok\":false}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{\"ok\":false}";
}

static NSString *ResolvePOSIXPath(NSString *projectFile) {
    if (!projectFile.length) return nil;
    NSString *path = projectFile;
    if (![path containsString:@":"] && ![path containsString:@"/"]) {
        Dl_info own = {};
        dladdr(reinterpret_cast<const void *>(&AXBWatcherInitialize), &own);
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

static BOOL ComponentDirectoryHasWatcher(NSString *componentDir) {
    if (!componentDir.length) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:[componentDir stringByAppendingPathComponent:@"Resources/watcher-capabilities.json"]]) {
        return YES;
    }
    if ([files fileExistsAtPath:[componentDir stringByAppendingPathComponent:@"Project/Sources/Methods/AXB_WatcherTick.4dm"]]) {
        return YES;
    }
    return NO;
}

// Checks whether the running 4D host has an AccessibilityBridge.4dbase component
// that ships AXB_WatcherTick, before ever invoking CALL WORKER, so plugin-only
// hosts (or hosts with older components) never see a missing-method error.
static BOOL HasWatcherComponent(NSString *structurePath) {
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *imagePath = @(name);
        NSRange range = [imagePath rangeOfString:@"/AccessibilityBridge.4dbase/"];
        if (range.location != NSNotFound) {
            NSString *bundleRoot = [imagePath substringToIndex:range.location + range.length - 1];
            if (ComponentDirectoryHasWatcher(bundleRoot)) return YES;
        }
    }

    NSMutableArray<NSString *> *roots = [NSMutableArray new];
    NSString *resolved = ResolvePOSIXPath(structurePath);
    if (resolved.length) {
        NSString *dir = resolved;
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
            dir = [dir stringByDeletingLastPathComponent];
        }
        [roots addObject:dir];
        [roots addObject:[dir stringByDeletingLastPathComponent]];
    }
    Dl_info own = {};
    if (dladdr(reinterpret_cast<const void *>(&AXBWatcherInitialize), &own) && own.dli_fname) {
        NSString *binary = @(own.dli_fname);
        NSRange plugins = [binary rangeOfString:@"/Plugins/" options:NSBackwardsSearch];
        if (plugins.location != NSNotFound) {
            [roots addObject:[binary substringToIndex:plugins.location]];
        }
    }
    for (NSString *root in roots) {
        NSString *candidate = [root stringByAppendingPathComponent:@"Components/AccessibilityBridge.4dbase"];
        if (ComponentDirectoryHasWatcher(candidate)) return YES;
    }
    return NO;
}

static std::vector<PA_Unichar> ToUnichars(NSString *str) {
    std::vector<PA_Unichar> out(str.length + 1, 0);
    if (str.length) [str getCharacters:out.data() range:NSMakeRange(0, str.length)];
    return out;
}

static void PokeWatcherWorker(void) {
    std::lock_guard<std::mutex> lock(SignalMutex);
    if (SignalStop) return;
    SignalPending = true;
}

static void WatcherRelayProcess(void) {
    @autoreleasepool {
        auto cmdName = ToUnichars(@"CALL WORKER");
        PA_long32 callWorkerID = PA_GetCommandID(cmdName.data());
        PA_long32 myPID = PA_GetCurrentProcessNumber();
        while (!PA_IsProcessDying()) {
            bool hasWork = false;
            bool enabled = false;
            {
                std::lock_guard<std::mutex> lock(SignalMutex);
                if (SignalStop) break;
                if (SignalPending) {
                    SignalPending = false;
                    hasWork = true;
                }
            }
            @synchronized(WatcherLock) {
                enabled = WatcherEnabled && !WatcherStopped;
            }
            if (PA_IsProcessDying() || AXBIsStopped()) break;
            if (enabled && hasWork && callWorkerID > 0 && AXBActivationIsActive()) {
                auto workerName = ToUnichars(@"AXB_Watcher");
                auto methodName = ToUnichars(@"AXB_WatcherTick");
                PA_Unistring uWorker = PA_CreateUnistring(workerName.data());
                PA_Unistring uMethod = PA_CreateUnistring(methodName.data());
                PA_Variable params[2] = {};
                PA_SetStringVariable(&params[0], &uWorker);
                PA_SetStringVariable(&params[1], &uMethod);
                (void)PA_ExecuteCommandByID(callWorkerID, params, 2);
                PA_DisposeUnistring(&uWorker);
                PA_DisposeUnistring(&uMethod);
            }
            // Cooperative 4D sleep: 30 ticks (~500ms) while dormant, 10 ticks (~167ms) while active.
            PA_PutProcessToSleep(myPID, enabled ? 10 : 30);
        }
    }
}

static void StartRelayProcessInPluginInit(void) {
    @synchronized(WatcherLock) {
        if (WatcherStopped || WatcherThreadStarted) return;
        WatcherThreadStarted = YES;
    }
    auto procName = ToUnichars(@"$AXB_WatchRelay");
    PA_long32 pid = PA_NewProcess(reinterpret_cast<void *>(&WatcherRelayProcess), kWatcherStackSize, procName.data());
    if (pid <= 0) {
        @synchronized(WatcherLock) { WatcherThreadStarted = NO; }
    }
}

static BOOL IsCandidateWindow(NSWindow *window) {
    if (!window || ![window isKindOfClass:NSWindow.class]) return NO;
    if (!window.isVisible) return NO;
    if (window.level > NSFloatingWindowLevel) return NO;
    NSRect frame = window.frame;
    if (frame.size.width < 20 || frame.size.height < 20) return NO;
    return YES;
}

static void NoteWindowEvent(NSWindow *window, BOOL resetCount) {
    if (!IsCandidateWindow(window)) return;
    if (AXBWindowHasSession((__bridge void *)window)) return;
    BOOL shouldPoke = NO;
    @synchronized(WatcherLock) {
        if (WatcherStopped || !WatcherEnabled) return;
        NSNumber *existing = [WindowProbeCounts objectForKey:window];
        int count = resetCount ? 0 : (existing ? existing.intValue : -1);
        if (count < 0 || resetCount) {
            [WindowProbeCounts setObject:@(1) forKey:window];
            shouldPoke = YES;
        }
    }
    if (shouldPoke) PokeWatcherWorker();
}

static void ScanUnattachedWindowsOnMain(void) {
    BOOL needsPoke = NO;
    for (NSWindow *window in NSApp.windows) {
        if (!IsCandidateWindow(window)) continue;
        if (AXBWindowHasSession((__bridge void *)window)) {
            @synchronized(WatcherLock) { [WindowProbeCounts removeObjectForKey:window]; }
            continue;
        }
        @synchronized(WatcherLock) {
            NSNumber *existing = [WindowProbeCounts objectForKey:window];
            int count = existing ? existing.intValue : 0;
            if (count < kMaxUnattachedProbes) {
                [WindowProbeCounts setObject:@(count + 1) forKey:window];
                needsPoke = YES;
            }
        }
    }
    if (needsPoke) PokeWatcherWorker();
}

static void InstallObservers(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSArray<NSNotificationName> *activateNames = @[
        NSWindowDidBecomeKeyNotification,
        NSWindowDidBecomeMainNotification,
        NSWindowDidExposeNotification,
        NSWindowWillBeginSheetNotification,
    ];
    for (NSNotificationName name in activateNames) {
        id obs = [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            NoteWindowEvent(note.object, YES);
        }];
        [WatcherObservers addObject:obs];
    }
    id updateObs = [center addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NoteWindowEvent(note.object, NO);
    }];
    [WatcherObservers addObject:updateObs];
    id closeObs = [center addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSWindow *window = note.object;
        @synchronized(WatcherLock) {
            if (window) [WindowProbeCounts removeObjectForKey:window];
        }
    }];
    [WatcherObservers addObject:closeObs];

    WatcherRetryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(WatcherRetryTimer, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), 300 * NSEC_PER_MSEC, 100 * NSEC_PER_MSEC);
    __block BOOL scanPending = NO;
    dispatch_source_set_event_handler(WatcherRetryTimer, ^{
        BOOL active = NO;
        @synchronized(WatcherLock) { active = !WatcherStopped && WatcherEnabled; }
        if (!active || scanPending) return;
        CFRunLoopRef main = CFRunLoopGetMain();
        CFArrayRef modes = CFRunLoopCopyAllModes(main);
        if (!modes) return;
        scanPending = YES;
        CFRunLoopPerformBlock(main, modes, ^{
            ScanUnattachedWindowsOnMain();
            scanPending = NO;
        });
        CFRelease(modes);
        CFRunLoopWakeUp(main);
    });
    dispatch_resume(WatcherRetryTimer);
}

} // namespace

void AXBWatcherInitialize(NSString *structurePath) {
    EnsureWatcherState();
    {
        std::lock_guard<std::mutex> lock(SignalMutex);
        SignalStop = false;
        SignalPending = false;
    }
    @synchronized(WatcherLock) {
        WatcherStructurePath = [structurePath copy];
        WatcherEnabled = NO;
        WatcherConfirmed = NO;
        WatcherStopped = NO;
        WatcherThreadStarted = NO;
        [WindowProbeCounts removeAllObjects];
    }
    if (HasWatcherComponent(structurePath)) {
        StartRelayProcessInPluginInit();
    }
}

void AXBWatcherActivate(void) {
    EnsureWatcherState();
    NSString *structure = nil;
    @synchronized(WatcherLock) {
        if (WatcherStopped || WatcherEnabled) return;
        structure = WatcherStructurePath;
    }
    if (!HasWatcherComponent(structure)) {
        AXBGenericFormsSetSuppressed(NO);
        AXBGenericFormsInitialize(structure);
        return;
    }
    // Suppress GenericForms before it ever attaches an overlay to a project form.
    AXBGenericFormsSetSuppressed(YES);
    @synchronized(WatcherLock) {
        WatcherEnabled = YES;
        InstallObservers();
    }
    PokeWatcherWorker();

    // Safety fallback: if the component never confirms activation (for example, it failed
    // to load), release suppression so GenericForms still provides baseline coverage.
    WatcherFallbackTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(WatcherFallbackTimer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 250 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(WatcherFallbackTimer, ^{
        BOOL fallback = NO;
        NSString *fallbackStructure = nil;
        @synchronized(WatcherLock) {
            if (!WatcherStopped && WatcherEnabled && !WatcherConfirmed) {
                WatcherEnabled = NO;
                fallback = YES;
                fallbackStructure = WatcherStructurePath;
            }
            if (WatcherFallbackTimer) {
                dispatch_source_cancel(WatcherFallbackTimer);
                WatcherFallbackTimer = nil;
            }
        }
        if (fallback) {
            CFRunLoopRef mainLoop = CFRunLoopGetMain();
            CFArrayRef allModes = CFRunLoopCopyAllModes(mainLoop);
            if (allModes) {
                CFRunLoopPerformBlock(mainLoop, allModes, ^{
                    AXBGenericFormsSetSuppressed(NO);
                    AXBGenericFormsInitialize(fallbackStructure);
                });
                CFRelease(allModes);
                CFRunLoopWakeUp(mainLoop);
            }
        }
    });
    dispatch_resume(WatcherFallbackTimer);
}

void AXBWatcherShutdown(void) {
    EnsureWatcherState();
    {
        std::lock_guard<std::mutex> lock(SignalMutex);
        SignalStop = true;
        SignalPending = false;
    }
    NSArray *observers = nil;
    dispatch_source_t retry = nil;
    dispatch_source_t fallback = nil;
    @synchronized(WatcherLock) {
        WatcherStopped = YES;
        WatcherEnabled = NO;
        WatcherConfirmed = NO;
        WatcherThreadStarted = NO;
        observers = [WatcherObservers copy];
        [WatcherObservers removeAllObjects];
        retry = WatcherRetryTimer;
        WatcherRetryTimer = nil;
        fallback = WatcherFallbackTimer;
        WatcherFallbackTimer = nil;
        [WindowProbeCounts removeAllObjects];
    }
    if (retry) dispatch_source_cancel(retry);
    if (fallback) dispatch_source_cancel(fallback);
    for (id obs in observers) {
        [NSNotificationCenter.defaultCenter removeObserver:obs];
    }
}

NSString *AXBWatcherHandleCommand(NSString *operation, NSInteger windowID) {
    EnsureWatcherState();
    if ([operation isEqualToString:@"activate"]) {
        dispatch_source_t fallback = nil;
        @synchronized(WatcherLock) {
            WatcherConfirmed = YES;
            fallback = WatcherFallbackTimer;
            WatcherFallbackTimer = nil;
        }
        if (fallback) dispatch_source_cancel(fallback);
        AXBGenericFormsSetSuppressed(YES);
        return JSONReply(@{@"ok": @YES, @"active": @YES});
    }
    if ([operation isEqualToString:@"deactivate"]) {
        @synchronized(WatcherLock) {
            WatcherConfirmed = NO;
        }
        return JSONReply(@{@"ok": @YES, @"active": @NO});
    }
    if ([operation isEqualToString:@"hasWindow"]) {
        BOOL stopping = NO;
        @synchronized(WatcherLock) { stopping = WatcherStopped; }
        stopping = stopping || AXBIsStopped();
        return JSONReply(@{@"ok": @YES, @"hasSession": @(AXBWindowIDHasSession(windowID)), @"stopping": @(stopping)});
    }
    if ([operation isEqualToString:@"status"]) {
        BOOL active = NO, enabled = NO, stopping = NO;
        @synchronized(WatcherLock) {
            active = WatcherConfirmed;
            enabled = WatcherEnabled;
            stopping = WatcherStopped;
        }
        stopping = stopping || AXBIsStopped();
        return JSONReply(@{@"ok": @YES, @"active": @(active), @"enabled": @(enabled), @"stopping": @(stopping)});
    }
    return JSONReply(@{@"ok": @NO, @"error": @"unknownOperation"});
}
