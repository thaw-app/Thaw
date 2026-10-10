//
//  AppUIZoom.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

enum AppUIZoom {
    static let defaultsKey = "AppUIZoomPercent"
    static let levels = [75, 90, 100, 110, 125, 150, 175, 200]

    static func normalized(_ percent: Int) -> Int {
        levels.contains(percent) ? percent : 100
    }

    static func next(_ percent: Int, increasing: Bool) -> Int {
        let current = normalized(percent)
        if increasing {
            return levels.first(where: { $0 > current }) ?? current
        }
        return levels.last(where: { $0 < current }) ?? current
    }
}

struct AppUIZoomModifier: ViewModifier {
    @AppStorage(AppUIZoom.defaultsKey) private var percent = 100

    func body(content: Content) -> some View {
        let scale = CGFloat(AppUIZoom.normalized(percent)) / 100
        ZoomLayout(scale: scale) {
            content.scaleEffect(scale, anchor: .topLeading)
        }
    }
}

/// Propose the unscaled viewport so forms reflow and keep their scrollbars
/// within the window. A scale effect alone would clip the enlarged content.
///
/// Sizes are rounded to whole points both ways. At a scale like 1.1 the raw
/// values never come back to where they started (x / 1.1 * 1.1 != x), and the
/// window re-laid out Settings pass after pass until AppKit aborted.
private struct ZoomLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(unscaled(proposal))
        return CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: unscaled(ProposedViewSize(bounds.size))
        )
    }

    private func unscaled(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(
            width: proposal.width.map { ($0 / scale).rounded(.down) },
            height: proposal.height.map { ($0 / scale).rounded(.down) }
        )
    }
}

struct AppUIZoomControls: View {
    @AppStorage(AppUIZoom.defaultsKey) private var percent = 100
    /// Off inside a toolbar item: one that carries a keyboardShortcut is
    /// vended with focused values every layout pass, and AppKit refuses the
    /// 406th constraints pass. The app menu's copy keeps the shortcuts.
    var showsShortcuts = true

    var body: some View {
        Button("Zoom In") { percent = AppUIZoom.next(percent, increasing: true) }
            .keyboardShortcut(showsShortcuts ? KeyboardShortcut("+", modifiers: .command) : nil)
            .disabled(AppUIZoom.normalized(percent) == AppUIZoom.levels.last)
        Button("Zoom Out") { percent = AppUIZoom.next(percent, increasing: false) }
            .keyboardShortcut(showsShortcuts ? KeyboardShortcut("-", modifiers: .command) : nil)
            .disabled(AppUIZoom.normalized(percent) == AppUIZoom.levels.first)
        Button("Actual Size") { percent = 100 }
            .keyboardShortcut(showsShortcuts ? KeyboardShortcut("0", modifiers: .command) : nil)
        Divider()
        Text("Zoom: \(AppUIZoom.normalized(percent))%")
    }
}

struct AppUIZoomCommands: Commands {
    @AppStorage(AppUIZoom.defaultsKey) private var percent = 100

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            AppUIZoomControls()
            // US keyboards produce '=' for Command-plus without Shift.
            Button("Zoom In") { percent = AppUIZoom.next(percent, increasing: true) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
        }
    }
}
