//
//  AppUIZoom.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

public enum AppUIZoom {
    public static let defaultsKey = "AppUIZoomPercent"
    public static let levels = [75, 90, 100, 110, 125, 150, 175, 200]

    public static func normalized(_ percent: Int) -> Int {
        levels.contains(percent) ? percent : 100
    }

    public static func next(_ percent: Int, increasing: Bool) -> Int {
        let current = normalized(percent)
        if increasing {
            return levels.first(where: { $0 > current }) ?? current
        }
        return levels.last(where: { $0 < current }) ?? current
    }
}

/// The words on the zoom commands.
public nonisolated struct AppUIZoomStrings: Sendable {
    public var zoomIn: LocalizedStringResource
    public var zoomOut: LocalizedStringResource
    public var actualSize: LocalizedStringResource
    public var level: @Sendable (_ percent: Int) -> LocalizedStringResource

    public init(
        zoomIn: LocalizedStringResource,
        zoomOut: LocalizedStringResource,
        actualSize: LocalizedStringResource,
        level: @escaping @Sendable (_ percent: Int) -> LocalizedStringResource
    ) {
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
        self.actualSize = actualSize
        self.level = level
    }
}

public struct AppUIZoomModifier: ViewModifier {
    @AppStorage(AppUIZoom.defaultsKey) private var percent = 100

    public init() {}

    public func body(content: Content) -> some View {
        let scale = CGFloat(AppUIZoom.normalized(percent)) / 100
        ZoomLayout(scale: scale) {
            content.scaleEffect(scale, anchor: .topLeading)
        }
    }
}

/// Proposes the unscaled viewport so forms reflow inside the window; a scale effect alone clips them.
/// Sizes round to whole points: at 1.1, x / 1.1 * 1.1 != x, and Settings re-lays out until AppKit aborts.
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

public struct AppUIZoomControls: View {
    @AppStorage(AppUIZoom.defaultsKey) private var percent = 100
    /// Off inside a toolbar item: one with a keyboardShortcut is vended with focused values every layout
    /// pass, and AppKit refuses the 406th constraints pass. The app menu's copy keeps the shortcuts.
    public var showsShortcuts: Bool
    let strings: AppUIZoomStrings

    public init(strings: AppUIZoomStrings, showsShortcuts: Bool = true) {
        self.strings = strings
        self.showsShortcuts = showsShortcuts
    }

    public var body: some View {
        Button(strings.zoomIn) { percent = AppUIZoom.next(percent, increasing: true) }
            .keyboardShortcut(showsShortcuts ? KeyboardShortcut("+", modifiers: .command) : nil)
            .disabled(AppUIZoom.normalized(percent) == AppUIZoom.levels.last)
        Button(strings.zoomOut) { percent = AppUIZoom.next(percent, increasing: false) }
            .keyboardShortcut(showsShortcuts ? KeyboardShortcut("-", modifiers: .command) : nil)
            .disabled(AppUIZoom.normalized(percent) == AppUIZoom.levels.first)
        Button(strings.actualSize) { percent = 100 }
            .keyboardShortcut(showsShortcuts ? KeyboardShortcut("0", modifiers: .command) : nil)
        Divider()
        Text(strings.level(AppUIZoom.normalized(percent)))
    }
}

public struct AppUIZoomCommands: Commands {
    @AppStorage(AppUIZoom.defaultsKey) private var percent = 100
    let strings: AppUIZoomStrings

    public init(strings: AppUIZoomStrings) {
        self.strings = strings
    }

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            AppUIZoomControls(strings: strings)
            // US keyboards produce '=' for Command-plus without Shift.
            Button(strings.zoomIn) { percent = AppUIZoom.next(percent, increasing: true) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
        }
    }
}
