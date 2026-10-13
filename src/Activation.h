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
// Test support: become active now, or return to dormant with no pending blocks.
void AXBActivationSetActiveForTesting(BOOL active);
// Test support: the number of windows carrying a wake sentinel.
NSUInteger AXBActivationSentinelCountForTesting(void);
