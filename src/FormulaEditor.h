#pragma once
#import <Cocoa/Cocoa.h>

// Accessibility for 4D's formula editor, which the Query, Order By and Quick Report editors
// open to write a formula: a form of 4D with no application method for a bridge session. Its
// objects are layers: the lists of fields, operators and commands, the menus that choose what
// each list shows, the formula itself, and its buttons. The provider publishes them and
// operates them with ordinary clicks and keys.
void AXBFormulaEditorInitialize(void);
void AXBFormulaEditorShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes the editor.
BOOL AXBFormulaEditorRefreshWindow(NSWindow *window);
// Test support: enable the provider without 4D's drawing images.
void AXBFormulaEditorEnableForTesting(void);
