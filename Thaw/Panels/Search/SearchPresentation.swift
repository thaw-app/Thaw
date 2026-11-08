//
//  SearchPresentation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - SearchPresentation

/// Floe's two launcher layouts; they differ only in whether the list shows
/// before you type. Raw values are stored, so never rename them.
nonisolated enum SearchPresentation: String, CaseIterable, Identifiable {
    /// The list is always shown under the search field.
    case extended
    /// Only the search field until something is typed.
    case compact

    var id: String {
        rawValue
    }

    /// Also reads the old panel styles: Compact listed nothing until you typed,
    /// Detailed and Large listed everything.
    init?(storedValue: String) {
        switch storedValue {
        case "launcher": self = .compact
        case "inspector", "assisted": self = .extended
        default: self.init(rawValue: storedValue)
        }
    }

    var localized: LocalizedStringKey {
        switch self {
        case .extended: "Extended"
        case .compact: "Compact"
        }
    }

    /// The picker's note.
    var summary: LocalizedStringKey {
        switch self {
        case .extended: "The list of items is always shown under the search field."
        case .compact: "Only the search field until you type."
        }
    }

    /// Whether the panel is only its search field for this query.
    func isCollapsed(query: String) -> Bool {
        self == .compact && query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Panel geometry

/// The search panel's measures: Floe's launcher.
nonisolated enum SearchPanelGeometry {
    /// The panel open, field and list.
    static let fullSize = CGSize(width: 750, height: 474)

    /// Room for the glass to draw its own shadow: AppKit's would outline the
    /// window's square corners.
    static let margin: CGFloat = 40

    /// The two pieces: the field's, the gap and the list's.
    static func pieceHeights(isCollapsed: Bool) -> PanelPieceHeights {
        .launcher(height: fullSize.height, isCollapsed: isCollapsed)
    }

    /// The glass the panel draws, collapsed to the field alone or open.
    static func contentSize(isCollapsed: Bool) -> CGSize {
        CGSize(width: fullSize.width, height: pieceHeights(isCollapsed: isCollapsed).total)
    }

    /// The window: the content and the margin on every side.
    static func windowSize(isCollapsed: Bool) -> CGSize {
        let content = contentSize(isCollapsed: isCollapsed)
        return CGSize(width: content.width + margin * 2, height: content.height + margin * 2)
    }

    /// Where the window goes, placed as if it were open, so the field is in
    /// the same spot on screen whether or not the panel is collapsed.
    static func frame(isCollapsed: Bool, in visibleFrame: CGRect) -> CGRect {
        let size = windowSize(isCollapsed: isCollapsed)
        let top = visibleFrame.minY + visibleFrame.height * 0.62 + windowSize(isCollapsed: false).height / 2
        let clampedTop = min(top, visibleFrame.maxY + margin)
        return CGRect(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: (clampedTop - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }
}
