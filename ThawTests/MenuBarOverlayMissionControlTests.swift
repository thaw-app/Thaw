//
//  MenuBarOverlayMissionControlTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The overlay fades only for a genuine Mission Control / Exposé, identified by
/// WindowManager's shield window — not for "click wallpaper to reveal desktop",
/// which parks windows the same way but keeps the menu bar (and its tint)
/// visible.
@MainActor
struct MenuBarOverlayMissionControlTests {
    @Test
    func shieldWindowRecognizesMissionControlExposeShield() {
        #expect(
            MenuBarOverlayPanel.isMissionControlShieldWindow(
                ownerName: "WindowManager",
                title: "ExposeShieldWindow"
            )
        )
    }

    @Test
    func shieldWindowRejectsRevealDesktopAndOrdinaryWindows() {
        // "Reveal desktop" raises no Exposé shield; ordinary WindowManager
        // windows (wallpaper, event shield) must not be mistaken for it.
        #expect(!MenuBarOverlayPanel.isMissionControlShieldWindow(ownerName: "WindowManager", title: "Wallpaper"))
        #expect(!MenuBarOverlayPanel.isMissionControlShieldWindow(ownerName: "WindowManager", title: "Event Shield Window"))
        #expect(!MenuBarOverlayPanel.isMissionControlShieldWindow(ownerName: "Dock", title: "ExposeShieldWindow"))
        #expect(!MenuBarOverlayPanel.isMissionControlShieldWindow(ownerName: nil, title: nil))
    }
}
