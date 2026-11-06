//
//  MenuBarPresentationProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The stateful per-process agent session must be constructed and accessed on MainActor.
/// Consumers use MenuBarPresentationControlling.isSupported, not OS version, to gate reveal, global hide, and auto-show.
@MainActor
enum MenuBarPresentationProvider {
    private static let controller = RuntimeItemSessionController()

    static let current: any MenuBarPresentationControlling = controller

    /// Open the shared session at launch when gated to test coexistence with the kit's visibility restriction.
    static func startDiagnosticSessionIfGated() {
        guard RuntimeItemSessionController.isDiagnosticGateEnabled else {
            return
        }
        controller.start()
    }
}

extension MenuBarPresentationProvider {
    /// Spotlight support comes from the platform package's controller conformance; nil means unavailable on older binaries.
    static var itemSpotlighting: (any MenuBarItemSpotlighting)? {
        controller as any MenuBarItemSpotlighting
    }
}
