//
//  ApplicationMenuCoverPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - MenuBarTitleFrame

/// One application-menu title, as Accessibility reports it.
///
/// Order matters and is the caller's responsibility to preserve: the Apple menu
/// is identified by being first, not by its title, which is the only property
/// that holds across localizations.
nonisolated struct MenuBarTitleFrame: Equatable, Sendable {
    let role: String?
    let frame: CGRect
}

// MARK: - DesktopFocusState

/// What the Finder currently has focused, reduced to the distinction that
/// matters here.
///
/// Finder is frontmost both when the user clicks the desktop and when they are
/// working in a Finder window, and the menu bar looks identical in the two
/// cases. Only the first is "the desktop", and hiding the menus while someone
/// is actually using a Finder window would be a bug rather than a feature.
nonisolated enum DesktopFocusState: Equatable, Sendable {
    /// No focused window, or the focused window is the desktop itself. Live
    /// probing on 27 shows Finder always publishing exactly one AX window with
    /// role=AXScrollArea, subrole=AXDesktop, and AXFocusedWindow nil while
    /// nothing else is focused.
    case desktop

    /// A real Finder window has focus. The menus belong to that window.
    case window

    /// Finder is not frontmost at all.
    case notFinder

    /// Classifies from what Accessibility answered.
    ///
    /// - Parameters:
    ///   - frontmostBundleIdentifier: The frontmost application's bundle id.
    ///   - hasFocusedWindow: Whether AXFocusedWindow returned an element.
    ///   - focusedWindowSubrole: That element's AXSubrole, when there was one.
    static func classify(
        frontmostBundleIdentifier: String?,
        hasFocusedWindow: Bool,
        focusedWindowSubrole: String?
    ) -> DesktopFocusState {
        guard frontmostBundleIdentifier == ApplicationMenuCoverPolicy.finderBundleIdentifier else {
            return .notFinder
        }
        guard hasFocusedWindow else {
            return .desktop
        }
        return focusedWindowSubrole == ApplicationMenuCoverPolicy.desktopSubrole ? .desktop : .window
    }
}

// MARK: - ApplicationMenuCoverPolicy

/// Decides whether the application menus should be covered, and what rect the
/// cover occupies.
///
/// Split out from ApplicationMenuCover so both decisions can be tested
/// without a live menu bar, the same split AlertRevealPolicy and
/// RecordingWatchPolicy use.
nonisolated enum ApplicationMenuCoverPolicy {
    static let finderBundleIdentifier = "com.apple.finder"

    /// The subrole Finder gives the desktop's AX window.
    static let desktopSubrole = "AXDesktop"

    /// Menu bar children that are actually menu titles. On macOS 27 the menu
    /// bar's AX children can also include status-item hosts, which are not
    /// menus and must not be covered.
    static let titleRoles: Set<String> = ["AXMenuBarItem", "AXMenuItem"]

    static func shouldCover(_ state: DesktopFocusState) -> Bool {
        state == .desktop
    }

    /// The rect covering every application menu title except the Apple menu.
    ///
    /// The Apple menu stays exposed: it is the system's, and hiding About This
    /// Mac, Sleep, Restart and Shut Down behind an opaque strip would be worse
    /// than the clutter this removes. NSScreen.getApplicationMenuFrame() is
    /// unusable for the same reason, since it unions every title.
    ///
    /// The Apple menu is found by position, not title: AXTitle is localized
    /// and macOS 27 leaves it empty on many menu bar elements.
    ///
    /// Returns nil when there is nothing to cover, no titles, or only the
    /// Apple menu, which is what a menu bar mid-transition looks like.
    static func coverRect(forOrderedTitles titles: [MenuBarTitleFrame]) -> CGRect? {
        let menuTitles = titles.filter { title in
            title.role.map(titleRoles.contains) ?? false
        }
        guard let apple = menuTitles.first, menuTitles.count > 1 else {
            return nil
        }

        let covered = menuTitles.dropFirst().reduce(into: CGRect.null) { union, title in
            union = union.union(title.frame)
        }
        guard !covered.isNull, covered.width > 0 else {
            return nil
        }

        // Adjacent titles overlap by a point, Apple ends at 44.0 where Finder
        // begins at 43.0, so start at whichever edge is further right, or the
        // cover clips the Apple menu's own frame.
        let leadingEdge = max(covered.minX, apple.frame.maxX)
        guard leadingEdge < covered.maxX else {
            return nil
        }

        return CGRect(
            x: leadingEdge,
            y: covered.minY,
            width: covered.maxX - leadingEdge,
            height: covered.height
        )
    }
}
