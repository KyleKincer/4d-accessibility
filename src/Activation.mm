#import "Activation.h"
#include <atomic>
#include <os/lock.h>
#include <stdlib.h>

typedef NS_ENUM(NSInteger, AXBActivationMode) { AXBActivationAuto, AXBActivationOn, AXBActivationOff };

static std::atomic<bool> Active{false};
static AXBActivationMode Mode = AXBActivationAuto;
static NSString *Reason = @"";
static NSMutableArray<dispatch_block_t> *Pending; // Guarded by Lock.
static NSObject *Lock;
static id UpdateObserver;
static NSMapTable<NSWindow *, NSView *> *Sentinels; // Main thread only.
static BOOL ObservingWorkspace;
@class AXBWorkspaceObserver;
static AXBWorkspaceObserver *WorkspaceObserver;

static void Setup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ Lock = [NSObject new]; Pending = [NSMutableArray new]; });
}

// Run on the main thread's next pass through any run-loop mode: 4D's own loops do not drain
// the main queue, and an activation must not change views inside an accessibility request.
static void Later(dispatch_block_t block) {
    CFRunLoopRef main = CFRunLoopGetMain();
    CFArrayRef modes = CFRunLoopCopyAllModes(main);
    if (!modes) { dispatch_async(dispatch_get_main_queue(), block); return; }
    CFRunLoopPerformBlock(main, modes, block);
    CFRelease(modes);
    CFRunLoopWakeUp(main);
}

void AXBRunOnMain(dispatch_block_t block) { Later(block); }

BOOL AXBRunOnMainAndWait(dispatch_block_t block, NSTimeInterval timeout) {
    if (NSThread.isMainThread) { block(); return YES; }
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    Later(^{ block(); dispatch_semaphore_signal(done); });
    return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) == 0;
}

static void RemoveSentinels(void) {
    if (UpdateObserver) [NSNotificationCenter.defaultCenter removeObserver:UpdateObserver];
    UpdateObserver = nil;
    for (NSView *sentinel in Sentinels.objectEnumerator) [sentinel removeFromSuperview];
    [Sentinels removeAllObjects];
}

// Starting active runs the blocks at once on 4D's calling thread; a later activation runs them
// on the main thread's next pass.
static void Activate(NSString *reason, BOOL now) {
    NSArray<dispatch_block_t> *blocks;
    @synchronized(Lock) {
        if (Active || Mode == AXBActivationOff) return;
        Active = true;
        Reason = reason;
        blocks = Pending;
        Pending = [NSMutableArray new];
    }
    dispatch_block_t run = ^{
        RemoveSentinels();
        for (dispatch_block_t block in blocks) block();
    };
    if (now && NSThread.isMainThread) run(); else Later(run);
}

// A transparent view in each window while dormant. A client that reads the window's contents
// asks it for its children, as it asks every view; one that reads only the window does not.
@interface AXBWakeSentinel : NSView
@end
@implementation AXBWakeSentinel
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren { AXBActivationNoteRequest(); return @[]; }
@end

static void Guard(NSWindow *window) {
    if (Active || ![window isKindOfClass:NSWindow.class] || !window.contentView || [Sentinels objectForKey:window]) return;
    AXBWakeSentinel *sentinel = [[AXBWakeSentinel alloc] initWithFrame:window.contentView.bounds];
    sentinel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [window.contentView addSubview:sentinel];
    [Sentinels setObject:sentinel forKey:window];
}

// macOS keeps VoiceOver's setting on when VoiceOver quits other than by its own toggle, so the
// setting counts only while VoiceOver runs.
static BOOL VoiceOverRunning(void) {
    return NSWorkspace.sharedWorkspace.voiceOverEnabled &&
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.VoiceOver"].count > 0;
}
static id LaunchObserver;

@interface AXBWorkspaceObserver : NSObject
@end
@implementation AXBWorkspaceObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    (void)object; (void)change; (void)context;
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    if ([keyPath isEqual:@"voiceOverEnabled"] && VoiceOverRunning()) Activate(@"VoiceOver", NO);
    if ([keyPath isEqual:@"switchControlEnabled"] && workspace.switchControlEnabled) Activate(@"Switch Control", NO);
}
@end

static AXBActivationMode ReadMode(void) {
    NSString *value;
    const char *variable = getenv("AXB_ACTIVATION");
    if (variable) value = @(variable);
    else {
        id preference = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Activation"), CFSTR("io.github.kylekincer.4d-accessibility")));
        if ([preference isKindOfClass:NSString.class]) value = preference;
    }
    value = value.lowercaseString;
    if ([value isEqual:@"on"]) return AXBActivationOn;
    if ([value isEqual:@"off"]) return AXBActivationOff;
    return AXBActivationAuto;
}

