//
//  AppMenuHidingRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// When Thaw takes app menus out of the bar, as one row: while hidden items
/// are showing, to make room for them, and while the desktop is in front,
/// where the Finder's menus would otherwise sit.
struct AppMenuHidingRow: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        ToggleButtonRow("Hide app menus") {
            Toggle("When showing items", isOn: $settings.hideApplicationMenus)
                .help("Hides the current app's menus when hidden items need the room.")
            Toggle(isOn: $settings.enableDesktopMenuHiding) {
                HStack(spacing: ThawSpacing.compact) {
                    Text("On the desktop")
                    ThawBadge.alpha
                }
            }
            .help("Covers the Finder's menus after you click the desktop, until you switch to something else.")
        }
        .annotation(
            "Makes room in the menu bar by taking app menus out of it. The Apple menu always stays.",
            more: """
            When showing items, macOS requires \(Constants.displayName) to show itself in the Dock while the \
            menus are hidden. On the desktop, Finder windows keep their menus, and the cover is a \
            capture of what sits behind the bar so it matches your wallpaper. Without Screen Recording it \
            falls back to a flat patch of the bar's average color, which can show against the wallpaper.
            """
        )
    }
}
