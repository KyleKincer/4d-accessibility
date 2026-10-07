#pragma once
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// Text that 4D draws into its own form-object layers.
//
// 4D renders each form object into a bitmap on a background thread and installs the
// image as the contents of a CALayer named after the object. This module observes the
// CoreText calls made by 4D's own images and follows the drawn text through the bitmap
// image to the layer. It never changes what is drawn.

// Install the observation once. Returns NO when no 4D image imports the observed calls.
BOOL AXBDrawnTextInitialize(void);
BOOL AXBDrawnTextAvailable(void);
// The strings most recently drawn into this layer's contents, in drawing order, or nil.
NSArray<NSString *> *AXBDrawnTextForLayer(CALayer *layer);
// Called on the main thread after a layer with one of these names receives new
// drawn text, or contents without text that clear its previous text. Each owner
// has one observer; a nil observer removes that owner's.
void AXBDrawnTextSetObserver(NSString *owner, NSSet<NSString *> *names, void (^observer)(CALayer *layer));
// Test support: record text for a synthetic layer as if 4D had drawn it; nil clears it.
void AXBDrawnTextRecordForTesting(CALayer *layer, NSArray<NSString *> *texts);
// Test support: the image table that follows text from a bitmap to a layer.
NSArray<NSString *> *AXBDrawnTextForImageForTesting(CGImageRef image);
void AXBDrawnTextRecordImageForTesting(CGImageRef image, NSArray<NSString *> *texts);
