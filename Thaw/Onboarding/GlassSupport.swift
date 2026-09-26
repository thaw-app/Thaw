//
//  GlassSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// An `NSVisualEffectView` that blends with whatever is behind the window,
/// with the window made non-opaque so the blend shows through.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        makeWindowTransparent(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        makeWindowTransparent(nsView)
    }

    private func makeWindowTransparent(_ view: NSView) {
        // Deferred one turn: view.window is nil until the view is attached.
        Task { @MainActor in
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

/// A small SF Symbol glyph, optionally on a frosted circular badge. Use
/// `showBackground: false` in menu bar mockups, where real icons have no badge.
struct GlassIconBubble: View {
    let symbol: String
    var size: CGFloat = 30
    var tint: Color = .primary
    var showBackground: Bool = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint.opacity(0.75))
            .frame(width: size, height: size)
            .background {
                if showBackground {
                    Circle().fill(.regularMaterial)
                }
            }
    }
}
