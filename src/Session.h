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
// The same for an envelope that already passed AXBValidateEnvelope and was parsed, immutable,
// from at most AXBLimits::payload bytes of JSON: it is neither validated nor copied again.
- (NSDictionary *)exchangeParsed:(NSDictionary *)envelope now:(NSTimeInterval)now;
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
// What the host last took of the changes since its last description: the significant-change and
// whole-form counts, and whether the idle interval asks to check every object again. Guarded by the session.
@property(atomic) uint64_t takenChanges, takenStructure;
@property(atomic) BOOL verificationDue;
// Whether the host should describe its form again now: before its first description, while an
// action or a grid's rows wait for it, after significant changes once they pause for a quarter
// second (or a second after the last description while they continue: describing a list in
// mid-scroll, or a field in mid-typing, is outdated at once), once the user's input settles, and
// otherwise after its idle interval (the snapshot's idleRefresh seconds, else 30 while 4D's drawing
// is observed and 5 when it is not). A minor change
// counts, at most once a second, only when 4D's drawing is not observed: code that changes what
// a form shows otherwise redraws it. A true answer claims the changes so far.
- (BOOL)claimRefreshWithSignificant:(uint64_t)significant minor:(uint64_t)minor changedAt:(NSTimeInterval)changedAt
                         settleUntil:(NSTimeInterval)settleUntil drawingObserved:(BOOL)drawingObserved now:(NSTimeInterval)now;
- (void)invalidate;
@end

NSString *AXBValidateEnvelope(NSDictionary *envelope);
// The envelope's parts other than its snapshot, against the snapshot's nodes by identifier.
NSString *AXBValidateEnvelopeParts(NSDictionary *envelope, NSDictionary *byID);
// A host that holds the tree it last sent sends less: for an unchanged form, the revision the
// session holds ({"version":1,"revision":n,"unchanged":true}); otherwise the window's metadata
// with the next revision, the one it replaces as "base", and as "changed" only the nodes that
// changed (none, when only the window's metadata did), each replacing the node with its id.
// Whether an envelope is such a brief one.
BOOL AXBEnvelopeIsBrief(id envelope);
// The complete envelope a brief one stands for, from the snapshot the session holds, validated as
// if it had been sent whole; nil, with the reason, when it does not apply to that snapshot.
NSDictionary *AXBExpandEnvelope(NSDictionary *envelope, NSDictionary *known, NSString **error);
BOOL AXBTextRangeValid(NSString *text, NSRange range);
