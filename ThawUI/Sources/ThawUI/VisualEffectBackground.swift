//
//  VisualEffectBackground.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// A behind-window blend that makes its window non-opaque, for the onboarding ground. SwiftUI has no
/// behind-window blend, so this isn't a ThawGlass tier; content over it uses .thawGlass(_:in:).
public struct VisualEffectBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = TransparentWindowEffectView()
        configure(view)
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        configure(nsView)
        nsView.window?.makeTransparent()
    }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = false
    }
}

/// Clears its window when it joins one, which comes after SwiftUI's first update pass.
private final class TransparentWindowEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeTransparent()
    }
}

private extension NSWindow {
    func makeTransparent() {
        isOpaque = false
        backgroundColor = .clear
    }
}