void AXBActivationInitialize(void) {
    Setup();
    Mode = ReadMode();
    if (Mode == AXBActivationOn) { Activate(@"configured", YES); return; }
    if (Mode == AXBActivationOff || Active) return;
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    if (!ObservingWorkspace) {
        WorkspaceObserver = [AXBWorkspaceObserver new];
        [workspace addObserver:WorkspaceObserver forKeyPath:@"voiceOverEnabled" options:0 context:nil];
        [workspace addObserver:WorkspaceObserver forKeyPath:@"switchControlEnabled" options:0 context:nil];
        LaunchObserver = [workspace.notificationCenter addObserverForName:NSWorkspaceDidLaunchApplicationNotification object:nil queue:nil
                                                               usingBlock:^(NSNotification *note) {
            NSRunningApplication *application = note.userInfo[NSWorkspaceApplicationKey];
            if ([application.bundleIdentifier isEqual:@"com.apple.VoiceOver"]) Activate(@"VoiceOver", NO);
        }];
        ObservingWorkspace = YES;
    }
    if (VoiceOverRunning()) { Activate(@"VoiceOver", YES); return; }
    if (workspace.switchControlEnabled) { Activate(@"Switch Control", YES); return; }
    void (^guard)(void) = ^{
        if (Active || UpdateObserver) return;
        Sentinels = [NSMapTable weakToWeakObjectsMapTable];
        for (NSWindow *window in NSApp.windows) Guard(window);
        // A window updates as it first draws; checking a map is all a known window costs.
        UpdateObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidUpdateNotification object:nil queue:nil
                                                                     usingBlock:^(NSNotification *note) { Guard(note.object); }];
    };
    if (NSThread.isMainThread) guard(); else Later(guard);
}

void AXBActivationShutdown(void) {
    Setup();
    dispatch_block_t cleanup = ^{
        RemoveSentinels();
        if (ObservingWorkspace) {
            [NSWorkspace.sharedWorkspace removeObserver:WorkspaceObserver forKeyPath:@"voiceOverEnabled"];
            [NSWorkspace.sharedWorkspace removeObserver:WorkspaceObserver forKeyPath:@"switchControlEnabled"];
            [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:LaunchObserver];
            LaunchObserver = nil;
            ObservingWorkspace = NO;
        }
    };
    AXBRunOnMainAndWait(cleanup, 2);
    @synchronized(Lock) { [Pending removeAllObjects]; }
}

BOOL AXBActivationIsOff(void) { return ReadMode() == AXBActivationOff; }

static std::atomic<uint64_t> SignificantChanges{0}, MinorChanges{0};
static std::atomic<double> SettleUntil{0}, ChangedAt{0};
// How long after the user's input forms keep being described, while 4D runs what it triggered.
static const NSTimeInterval InputSettle = 1.0;

void AXBNoteChange(AXBChange change) {
    if (change == AXBChangeMinor) { MinorChanges++; return; }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    SignificantChanges++;
    ChangedAt = now;
    if (change == AXBChangeInput) SettleUntil = now + InputSettle;
}

static std::atomic<uint64_t> StructureChanges{0};
static NSMutableDictionary<NSString *, NSNumber *> *ObjectChanges; // Guarded by ObjectLock.
static os_unfair_lock ObjectLock = OS_UNFAIR_LOCK_INIT;

void AXBNoteObjectChange(NSString *name) {
    if (!Active || !name.length) { AXBNoteChange(AXBChangeSignificant); return; }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    os_unfair_lock_lock(&ObjectLock);
    uint64_t generation = ++SignificantChanges;
    if (!ObjectChanges) ObjectChanges = [NSMutableDictionary new];
    ObjectChanges[name] = @(generation);
    os_unfair_lock_unlock(&ObjectLock);
    ChangedAt = now;
}

void AXBNoteStructureChange(void) {
    StructureChanges++;
    AXBNoteChange(AXBChangeSignificant);
}

uint64_t AXBStructureGeneration(void) { return StructureChanges.load(); }

NSArray<NSString *> *AXBObjectsChangedSince(uint64_t generation, NSUInteger limit, uint64_t *latest) {
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    os_unfair_lock_lock(&ObjectLock);
    *latest = SignificantChanges.load();
    [ObjectChanges enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSNumber *changed, BOOL *stop) {
        if (changed.unsignedLongLongValue <= generation) return;
        [names addObject:name];
        if (names.count > limit) *stop = YES;
    }];
    os_unfair_lock_unlock(&ObjectLock);
    return names.count > limit ? nil : names;
}

AXBChanges AXBCurrentChanges(void) { return {SignificantChanges.load(), MinorChanges.load(), ChangedAt.load(), SettleUntil.load()}; }

