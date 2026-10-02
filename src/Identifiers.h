#import <Foundation/Foundation.h>

// Public locators never participate in session, cache or action identity.
// Encode UTF-8 segments separately: a slash in an object name is not a path.
static inline NSString *AXBIdentifierSegment(NSString *value) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}
static inline NSString *AXBIdentifierAppend(NSString *base, NSArray<NSString *> *segments) {
    NSMutableString *path = [base mutableCopy];
    for (NSString *segment in segments) [path appendFormat:@"/%@", AXBIdentifierSegment(segment)];
    return path;
}
static inline NSString *AXBRootIdentifier(NSDictionary *snapshot) {
    return AXBIdentifierAppend(@"axb", @[snapshot[@"automationKey"] ?: @"form"]);
}
static inline NSString *AXBNodeIdentifier(NSDictionary *snapshot, NSDictionary *node) {
    return AXBIdentifierAppend(AXBRootIdentifier(snapshot), node[@"automationPath"] ?: @[node[@"id"]]);
}
