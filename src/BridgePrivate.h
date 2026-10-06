#import <Cocoa/Cocoa.h>
#import "Session.h"
@class AXBWindowView;
@class AXBNativeRoot;
BOOL AXBAttributeIsSettable(id<NSAccessibility> element, NSString *attribute);

@interface AXBNode : NSAccessibilityElement
@property(nonatomic, weak) AXBWindowView *owner;
@property(nonatomic, strong) NSDictionary *data;
@property(nonatomic, strong) NSNumber *revision;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, strong) NSAccessibilityElement *comboButton;
@property(nonatomic) BOOL live;
- (BOOL)queue:(NSString *)operation value:(id)value;
- (void)invalidate;
- (NSRect)hitFrame;
@end

@interface AXBTextNode : AXBNode
@end
@interface AXBEditableTextNode : AXBTextNode
@end

@interface AXBWindowElement : NSAccessibilityElement
@property(nonatomic, weak) AXBWindowView *owner;
@property(nonatomic, copy) NSString *identifier;
@end

@interface AXBWindowView : NSView
@property(nonatomic, strong) AXBNativeRoot *nativeRoot;
@property(nonatomic, readonly) NSView *rootContainer;
@property(nonatomic, strong) AXBSession *session;
@property(nonatomic, strong) AXBWindowElement *element;
@property(nonatomic, strong) NSArray<AXBNode *> *nodes;
@property(nonatomic, strong) NSDictionary *publishedSnapshot;
@property(nonatomic, strong) NSDictionary *actionFeedback;
@property(nonatomic, weak) AXBNode *comboOwner;
@property(nonatomic, weak) NSTableView *comboList;
@property(nonatomic, strong) id comboNativeParent;
@property(nonatomic, strong) NSArray *comboWindowChildren;
@property(nonatomic) BOOL comboWindowAccessible;
@property(nonatomic, strong) NSArray *focusObservers;
@property(nonatomic, weak) id nativeFocus;
@property(nonatomic, strong) id menuFocus;
@property(nonatomic, strong) NSDictionary *popupRequest;
@property(nonatomic, strong) NSMenu *adoptedMenu;
@property(nonatomic, strong) id menuNativeParent;
@property(nonatomic, strong) NSMenu *choiceMenu;
@property(nonatomic, weak) AXBNode *choiceNode;
@property(nonatomic, strong) NSDictionary *pictureChoice;
@property(nonatomic) BOOL live;
@property(nonatomic) BOOL omitOutsideWindow;
- (void)refresh;
- (void)refreshNativeRoot;
- (void)refreshComboPopup;
- (void)invalidate;
- (BOOL)canAct;
- (void)restoreNativeFocus;
- (void)expectPopupFrom:(id)element;
- (void)expectCheckboxFrom:(id<NSAccessibility>)element previousValue:(NSNumber *)value;
- (void)expectDisclosureFrom:(id<NSAccessibility>)element previousValue:(NSNumber *)value;
- (void)adoptPopupMenu:(NSMenu *)menu;
- (void)restorePopupMenu;
- (BOOL)showChoicesFor:(AXBNode *)node;
- (BOOL)choosePictureCell:(NSMenu *)menu;
@end

@interface AXBGridNode : AXBNode
- (void)prepareGrid;
- (void)refreshGrid;
- (id)controlForRow:(NSString *)row column:(NSString *)column;
- (id)headerForColumn:(NSString *)column;
@end
BOOL AXBGridElementBelongsToView(id element, AXBWindowView *view);
BOOL AXBIsHelpTipWindow(NSWindow *window);
BOOL AXBGridRevealMatchesElement(id element, NSDictionary *activity);
