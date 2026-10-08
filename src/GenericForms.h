#pragma once
#import <Cocoa/Cocoa.h>

// Baseline accessibility for an application's own 4D forms that have no bridge session.
//
// 4D draws each form object into a layer named after the object; its visible text comes from
// DrawnText. The project's form definitions name each object's type, title and help tip.
// The provider matches a window's object layers to one form of the project, then publishes
// its buttons, texts, inputs, checkboxes, radio buttons and pop-ups in reading order, and
// operates them with ordinary clicks and keys. A form with a bridge session is left to it.
// The project's folder or file, as a POSIX or 4D's HFS path.
void AXBGenericFormsInitialize(NSString *projectFile);
void AXBGenericFormsShutdown(void);
// Inspect one window now (also used by tests). Returns YES when it publishes a form.
BOOL AXBGenericFormsRefreshWindow(NSWindow *window);
// Test support: index these form definitions, by form name, instead of a project's.
void AXBGenericFormsEnableForTesting(NSDictionary<NSString *, NSDictionary *> *forms);
// Test support: the form definitions inside a component archive, described by name.
NSDictionary<NSString *, NSDictionary *> *AXBGenericFormsArchivedFormsForTesting(NSString *path);
// Test support: the name a list box without a caption takes from its object name.
NSString *AXBGenericFormsListNameForTesting(NSString *object);
