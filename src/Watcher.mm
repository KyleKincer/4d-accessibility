#import "Watcher.h"
#import "Bridge.h"
#import "GenericForms.h"
#import "Activation.h"
#import <Cocoa/Cocoa.h>
#include "4DPluginAPI.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <vector>

namespace {

constexpr int kMaxUnattachedProbes = 6;

static NSObject *WatcherLock = nil;
static dispatch_queue_t WatcherQueue = nil;
static NSString *WatcherStructurePath = nil;
static BOOL WatcherEnabled = NO;
static BOOL WatcherConfirmed = NO;
static BOOL WatcherStopped = NO;
static BOOL WatcherInFlight = NO;
static BOOL WatcherPending = NO;
static NSString *WatcherPendingReason = nil;
static NSMutableArray<id> *WatcherObservers = nil;
static dispatch_source_t WatcherRetryTimer = nil;
static dispatch_source_t WatcherFallbackTimer = nil;
static NSMapTable<NSWindow *, NSNumber *> *WindowProbeCounts = nil;

static void EnsureWatcherState(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WatcherLock = [NSObject new];
        WatcherQueue = dispatch_queue_create("io.github.kylekincer.axb.watcher", DISPATCH_QUEUE_SERIAL);
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

static void ScheduleWatcherPoke(NSString *reason);

static void WatcherBootstrapEntry(void) {
    @autoreleasepool {
        NSString *reason = nil;
        BOOL shouldRun = NO;
        @synchronized(WatcherLock) {
            shouldRun = !WatcherStopped && WatcherEnabled && !AXBIsStopped();
            reason = WatcherPendingReason ?: @"poke";
            WatcherPendingReason = nil;
        }
        if (shouldRun && AXBActivationIsActive()) {
            auto cmdName = ToUnichars(@"CALL WORKER");
            PA_long32 callWorkerID = PA_GetCommandID(cmdName.data());
            if (callWorkerID > 0) {
                auto workerName = ToUnichars(@"AXB_Watcher");
                auto methodName = ToUnichars(@"AXB_WatcherTick");
                auto reasonChars = ToUnichars(reason);
                PA_Unistring uWorker = PA_CreateUnistring(workerName.data());
                PA_Unistring uMethod = PA_CreateUnistring(methodName.data());
                PA_Unistring uReason = PA_CreateUnistring(reasonChars.data());
                PA_Variable params[3] = {};
                PA_SetStringVariable(&params[0], &uWorker);
                PA_SetStringVariable(&params[1], &uMethod);
                PA_SetStringVariable(&params[2], &uReason);
                (void)PA_ExecuteCommandByID(callWorkerID, params, 3);
                PA_DisposeUnistring(&uWorker);
                PA_DisposeUnistring(&uMethod);
                PA_DisposeUnistring(&uReason);
            }
        }
        BOOL runAgain = NO;
        NSString *nextReason = nil;
        @synchronized(WatcherLock) {
            WatcherInFlight = NO;
            if (WatcherPending && !WatcherStopped && WatcherEnabled) {
                WatcherPending = NO;
                runAgain = YES;
                nextReason = WatcherPendingReason ?: @"coalesced";
                WatcherPendingReason = nil;
            }
        }
        if (runAgain) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), WatcherQueue, ^{
                ScheduleWatcherPoke(nextReason);
            });
        }
    }
}

static void SpawnWatcherBootstrap(void *context) {
    (void)context;
    @autoreleasepool {
        BOOL stopped = NO;
        @synchronized(WatcherLock) { stopped = WatcherStopped || !WatcherEnabled; }
        if (stopped) {
            @synchronized(WatcherLock) { WatcherInFlight = NO; }
            return;
        }
        auto procName = ToUnichars(@"$AXB_WatchBoot");
        PA_long32 pid = PA_NewProcess(reinterpret_cast<void *>(&WatcherBootstrapEntry), 0, procName.data());
        if (pid <= 0) {
            @synchronized(WatcherLock) { WatcherInFlight = NO; }
        }
    }
}

