//
//  OutOfRoomWarning.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Layout pane's warning while macOS hides items it has no room for on the bar.
struct OutOfRoomWarning: View {
    /// The Visible items macOS is not drawing, or empty when Thaw cannot tell which.
    let hiddenItemNames: [String]

    var body: some View {
        SettingsWarningPill(
            title: "Some items don’t fit in the menu bar",
            message: Self.message(naming: hiddenItemNames),
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange
        )
    }

    static func message(naming names: [String]) -> LocalizedStringResource {
        guard !names.isEmpty else {
            return "macOS is hiding items it has no room for on this display. Move some items to Hidden to make room."
        }
        let list = names.formatted(.list(type: .and))
        return "macOS is hiding items it has no room for on this display, including \(list). Move some items to Hidden to make room."
    }
}

/// Watches macOS's overflow for the display the bars show, so cache walks do not re-diff the whole pane.
struct OutOfRoomSync: ViewModifier {
    let itemManager: MenuBarItemManager
    let presence: NativeOverflowPresence
    let sync: (Bool, [String]) -> Void

    func body(content: Content) -> some View {
        let isOutOfRoom = presence.isPresent(on: itemManager.itemDisplayID)
        content.onChange(of: isOutOfRoom, initial: true) {
            report(isOutOfRoom)
        }
        .onChange(of: itemManager.itemsNotShownOnBarTags) {
            report(isOutOfRoom)
        }
    }

    private func report(_ isOutOfRoom: Bool) {
        let names = isOutOfRoom ? LayoutBanner.namesNotDrawn(
            visibleItems: itemManager.managedItems(for: .visible),
            notDrawnTags: itemManager.itemsNotShownOnBarTags
        ) : []
        sync(isOutOfRoom, names)
    }
}
