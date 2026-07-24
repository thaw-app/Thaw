//
//  GlassSupport.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// A true see-through glass pane: an `NSVisualEffectView` blending with
/// whatever is *behind the window* (desktop, other apps), and making the
/// window itself non-opaque so that blend has something real to show —
/// rather than a synthetic colored backdrop standing in for it.
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

/// A small SF Symbol glyph, optionally drawn on a frosted circular badge —
/// the welcome orbit's "planet" look wants a badge (so it reads as a
/// floating object), but a real macOS menu bar icon is just a plain
/// monochrome glyph with no background shape at all. Set
/// `showBackground: false` for the demo menu bar mockups so they look like
/// an authentic bar instead of a row of buttons.
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
