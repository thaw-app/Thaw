//
//  SettingsChrome.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.

import AppKit
import SwiftUI

/// Behind-window vibrancy so surfaces sample the desktop rather than the
/// system-owned NavigationSplitView backdrop beneath the SwiftUI layer.
public struct BehindWindowMaterialBackground: NSViewRepresentable {
    public let material: NSVisualEffectView.Material

    public init(
        material: NSVisualEffectView.Material
    ) {
        self.material = material
    }

    public func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

/// The system glass button, unmodified, so a Settings button looks like one
/// in System Settings and follows macOS as the style changes.
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    public static var settingsGlass: GlassButtonStyle {
        .glass
    }
}
