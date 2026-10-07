#pragma once
#import <Cocoa/Cocoa.h>

// Accessibility for 4D's Query editor (QUERY with no criteria, and the standard query
// command), a form of 4D's internal runtime component with no application method for a
// bridge session. Its objects are layers named as in that form: a line subform per
// criterion, with the conjunction, field, comparison and value, and buttons to add and
// remove lines, choose the destination, and query or cancel. The provider publishes them
// and operates them with ordinary clicks and keys.
void AXBQueryEditorInitialize(void);
void AXBQueryEditorShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes a Query editor.
BOOL AXBQueryEditorRefreshWindow(NSWindow *window);
// Test support: enable the provider without 4D's drawing images.
void AXBQueryEditorEnableForTesting(void);
