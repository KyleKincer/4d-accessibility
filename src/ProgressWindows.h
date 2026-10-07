#pragma once
#import <Cocoa/Cocoa.h>

// Accessibility for the windows of 4D's Progress component (Progress New and friends).
//
// The component draws each progress in its own form, with no application method for a
// bridge session to describe. Its objects are layers named Message1 (the title),
// ThermoProgress (the bar), Message2 (the message), StopButton, and ProgressValue, an
// off-window copy of the progress; the visible text comes from DrawnText. The provider
// publishes each progress as an indicator labelled with its title, its message, and its
// Stop button, which it presses with an ordinary click at its center.
void AXBProgressInitialize(void);
void AXBProgressShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes progress.
BOOL AXBProgressRefreshWindow(NSWindow *window);
// Test support: enable the provider without 4D's drawing images.
void AXBProgressEnableForTesting(void);
