#pragma once
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// Accessibility for 4D's own internal forms: standard messages, the Query editor and
// others that no bridge session can describe. Each form's objects are layers named
// after them; their visible text comes from DrawnText. A form adapter describes which
// layers to publish, in reading order, and this overlay publishes and operates them.
//
// An entry is a dictionary:
//   key       identifier suffix, unique within the form (required)
//   layer     the object's CALayer (required)
//   role      NSAccessibilityButtonRole, RadioButtonRole, CheckBoxRole, DisclosureTriangleRole, PopUpButtonRole,
//             TextFieldRole or StaticTextRole
//   label     a fixed label; a button without one is labelled by its drawn text
//   editable  @YES for a text field whose value can be written
//   caret     @YES for the field that holds 4D's keyboard focus and caret
//   inset     @(points) between the layer's frame and the object's own frame (default 0)
//   area      NSValue rect: the part of the layer the element covers, in the layer's points
//             from its bottom left, for one item of an object drawn as a whole
//   text      the element's own text, for such an item, instead of the layer's
//   placeholders  NSSet of texts that a text field draws only while it is empty
//   table     for NSAccessibilityTableRole: the model AXBInternalTable describes
//   press     another object's layer that a press or Show Menu clicks, with pressInset
//   pressArea NSValue rect: the part of the element's layer that a press clicks instead of its area
//   clicks    @2 for an object that a double click operates, such as adding a list's item
//   checked   for a radio button or checkbox: whether it is chosen; for a disclosure triangle,
//             whether it is expanded; absent when unknown
//   list      the key of a list entry, published before this one, that holds this element: a
//             list entry, NSAccessibilityListRole with the list's layer and label, publishes its
//             lines as its own children, so an assistive technology reads one list at a time. When
//             the scroll bar 4D draws in the list shows more lines, the list and its lines offer
//             to scroll a page down or up, as AXBInternalList describes
//   focused   @YES for the object 4D draws with its keyboard focus ring, which becomes the
//             application's focused element when it moves, as AppKit reports a Tab
// An entry without drawn text is published only when it has a fixed label or is a text field.

@class AXBInternalFormOverlay;

@interface AXBInternalFormElement : NSAccessibilityElement
@property(nonatomic, weak) AXBInternalFormOverlay *owner;
@property(nonatomic, weak) CALayer *layer;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSString *publishedText;
@property(nonatomic) BOOL editable;
@property(nonatomic) BOOL caret;
@property(nonatomic) BOOL keyboardFocused;
@property(nonatomic) CGFloat inset;
@property(nonatomic) NSRect area;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSSet<NSString *> *placeholders;
@property(nonatomic, weak) CALayer *pressLayer;
@property(nonatomic) CGFloat pressInset;
@property(nonatomic) NSRect pressArea;
@property(nonatomic) NSInteger clicks;
// The list that holds this element, if any.
@property(nonatomic, weak) AXBInternalFormElement *container;
@property(nonatomic) BOOL checked;
@property(nonatomic) BOOL stateUnknown;
- (NSRect)screenFrame;
- (NSString *)currentText;
// The caret inferred from edits, used only when 4D's editor cannot report it.
@property(nonatomic) NSRange selection;
// The caret last announced, so a move by the arrow keys can be announced in turn.
@property(nonatomic) NSRange announcedSelection;
- (BOOL)nativeSelection:(NSRange *)range;
- (void)noticeCaret;
- (NSRange)clampedSelection;
- (void)publishEditFrom:(NSString *)previous to:(NSString *)text;
@end

// A list entry's element: AXScrollDownByPage and AXScrollUpByPage, and the custom actions Scroll
// down and Scroll up, scroll the list 4D draws by a page, keeping one line, with a wheel event
// at the list, as the mouse scrolls it.
@interface AXBInternalList : AXBInternalFormElement
// A page's scroll was posted and its lines have not yet changed.
@property(nonatomic) BOOL scrolled;
- (NSArray<NSAccessibilityCustomAction *> *)scrollActions;
@end

@interface AXBInternalFormOverlay : NSView
@property(nonatomic, weak) NSView *formView;
@property(nonatomic, weak) CALayer *formLayer;
@property(nonatomic, copy) NSString *identifierPrefix;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBInternalFormElement *> *elements;
@property(nonatomic, copy) NSArray<NSString *> *order;
@property(nonatomic, weak) AXBInternalFormElement *placedFocus;
@property(nonatomic) NSTimeInterval publishedAt;
// Whether a list's scroll bar shows more lines that way, and a page's scroll that way.
- (BOOL)canScrollList:(AXBInternalFormElement *)list down:(BOOL)down;
- (BOOL)scrollList:(AXBInternalFormElement *)list down:(BOOL)down;
- (instancetype)initWithFormView:(NSView *)view prefix:(NSString *)prefix;
// Publish these entries in this order; returns YES when anything is published.
- (BOOL)updateWithEntries:(NSArray<NSDictionary *> *)entries;
- (void)releaseFocus;
- (NSRect)screenFrameForLayer:(CALayer *)layer inset:(CGFloat)inset;
// An area of a layer's image, from its bottom left, on screen; and an ordinary click at its center.
- (NSRect)screenFrameForArea:(NSRect)area inLayer:(CALayer *)layer;
- (BOOL)clickArea:(NSRect)area inLayer:(CALayer *)layer;
// For an object that reads where the pointer is rather than where a click is, as 4D's Quick
// Report sheet does: the pointer moves to the click and goes back once the action is over.
// A secondary click there, as the mouse opens a context menu.
- (BOOL)clickArea:(NSRect)area inLayer:(CALayer *)layer secondary:(BOOL)secondary movingPointer:(BOOL)pointer;
// Edit the text of an item 4D edits in place: a double click starts editing, Command-A selects
// its text, the text is typed, and Tab ends editing, as a keyboard user would.
- (BOOL)editText:(NSString *)text inArea:(NSRect)area ofLayer:(CALayer *)layer movingPointer:(BOOL)pointer;
- (NSString *)textForLayer:(CALayer *)layer;
- (void)whenSettled:(dispatch_block_t)block;
- (BOOL)clickElement:(AXBInternalFormElement *)element;
- (BOOL)focusField:(AXBInternalFormElement *)element;
- (BOOL)replaceText:(NSString *)text inElement:(AXBInternalFormElement *)element;
@end

// The view whose layer holds a form's formContext layer, or nil when an integrated form
// owns the window; and that layer.
NSView *AXBInternalFormView(NSWindow *window);
CALayer *AXBInternalFormContext(NSView *view);
CALayer *AXBInternalFormChild(CALayer *context, NSString *name);
// The items of a list 4D draws as a whole into one layer, such as a hierarchical list:
// one entry per drawn line, found from where its text is drawn, with keys under the
// prefix and the given role, and each item's drawn x as originX. Returns nil when the
// item positions are unknown.
NSArray<NSDictionary *> *AXBInternalListItems(CALayer *list, NSString *prefix, NSString *role);
// The form context inside a subform layer, or nil.
CALayer *AXBInternalSubformContext(CALayer *subform);
