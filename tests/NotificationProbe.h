#pragma once
#import <Cocoa/Cocoa.h>

// Only the native test build includes this header. Observe the actual posts
// while forwarding them unchanged to AppKit.
void AXBTestPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification, NSDictionary *userInfo);
#define NSAccessibilityPostNotificationWithUserInfo AXBTestPostNotificationWithUserInfo
void AXBTestPostNotification(id element, NSAccessibilityNotificationName notification);
#define NSAccessibilityPostNotification AXBTestPostNotification
