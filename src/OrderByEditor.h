#pragma once
#import <Cocoa/Cocoa.h>

// Accessibility for 4D's Order By editor (ORDER BY with no criteria), a form of 4D with no
// application method for a bridge session. Its objects are layers: the available fields, the
// fields and formulas the selection is ordered by, the buttons that move them, and Sort.
// The provider publishes them and operates them with ordinary clicks.
void AXBOrderByEditorInitialize(void);
void AXBOrderByEditorShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes the editor.
BOOL AXBOrderByEditorRefreshWindow(NSWindow *window);
// Test support: enable the provider without 4D's drawing images.
void AXBOrderByEditorEnableForTesting(void);
