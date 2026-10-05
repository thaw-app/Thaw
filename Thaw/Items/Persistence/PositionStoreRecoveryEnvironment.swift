//
//  PositionStoreRecoveryEnvironment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
import ThawCapture

extension PositionStoreItemSource.Environment {
    /// The app's store, hosting-surface reader and AX window IDs, for the
    /// kit's recovery of items no application publishes.
    @MainActor
    static var thaw: Self {
        Self(
            positionStore: { MenuBarPositionStoreProvider.current },
            readHostingSurface: { items, displayID in
                guard !ScreenLock.isLocked,
                      let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID),
                      !ScreenLock.isLocked else {
                    return nil
                }
                // The hosting surface draws items on a transparent background,
                // so the knock-out would only add noise.
                let reading = MenuBarItemImageCache.verdict(for: items, from: capture, knockingOutBackground: false)
                return .init(seen: reading.seen, blank: reading.blank)
            },
            syntheticWindowID: { namespace, title, instanceIndex in
                MenuBarItemAXProvider.syntheticWindowID(
                    namespace: namespace,
                    title: title,
                    instanceIndex: instanceIndex
                )
            }
        )
    }
}
