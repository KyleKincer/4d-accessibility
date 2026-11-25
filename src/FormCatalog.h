#pragma once
#import <Foundation/Foundation.h>

// Native read-only form metadata catalog backed by loose Project/Sources/ files
// or a compiled .4DZ archive. Thread-safe with an LRU cache.
void AXBFormCatalogInitialize(NSString *structurePath);
void AXBFormCatalogShutdown(void);
// Returns JSON text for the given form (tableNum == 0 for project forms).
NSString *AXBFormCatalogMetadataJSON(NSInteger tableNum, NSString *formName);
// Exposed for native unit tests without 4DPluginAPI.
void AXBFormCatalogSetProjectForTesting(NSString *structurePath);
