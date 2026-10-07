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
//   role      NSAccessibilityButtonRole, PopUpButtonRole, TextFieldRole or StaticTextRole
//   label     a fixed label; a button without one is labelled by its drawn text
//   editable  @YES for a text field whose value can be written
//   caret     @YES for the field that holds 4D's keyboard focus and caret
//   inset     @(points) between the layer's frame and the object's own frame (default 0)
//   area      NSValue rect: the part of the layer the element covers, in the layer's points
//             from its bottom left, for one item of an object drawn as a whole
//   text      the element's own text, for such an item, instead of the layer's
//   placeholders  NSSet of texts that a text field draws only while it is empty
//   press     another object's layer that a press or Show Menu clicks, with pressInset
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
@property(nonatomic) CGFloat inset;
@property(nonatomic) NSRect area;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSSet<NSString *> *placeholders;
@property(nonatomic, weak) CALayer *pressLayer;
@property(nonatomic) CGFloat pressInset;
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

@interface AXBInternalFormOverlay : NSView
@property(nonatomic, weak) NSView *formView;
@property(nonatomic, weak) CALayer *formLayer;
@property(nonatomic, copy) NSString *identifierPrefix;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AXBInternalFormElement *> *elements;
@property(nonatomic, copy) NSArray<NSString *> *order;
@property(nonatomic, weak) AXBInternalFormElement *placedFocus;
@property(nonatomic) NSTimeInterval publishedAt;
- (instancetype)initWithFormView:(NSView *)view prefix:(NSString *)prefix;
// Publish these entries in this order; returns YES when anything is published.
- (BOOL)updateWithEntries:(NSArray<NSDictionary *> *)entries;
- (void)releaseFocus;
- (NSRect)screenFrameForLayer:(CALayer *)layer inset:(CGFloat)inset;
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
// The form context inside a subform layer, or nil.
CALayer *AXBInternalSubformContext(CALayer *subform);
