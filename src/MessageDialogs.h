#pragma once
#import <Cocoa/Cocoa.h>

// Accessibility for 4D's standard message windows (ALERT, CONFIRM, Request).
//
// These are internal 4D forms with no application method, so no bridge session can
// describe them. Their objects are layers named main, ok, cancel, box and so on; the
// visible text comes from DrawnText. The provider publishes the message, the buttons
// and the Request field, and presses a button with an ordinary click at its center.
void AXBMessagesInitialize(void);
void AXBMessagesShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes a message window.
BOOL AXBMessagesRefreshWindow(NSWindow *window);
// Test support: enable the provider without 4D's drawing images.
void AXBMessagesEnableForTesting(void);
// Shared with the other internal 4D forms: the view whose layer holds a form's
// formContext layer, or nil when an integrated form owns the window; and that layer.
NSView *AXBInternalFormView(NSWindow *window);
CALayer *AXBInternalFormContext(NSView *view);
