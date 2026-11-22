//
//  ThawBarOpeningCapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Each presentation owns its first capture. A closing panel's task cannot
/// release a newer panel's loading state.
@MainActor
@Observable
final class ThawBarOpeningCapture {
    var isPending = true

    /// A partial snapshot still has items that would briefly show their app icons.
    @ViewBuilder
    func row(
        for items: [MenuBarItem],
        cache: MenuBarItemImageCache,
        prefersAppIcons: Bool,
        canCapture: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        var hasMissingCapture: Bool {
            items.contains { MenuBarItemImageCache.image(for: $0.tag, in: cache.images) == nil }
        }
        if isPending, !prefersAppIcons, canCapture, hasMissingCapture {
            Text("Loading menu bar items…")
                .padding(.horizontal, 10)
        } else {
            content()
        }
    }
}
