//
//  WindowInfoDerivedTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Thaw

// MARK: - Fixtures

/// A display identifier no Mac hands out. Core Graphics answers with an
/// empty rect for it, the one display geometry that is the same everywhere.
private let unknownDisplay = CGDirectDisplayID(0xDEAD_BEEF)

/// Pins the two Core Graphics facts every fixture in this file rests on:
/// an unknown display reports an empty rect, and an empty rect contains the
/// empty rect. If either stops holding, the zero-bounds cases would pass for
/// the wrong reason.
private func requireContainableEmptyDisplay() throws {
    let bounds = CGDisplayBounds(unknownDisplay)
    try #require(
        bounds.isEmpty,
        "An unknown display is expected to report an empty rect, got \(bounds)"
    )
    try #require(
        bounds.contains(CGRect.zero),
        "An empty rect is expected to contain the empty rect"
    )
}

/// The four attributes `menuBarWindow(from:for:)` requires of a window,
/// one case per clause of its predicate.
private enum MenuBarWindowRule: String, CaseIterable, Sendable {
    case ownedByTheWindowServer
    case onScreen
    case atTheMainMenuLayer
    case titledMenubar
}

// MARK: - Suite

/// Covers the parts of `Shared/Utilities/WindowInfo.swift` that answer
/// without a window server: the two selection rules, and the enumeration
/// paths that refuse before reaching one.
///
/// `CGDisplayBounds` reports an empty rect for an unknown display, and an
/// empty rect contains itself, so a zero-bounds window satisfies the
/// containment clause of both rules on any machine. That frees the other
/// clauses to be asserted one at a time; a window with real bounds pins
/// the containment clause itself.
///
/// `menuBarWindow(from:for:)` is how `NSScreen.getMenuBarHeight()` finds the
/// window it measures, and that height places every managed item. A dropped
/// clause would match another window and return a plausible but wrong height.
///
/// The window server paths are covered by `WindowInfoLiveTests` below. The
/// Dock-owned arm of `wallpaperWindow(from:for:)` is pinned here from the
/// other side by a non-Dock owner.
@Suite("Window info lookups without a window server")
struct WindowInfoDerivedTests {
    // MARK: - Enumeration refusals

    /// `Bridging.createCGWindowArray(with:)` documents that it returns `nil`
    /// for an empty list, or for a list none of whose elements is a valid bit
    /// pattern. Both refusals happen before any window server call, so these
    /// are the two enumeration inputs whose answer is fixed.
    @Suite("Enumerating nothing")
    struct EnumerationRefusalTests {
        @Test("Asking for no windows returns no windows")
        func emptyRequestReturnsNoWindows() {
            #expect(WindowInfo.createWindows(from: []).isEmpty)
        }

        /// Zero is the null window identifier and has no valid bit pattern,
        /// so a request made entirely of zeroes cannot be built into a query
        /// at all. Returning an empty list rather than falling through to an
        /// unfiltered enumeration is the load-bearing part.
        @Test("A request made only of null identifiers returns no windows")
        func nullIdentifiersReturnNoWindows() {
            #expect(WindowInfo.createWindows(from: [0]).isEmpty)
            #expect(WindowInfo.createWindows(from: [0, 0, 0]).isEmpty)
        }

        @Test("A window cannot be built from the null identifier")
        func nullIdentifierBuildsNoWindow() {
            #expect(WindowInfo(windowID: 0) == nil)
        }
    }

    // MARK: - Menu bar window

    /// The rule names four attributes and a containment. Each case below
    /// leaves exactly one unsatisfied, so a dropped clause fails on its own.
    @Suite("Picking the menu bar window out of a list")
    struct MenuBarWindowTests {
        /// A window carrying every attribute the rule asks for. Its bounds
        /// are zero so that the containment clause holds against
        /// `unknownDisplay`; the cases that are about containment pass real
        /// bounds instead.
        private func candidate(
            windowID: CGWindowID = 1,
            bounds: CGRect = .zero,
            layer: Int = Int(kCGMainMenuWindowLevel),
            title: String? = "Menubar",
            ownerName: String? = "Window Server",
            isOnScreen: Bool = true
        ) -> WindowInfo {
            WindowInfo(
                windowID: windowID,
                ownerPID: 1,
                bounds: bounds,
                layer: layer,
                title: title,
                ownerName: ownerName,
                isOnScreen: isOnScreen
            )
        }

        @Test("An empty list has no menu bar window")
        func emptyListHasNoMenuBarWindow() {
            #expect(WindowInfo.menuBarWindow(from: [], for: unknownDisplay) == nil)
        }

        @Test("A window carrying every attribute is the menu bar window")
        func fullyMatchingWindowIsFound() throws {
            try requireContainableEmptyDisplay()
            let window = candidate()

            #expect(WindowInfo.menuBarWindow(from: [window], for: unknownDisplay) == window)
        }

        @Test("Every attribute is required", arguments: MenuBarWindowRule.allCases)
        fileprivate func everyAttributeIsRequired(_ unsatisfied: MenuBarWindowRule) throws {
            try requireContainableEmptyDisplay()

            let rejected: WindowInfo = switch unsatisfied {
            case .ownedByTheWindowServer: candidate(windowID: 2, ownerName: "Some App")
            case .onScreen: candidate(windowID: 2, isOnScreen: false)
            case .atTheMainMenuLayer: candidate(windowID: 2, layer: Int(kCGMainMenuWindowLevel) + 1)
            case .titledMenubar: candidate(windowID: 2, title: "Menu Bar")
            }
            let accepted = candidate(windowID: 1)

            #expect(WindowInfo.menuBarWindow(from: [rejected], for: unknownDisplay) == nil)
            // And the rejection is a rejection of that window, not of the
            // whole list: a good window later in the list is still found.
            #expect(WindowInfo.menuBarWindow(from: [rejected, accepted], for: unknownDisplay) == accepted)
        }

