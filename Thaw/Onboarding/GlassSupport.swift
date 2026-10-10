//
//  GlassSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// A behind-window blend that also makes its window non-opaque, used as the
/// onboarding ground. SwiftUI has no behind-window blend, so this is not a
/// ThawGlass tier; content drawn over it uses .thawGlass(_:in:).
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        makeWindowTransparent(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        configure(nsView)
        makeWindowTransparent(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = false
    }

    private func makeWindowTransparent(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

/// A plain monochrome SF Symbol, drawn like a real status item so the mockup
/// bars read as a menu bar rather than a row of buttons.
struct GlassIconBubble: View {
    let symbol: String
    var size: CGFloat = 30
    var tint: Color = .primary
    /// Ignored; kept so existing call sites still compile.
    var showBackground: Bool = false

    var body: some View {
        // Resizable, not font-sized: a font symbol centers its line box, so
        // the glyph sits high. Scaling its own bounds centers the ink.
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .foregroundStyle(tint.opacity(0.75))
            .frame(width: size * 0.46, height: size * 0.46)
            .frame(width: size, height: size)
    }
}