static id InputMonitor;
static NSArray *KeyObservers;

void AXBObserveChanges(void) {
    if (InputMonitor) return;
    NSEventMask input = NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged | NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp |
        NSEventMaskRightMouseDown | NSEventMaskRightMouseUp | NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskScrollWheel;
    InputMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:input handler:^NSEvent *(NSEvent *event) {
        AXBNoteChange(AXBChangeInput);
        return event;
    }];
    NSMutableArray *observers = [NSMutableArray new];
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification, NSWindowDidBecomeMainNotification])
        [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                                         usingBlock:^(NSNotification *note) { (void)note; AXBNoteChange(AXBChangeSignificant); }]];
    KeyObservers = observers;
}

void AXBStopObservingChanges(void) {
    if (InputMonitor) [NSEvent removeMonitor:InputMonitor];
    InputMonitor = nil;
    for (id observer in KeyObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    KeyObservers = nil;
}

// The 4D versions whose drawing the observations were validated on, by major version.
static const unsigned int ValidatedMajors[] = {20};
static unsigned int Version;
static std::atomic<bool> HooksInstalled{false};

// PA_Get4DVersion's low 16 bits hold the version in hexadecimal digits: the major version, then
// the R release, then the patch. 0x2008 is 20.8, 0x2050 is 20 R5.
static unsigned int Major(unsigned int version) { return ((version >> 12) & 0xF) * 10 + ((version >> 8) & 0xF); }
static NSString *VersionText(unsigned int version) {
    unsigned int release = (version >> 4) & 0xF, patch = version & 0xF;
    if (release) return patch ? [NSString stringWithFormat:@"4D %u R%u.%u", Major(version), release, patch]
                              : [NSString stringWithFormat:@"4D %u R%u", Major(version), release];
    return [NSString stringWithFormat:@"4D %u.%u", Major(version), patch];
}

static NSString *HooksSetting(void) {
    const char *variable = getenv("AXB_HOOKS");
    if (variable) return @(variable).lowercaseString;
    id preference = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Hooks"), CFSTR("io.github.kylekincer.4d-accessibility")));
    return [preference isKindOfClass:NSString.class] ? [preference lowercaseString] : @"auto";
}

void AXBHooksConfigure(unsigned int version) { Version = version & 0xFFFF; }

BOOL AXBHooksAllowed(void) {
    NSString *setting = HooksSetting();
    if ([setting isEqual:@"on"]) return YES;
    if ([setting isEqual:@"off"]) return NO;
    // An unknown version is not 4D's: a test host.
    if (!Version) return YES;
    for (unsigned int major : ValidatedMajors) if (Major(Version) == major) return YES;
    return NO;
}

void AXBHooksNoteInstalled(void) { HooksInstalled = true; }

NSString *AXBHooksDescription(void) {
    NSString *version = Version ? VersionText(Version) : @"4D unknown";
    if (HooksInstalled) return [version stringByAppendingString:@"; hooks installed"];
    if (!AXBHooksAllowed()) return [version stringByAppendingString:[HooksSetting() isEqual:@"off"] ? @"; hooks off" : @"; hooks withheld"];
    return [version stringByAppendingString:@"; hooks not installed"];
}

BOOL AXBActivationIsActive(void) { return Active; }

void AXBWhenActive(dispatch_block_t block) {
    Setup();
    @synchronized(Lock) {
        if (!Active) { [Pending addObject:block]; return; }
    }
    if (NSThread.isMainThread) block(); else Later(block);
}

void AXBActivationNoteRequest(void) {
    if (!Active && Mode == AXBActivationAuto) Activate(@"accessibility client", NO);
}

NSString *AXBActivationDescription(void) {
    Setup();
    NSString *mode = Mode == AXBActivationOn ? @"on" : Mode == AXBActivationOff ? @"off" : @"auto";
    @synchronized(Lock) {
        return Active ? [NSString stringWithFormat:@"%@; active; %@", mode, Reason] : [mode stringByAppendingString:@"; dormant"];
    }
}

void AXBActivationSetActiveForTesting(BOOL active) {
    Setup();
    if (active) {
        NSArray<dispatch_block_t> *blocks;
        @synchronized(Lock) {
            if (Active) return;
            Active = true; Reason = @"test"; blocks = Pending; Pending = [NSMutableArray new];
        }
        RemoveSentinels();
        for (dispatch_block_t block in blocks) block();
    } else {
        @synchronized(Lock) { Active = false; Reason = @""; [Pending removeAllObjects]; }
    }
}

NSUInteger AXBActivationSentinelCountForTesting(void) {
    NSUInteger count = 0;
    for (NSView *sentinel in Sentinels.objectEnumerator) if (sentinel.superview) count++;
    return count;
}