static void ScheduleWatcherPoke(NSString *reason) {
    EnsureWatcherState();
    BOOL launch = NO;
    @synchronized(WatcherLock) {
        if (WatcherStopped || !WatcherEnabled || AXBIsStopped()) return;
        if (WatcherInFlight) {
            WatcherPending = YES;
            WatcherPendingReason = [reason copy];
            return;
        }
        WatcherInFlight = YES;
        WatcherPending = NO;
        WatcherPendingReason = [reason copy];
        launch = YES;
    }
    if (!launch) return;
    dispatch_async(WatcherQueue, ^{
        BOOL stopped = NO;
        @synchronized(WatcherLock) { stopped = WatcherStopped || !WatcherEnabled; }
        if (stopped) {
            @synchronized(WatcherLock) { WatcherInFlight = NO; }
            return;
        }
        PA_RunInMainProcess(SpawnWatcherBootstrap, nullptr);
        if (PA_GetLastError() != eER_NoErr) {
            @synchronized(WatcherLock) { WatcherInFlight = NO; }
        }
    });
}

static BOOL IsCandidateWindow(NSWindow *window) {
    if (!window || ![window isKindOfClass:NSWindow.class]) return NO;
    if (!window.isVisible) return NO;
    if (window.level > NSFloatingWindowLevel) return NO;
    NSRect frame = window.frame;
    if (frame.size.width < 20 || frame.size.height < 20) return NO;
    return YES;
}

static void NoteWindowEvent(NSWindow *window, NSString *reason, BOOL resetCount) {
    if (!IsCandidateWindow(window)) return;
    if (AXBWindowHasSession((__bridge void *)window)) return;
    BOOL shouldPoke = NO;
    @synchronized(WatcherLock) {
        if (WatcherStopped || !WatcherEnabled) return;
        NSNumber *existing = [WindowProbeCounts objectForKey:window];
        int count = resetCount ? 0 : (existing ? existing.intValue : -1);
        if (count < 0) {
            [WindowProbeCounts setObject:@(1) forKey:window];
            shouldPoke = YES;
        } else if (resetCount) {
            [WindowProbeCounts setObject:@(1) forKey:window];
            shouldPoke = YES;
        }
    }
    if (shouldPoke) ScheduleWatcherPoke(reason);
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
    if (needsPoke) ScheduleWatcherPoke(@"retry");
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
            NoteWindowEvent(note.object, @"window", YES);
        }];
        [WatcherObservers addObject:obs];
    }
    id updateObs = [center addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NoteWindowEvent(note.object, @"update", NO);
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
    @synchronized(WatcherLock) {
        WatcherStructurePath = [structurePath copy];
        WatcherEnabled = NO;
        WatcherConfirmed = NO;
        WatcherStopped = NO;
        WatcherInFlight = NO;
        WatcherPending = NO;
        WatcherPendingReason = nil;
        [WindowProbeCounts removeAllObjects];
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
    ScheduleWatcherPoke(@"start");

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
            CFRunLoopRef main = CFRunLoopGetMain();
            CFArrayRef modes = CFRunLoopCopyAllModes(main);
            if (modes) {
                CFRunLoopPerformBlock(main, modes, ^{
                    AXBGenericFormsSetSuppressed(NO);
                    AXBGenericFormsInitialize(fallbackStructure);
                });
                CFRelease(modes);
                CFRunLoopWakeUp(main);
            }
        }
    });
    dispatch_resume(WatcherFallbackTimer);
}

void AXBWatcherShutdown(void) {
    EnsureWatcherState();
    NSArray *observers = nil;
    dispatch_source_t retry = nil;
    dispatch_source_t fallback = nil;
    @synchronized(WatcherLock) {
        WatcherStopped = YES;
        WatcherEnabled = NO;
        WatcherConfirmed = NO;
        WatcherPending = NO;
        WatcherPendingReason = nil;
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
