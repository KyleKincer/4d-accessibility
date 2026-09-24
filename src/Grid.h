#import <Foundation/Foundation.h>

// Logical order and expensive cell values have independent lifetimes. All
// methods are thread-safe and use cached data only; none enter 4D or AppKit.
NSString *AXBValidateGrid(id descriptor);
NSString *AXBValidateGridChange(NSDictionary *previous, NSDictionary *next);
NSString *AXBValidateGridPage(id page);
NSString *AXBValidateGridPageForDescriptor(NSDictionary *page, NSDictionary *descriptor);
BOOL AXBGridRowAllowsEditing(NSDictionary *descriptor, NSString *row);
BOOL AXBGridRowAllowsSelection(NSDictionary *descriptor, NSString *row);

@interface AXBGrid : NSObject
@property(nonatomic, readonly) NSString *nodeID;
@property(nonatomic, readonly) NSDictionary *descriptor;
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) NSUInteger cachedPageCount;
@property(nonatomic, readonly) NSDictionary *cacheSnapshot;
- (instancetype)initWithNode:(NSString *)nodeID descriptor:(NSDictionary *)descriptor;
// Call only with validated, immutable JSON from the session exchange.
- (void)update:(NSDictionary *)descriptor;
- (NSUInteger)indexOfRow:(NSString *)key;
- (NSUInteger)indexOfColumn:(NSString *)key;
- (NSDictionary *)cellForRow:(NSString *)row column:(NSString *)column now:(NSTimeInterval)now;
// Requests are read-only and separate from the single-flight action queue.
- (NSArray *)takeRequestsAtTime:(NSTimeInterval)now;
// A stale generation/order response is ignored. Invalid current data rejects.
- (BOOL)acceptPage:(NSDictionary *)page now:(NSTimeInterval)now;
- (void)invalidate;
@end
