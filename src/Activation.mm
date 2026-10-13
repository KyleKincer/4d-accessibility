#import "Activation.h"
#include <atomic>
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
    if (NSThread.isMainThread) cleanup(); else dispatch_sync(dispatch_get_main_queue(), cleanup);
    @synchronized(Lock) { [Pending removeAllObjects]; }
}

BOOL AXBActivationIsOff(void) { return ReadMode() == AXBActivationOff; }

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
