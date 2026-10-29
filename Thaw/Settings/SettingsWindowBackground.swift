//
//  SettingsWindowBackground.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// What the settings window draws behind its panes. Black replaces the dark look with pure black
/// for OLED displays; light mode and the sidebar, toolbar and rows keep their usual look.
enum SettingsWindowBackground: Equatable {
    case system
    case black

    init(isBlack: Bool) {
        self = isBlack ? .black : .system
    }

    /// The color behind the panes in a color scheme. Nil leaves the window's own background.
    func color(in scheme: ColorScheme) -> Color? {
        self == .black && scheme == .dark ? .black : nil
    }

    /// Sets the color AppKit fills the window with before SwiftUI draws, so a resize never
    /// flashes grey at the edges. The window keeps following macOS between light and dark.
    func apply(to window: NSWindow) {
        window.appearance = nil
        window.backgroundColor = self == .black ? Self.blackInDarkMode : .windowBackgroundColor
    }

    private static let blackInDarkMode = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .windowBackgroundColor
    }
}

extension EnvironmentValues {
    @Entry var settingsWindowBackground = SettingsWindowBackground.system
}

extension View {
    /// Draws the background behind this view, holds the hosting window to it, and
    /// passes it down to panes that draw their own backdrop.
    func settingsWindowBackground(_ background: SettingsWindowBackground) -> some View {
        modifier(SettingsWindowBackgroundModifier(background: background))
    }
}

private struct SettingsWindowBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let background: SettingsWindowBackground
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background {
                if let color = background.color(in: colorScheme) {
                    color.ignoresSafeArea()
                }
            }
            .environment(\.settingsWindowBackground, background)
            .onWindowChange { window in
                self.window = window
                if let window {
                    background.apply(to: window)
                }
            }
            .onChange(of: background) {
                if let window {
                    background.apply(to: window)
                }
            }
    }
}

/// A pane's own behind-window material, or the window's black when the settings window is black
/// in dark mode, so no pane shows the desktop through it.
struct SettingsPaneBackdrop: View {
    @Environment(\.settingsWindowBackground) private var windowBackground
    @Environment(\.colorScheme) private var colorScheme
    let material: NSVisualEffectView.Material

    var body: some View {
        if let color = windowBackground.color(in: colorScheme) {
            color
        } else {
            BehindWindowMaterialBackground(material: material)
        }
    }
}
