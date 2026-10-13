#pragma once
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

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
// The entry that describes a list box drawn in this layer as a table of its drawn rows, for an
// overlay: the bridge uses it for a list box no grid adapter describes. info holds the list box's
// width and height and its columns ([{header, width, hidden}]), headerHeight and showHeaders, as
// a form definition does; label names it, else the words of its object name.
NSDictionary *AXBGenericListboxEntry(CALayer *layer, NSDictionary *info, NSString *key, NSString *label, NSString *objectName);
// Inspect one window now (also used by tests). Returns YES when it publishes a form.
BOOL AXBGenericFormsRefreshWindow(NSWindow *window);
// Test support: index these form definitions, by form name, instead of a project's.
void AXBGenericFormsEnableForTesting(NSDictionary<NSString *, NSDictionary *> *forms);
// Test support: the form definitions inside a component archive, described by name.
NSDictionary<NSString *, NSDictionary *> *AXBGenericFormsArchivedFormsForTesting(NSString *path);
// The words of an object name, for an object no text labels: "btnRefreshOrders" is Refresh Orders,
// "lb_shipping_limits" Shipping limits. nil for 4D's default names and names that say nothing.
NSString *AXBGenericFormsObjectName(NSString *object, BOOL button);
// Test support: the name an object no text labels takes from its object name, as a list box or
// a button, and the name a button takes from its picture file.
NSString *AXBGenericFormsObjectNameForTesting(NSString *object, BOOL button);
NSString *AXBGenericFormsPictureNameForTesting(NSString *path);
