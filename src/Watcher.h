#pragma once
#import <Foundation/Foundation.h>

// Zero-area automatic window watcher for AccessibilityBridge.4dbase.
// Activation-gated: starts nothing while dormant and never runs on 4D Server.
void AXBWatcherInitialize(NSString *structurePath);
void AXBWatcherActivate(void);
void AXBWatcherShutdown(void);
NSString *AXBWatcherHandleCommand(NSString *operation, NSInteger windowID);
