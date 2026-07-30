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
        let view = WindowTransparencyEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {
        // Nothing to update: every property this view needs is fixed at
        // creation, and the transparency behavior it exists for is driven
        // by the view's own attach/detach lifecycle rather than by SwiftUI
        // state.
    }
}

/// An `NSVisualEffectView` that makes its window non-opaque with a clear
/// background for as long as it's attached, and restores the window's
/// original opacity and background color when it leaves — so a window that
/// merely *hosts* this view temporarily (like the settings window presenting
/// an onboarding sheet) gets its normal chrome back afterwards.
private final class WindowTransparencyEffectView: NSVisualEffectView {
    private weak var transparentizedWindow: NSWindow?
    private var savedIsOpaque = true
    private var savedBackgroundColor: NSColor?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        restoreWindowAppearance(unless: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if transparentizedWindow !== window {
            transparentizedWindow = window
            savedIsOpaque = window.isOpaque
            savedBackgroundColor = window.backgroundColor
        }
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private func restoreWindowAppearance(unless newWindow: NSWindow?) {
        guard let window = transparentizedWindow, window !== newWindow else { return }
        window.isOpaque = savedIsOpaque
        window.backgroundColor = savedBackgroundColor
        transparentizedWindow = nil
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