        /// A window server window titled `Menubar` on the right layer still
        /// belongs to whichever display it sits on. Without this clause
        /// `getMenuBarHeight()` would measure another display's menu bar on a
        /// multi-display Mac.
        @Test("A window that lies outside the display is not its menu bar window")
        func windowOutsideTheDisplayIsRejected() throws {
            let window = candidate(bounds: CGRect(x: 0, y: 0, width: 1440, height: 24))
            try #require(
                !CGDisplayBounds(unknownDisplay).contains(window.bounds),
                "The fixture window has to lie outside the display for this case to mean anything"
            )

            #expect(WindowInfo.menuBarWindow(from: [window], for: unknownDisplay) == nil)
        }

        /// The list is scanned in order, and callers treat the answer as
        /// *the* menu bar window rather than one of several.
        @Test("The earliest matching window wins")
        func earliestMatchWins() throws {
            try requireContainableEmptyDisplay()
            let first = candidate(windowID: 10)
            let second = candidate(windowID: 11)

            let found = try #require(WindowInfo.menuBarWindow(from: [first, second], for: unknownDisplay))
            #expect(found.windowID == 10)
        }
    }

    // MARK: - Wallpaper window

    /// The wallpaper rule is owner-first: it asks the running application
    /// behind the window's process identifier for its bundle identifier
    /// before it looks at anything else. Both cases below are about that
    /// clause, from either side of a window that has an owner at all.
    @Suite("Picking the wallpaper window out of a list")
    struct WallpaperWindowTests {
        private func candidate(
            ownerPID: pid_t,
            bounds: CGRect = .zero,
            title: String? = "Wallpaper-1"
        ) -> WindowInfo {
            WindowInfo(
                windowID: 1,
                ownerPID: ownerPID,
                bounds: bounds,
                layer: 0,
                title: title,
                ownerName: "Dock"
            )
        }

        @Test("An empty list has no wallpaper window")
        func emptyListHasNoWallpaperWindow() {
            #expect(WindowInfo.wallpaperWindow(from: [], for: unknownDisplay) == nil)
        }

        /// `pid_max` is five digits on macOS, so this identifier can never
        /// name a running process and the owner lookup is guaranteed to come
        /// back empty. The window is otherwise built to look exactly like a
        /// wallpaper window, including its owner *name*, which the rule
        /// deliberately does not consult.
        @Test("A window owned by no running process is not the wallpaper")
        func unownedWindowIsNotTheWallpaper() throws {
            let window = candidate(ownerPID: 999_999)
            try #require(
                window.owningApplication == nil,
                "The fixture only means anything while its process identifier names nothing"
            )

            #expect(WindowInfo.wallpaperWindow(from: [window], for: unknownDisplay) == nil)
        }

        /// The rule is not "owned by something" but "owned by the Dock", and
        /// the one application a unit test can be certain is running is its
        /// own. Anything else would either need the Dock to be up or leave
        /// the clause pinned only against a nil owner, which a check as loose
        /// as `owningApplication != nil` would also satisfy.
        @Test("A window owned by an application other than the Dock is not the wallpaper")
        func nonDockWindowIsNotTheWallpaper() throws {
            try requireContainableEmptyDisplay()
            let window = candidate(ownerPID: ProcessInfo.processInfo.processIdentifier)
            let owner = try #require(
                window.owningApplication,
                "The test process has to be able to see itself for this case to mean anything"
            )
            #expect(owner.bundleIdentifier != "com.apple.dock")

            #expect(WindowInfo.wallpaperWindow(from: [window], for: unknownDisplay) == nil)
        }
    }
}

// MARK: - Live window server

/// Runs the CGS query chain against the hosted session. A bare CI session may
/// have no menu bar or wallpaper window, so each lookup is checked only when
/// it returns one.
@MainActor
@Suite("Window info lookups against the window server", .serialized)
struct WindowInfoLiveTests {
    @Test("The menu bar window, when present, sits on its display")
    func menuBarWindowSitsOnItsDisplay() {
        let display = CGMainDisplayID()
        // A hosted test session has a menu bar; a bare CI session may not.
        // Either way the CGS query chain runs for real.
        if let window = WindowInfo.menuBarWindow(for: display) {
            #expect(window.title == "Menubar")
            #expect(window.bounds.height > 0)
            #expect(CGDisplayBounds(display).contains(window.bounds))
            // Round-trip through the failable single-window initializer.
            let sameWindow = WindowInfo(windowID: window.windowID)
            #expect(sameWindow?.windowID == window.windowID)
            // currentBounds re-queries live state for the same window.
            if let bounds = window.currentBounds() {
                #expect(bounds.height > 0)
            }
        }
    }

    @Test("The wallpaper window, when present, sits on its display")
    func wallpaperWindowSitsOnItsDisplay() {
        let display = CGMainDisplayID()
        if let window = WindowInfo.wallpaperWindow(for: display) {
            #expect(window.owningApplication?.bundleIdentifier == "com.apple.dock")
            #expect(CGDisplayBounds(display).contains(window.bounds))
        }
    }
}
