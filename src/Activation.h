#pragma once
#import <Cocoa/Cocoa.h>

// Whether this 4D process serves an assistive technology.
//
// A process starts dormant: lifecycle areas do not start their forms' sessions, forms started by
// hand do not poll, and the providers for forms without a session and for 4D's own windows do
// not run. It becomes active, until it quits, when VoiceOver runs or Switch Control is on, or when an
// accessibility client reads the contents of one of its windows. Window managers and other
// clients that read only window titles and frames do not wake it.
//
// The mode comes from the AXB_ACTIVATION environment variable, else from the Activation
// preference in the io.github.kylekincer.4d-accessibility domain, which a configuration profile
// can manage: auto (the default) as above, on to start active, or off never to become active.
void AXBActivationInitialize(void);
// Whether the mode is off, read before anything else is installed: an off process installs no
// hooks and observers, and runs as without the plugin.
BOOL AXBActivationIsOff(void);
void AXBActivationShutdown(void);
// Thread-safe.
BOOL AXBActivationIsActive(void);
// Run on the main thread now if active, else once on activation. Blocks run in order.
void AXBWhenActive(dispatch_block_t block);
// An accessibility client asked for the contents of a 4D window.
void AXBActivationNoteRequest(void);
// The mode and state, for diagnostics: for example "auto; active; VoiceOver".
NSString *AXBActivationDescription(void);
// Run a block on the main thread's next pass through any run-loop mode, from any thread. 4D's
// own modal loops do not drain the main dispatch queue, so main-thread work must not use it.
void AXBRunOnMain(dispatch_block_t block);
// Run a block on the main thread and wait for it, at most timeout seconds when called from
// another thread. Returns whether it ran. A main thread blocked on 4D can never deadlock it.
BOOL AXBRunOnMainAndWait(dispatch_block_t block, NSTimeInterval timeout);

// Whether the plugin may observe 4D's drawing: the text it draws into its form-object layers,
// and the tab and pop-up cells AppKit draws for it. These observations depend on how 4D renders,
// which a new 4D version can change. Without them, forms with a bridge session are still
// published; forms without one, 4D's editors and standard messages are not. They start at load,
// unless the activation mode is off.
//
// The Hooks preference in the same domain, or the AXB_HOOKS environment variable, chooses: on,
// off, or auto (the default), which allows them on the 4D versions the bridge was validated on.
// Call once at load with PA_Get4DVersion's value.
void AXBHooksConfigure(unsigned int version);
BOOL AXBHooksAllowed(void);
void AXBHooksNoteInstalled(void);
// For diagnostics: for example "4D 20.8; hooks installed" or "4D 21.0; hooks withheld".
NSString *AXBHooksDescription(void);

// Test support: become active now, or return to dormant with no pending blocks.
void AXBActivationSetActiveForTesting(BOOL active);
// Test support: the number of windows carrying a wake sentinel.
NSUInteger AXBActivationSentinelCountForTesting(void);
