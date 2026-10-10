//
//  MenuBarPresentationProvider+ItemSession.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import MenuBarModel
import PlatformRuntimeKit

/// Retroactive so it needs no kit release and works against the published
/// binary.
extension RuntimeItemSessionController: @retroactive MenuBarItemSessionTracking {}

extension MenuBarPresentationProvider {
    /// The native menu-tracking session, when the running platform backend
    /// provides it.
    ///
    /// A conditional cast, so an older binary yields nil and callers fall back
    /// to the accessibility paths.
    static var itemSessionTracking: (any MenuBarItemSessionTracking)? {
        current as? any MenuBarItemSessionTracking
    }
}
