#import <Foundation/Foundation.h>
@class AXBGrid;

// No AppKit or 4D calls. All mutable state is protected by this object's monitor.
@interface AXBSession : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) NSInteger windowID;
@property(nonatomic, readonly) NSDictionary *snapshot;
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) NSDictionary *activity;
- (instancetype)initWithIdentifier:(NSString *)identifier windowID:(NSInteger)windowID;
- (NSDictionary *)exchange:(NSDictionary *)envelope now:(NSTimeInterval)now;
- (BOOL)enqueueNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value now:(NSTimeInterval)now;
// Native elements may lag the host snapshot. Rebase only if their complete
// target, ancestry and focus state are unchanged in the observed snapshot.
- (BOOL)enqueueNode:(NSString *)nodeID revision:(NSNumber *)revision operation:(NSString *)operation value:(id)value observedSnapshot:(NSDictionary *)observed now:(NSTimeInterval)now;
- (BOOL)canPostEditorInput:(NSDictionary *)input;
- (NSDictionary *)editorInputNode:(NSDictionary *)input;
- (void)finishEditorInput:(NSDictionary *)input accepted:(BOOL)accepted;
- (NSDictionary *)controlInputNode:(NSDictionary *)input;
- (void)finishControlInput:(NSDictionary *)input accepted:(BOOL)accepted;
- (void)noteMenuForControlInput:(NSString *)action;
- (AXBGrid *)gridForNode:(NSString *)nodeID;
// Whether the host should describe its form again now: before its first description, while an
// action or a grid's rows wait for it, after a significant change, while the user's input
// settles, and otherwise after its idle interval (the snapshot's idleRefresh seconds, else 5).
// A minor change counts, at most once a second, only when 4D's drawing is not observed: code
// that changes what a form shows otherwise redraws it. A true answer claims the changes so far.
- (BOOL)claimRefreshWithSignificant:(uint64_t)significant minor:(uint64_t)minor settleUntil:(NSTimeInterval)settleUntil
                     drawingObserved:(BOOL)drawingObserved now:(NSTimeInterval)now;
- (void)invalidate;
@end

NSString *AXBValidateEnvelope(NSDictionary *envelope);
BOOL AXBTextRangeValid(NSString *text, NSRange range);
