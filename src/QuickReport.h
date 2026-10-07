#pragma once
#import <Cocoa/Cocoa.h>

// Accessibility for 4D's Quick Report editor (QR REPORT with the editor shown), a form of
// 4D with no application method for a bridge session. Its objects are layers: a toolbar,
// the report area, a status line and, while it is open, the sheet that chooses the
// report's columns. The provider publishes them and operates them with ordinary clicks.
void AXBQuickReportInitialize(void);
void AXBQuickReportShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes the editor.
BOOL AXBQuickReportRefreshWindow(NSWindow *window);
// Test support: enable the provider without 4D's drawing images.
void AXBQuickReportEnableForTesting(void);
