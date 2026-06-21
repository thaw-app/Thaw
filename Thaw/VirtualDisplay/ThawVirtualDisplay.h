//
//  ThawVirtualDisplay.h
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Creates a headless virtual display via the private CoreGraphics
/// CGVirtualDisplay API. Used to make the window server behave as multi-display
/// so that, on a single physical display, it publishes the bundle-ID "marker"
/// windows that source-PID marker-pair resolution depends on.
///
/// Returns an opaque, retained handle, or NULL when the private API is
/// unavailable or creation fails (the implementation resolves the classes at
/// runtime and catches Objective-C exceptions, so an absent or changed API
/// degrades to NULL rather than crashing). Pass the handle to
/// ThawVirtualDisplayDestroy to remove the display.
void *_Nullable ThawVirtualDisplayCreate(void);

/// The CGDirectDisplayID of a handle created by ThawVirtualDisplayCreate, or
/// 0 when the handle is NULL.
uint32_t ThawVirtualDisplayGetID(void *_Nullable handle);

/// Releases the handle and removes the virtual display.
void ThawVirtualDisplayDestroy(void *_Nullable handle);

NS_ASSUME_NONNULL_END
