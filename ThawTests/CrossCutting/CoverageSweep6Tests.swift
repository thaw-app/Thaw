//
//  CoverageSweep6Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Testing
@testable import Thaw

/// Coverage sweep, part 6: the live display and window-server adapters that
/// earlier sweeps left uncovered because their *values* depend on the machine
/// running the suite.
///
/// The trick that makes them testable anyway: assert **invariants** instead of
/// values. `getMenuBarHeightEstimate()` never returns a non-positive height on
/// any hardware — the notch-aware fallback guarantees it — and
/// `frameOfNotch` is non-nil exactly when the screen has a notch, whether or
/// not the runner's display has one. Hosted tests run with a real
/// WindowServer session, so the queries themselves are exercised for real.
///
/// Deliberate gaps, and why:
///
/// - `NSStatusItem.showMenu(_:)` runs a modal menu-tracking loop.
/// - `NSScreen.invalidateMenuBarHeightCache()` would throw away state the
///   host app is relying on mid-run.
/// - The secondary-screen branch of `computeApplicationMenuFrame()` needs a
///   second attached display.
/// - `Hotkey.enable()` / `HotkeyAction.perform(appState:)` need Carbon
///   registration and a live `AppState`.
/// - `DiagnosticLogger`'s file-opening and pruning paths write real log files
///   into the shared log directory.
@MainActor
@Suite("Coverage sweep 6: live display and window-server adapters", .serialized)
struct CoverageSweep6Tests {
    // MARK: - NSScreen

    @Test("The first screen is the primary display")
    func firstScreenIsPrimaryDisplay() throws {
        let screen = try #require(NSScreen.screens.first)
        #expect(screen.displayID == CGMainDisplayID())
    }

    @Test("The notch frame exists exactly when the screen has a notch")
    func notchFrameMatchesHasNotch() {
        for screen in NSScreen.screens {
            #expect((screen.frameOfNotch != nil) == screen.hasNotch)
            if let notch = screen.frameOfNotch {
                #expect(notch.width > 0)
            }
        }
    }

    @Test("The screen with the mouse contains the mouse location")
    func screenWithMouseContainsMouse() {
        if let screen = NSScreen.screenWithMouse {
            #expect(screen.frame.contains(NSEvent.mouseLocation))
        }
    }

    @Test("The screen with the active menu bar is an attached screen")
    func screenWithActiveMenuBarIsAttached() {
        if let screen = NSScreen.screenWithActiveMenuBar {
            #expect(NSScreen.screens.contains(screen))
        }
    }

    @Test("The menu bar height estimate is always positive and stable")
    func menuBarHeightEstimateIsPositiveAndStable() throws {
        let screen = try #require(NSScreen.screens.first)
        let first = screen.getMenuBarHeightEstimate()
        let second = screen.getMenuBarHeightEstimate()
        #expect(first > 0)
        #expect(second == first)
        // The optional variant agrees with the estimate whenever the live
        // window-list query succeeds.
        if let live = screen.getMenuBarHeight() {
            #expect(live == first)
        }
    }

    @Test("Cleaning up disconnected display caches keeps connected entries")
    func cleanupKeepsConnectedDisplayEntries() throws {
        let screen = try #require(NSScreen.screens.first)
        let before = screen.getMenuBarHeightEstimate()
        NSScreen.cleanupDisconnectedDisplayCaches()
        NSScreen.cleanupDisconnectedDisplayCaches()
        #expect(screen.getMenuBarHeightEstimate() == before)
    }

    @Test("The application menu frame, when readable, has a positive width")
    func applicationMenuFrameHasPositiveWidth() throws {
        let screen = try #require(NSScreen.screens.first)
        // Without Accessibility trust this returns nil; with it, the reduced
        // union of enabled menu children. Both arms are valid outcomes.
        if let frame = screen.getApplicationMenuFrame() {
            #expect(frame.width > 0)
            // A second read is served from the per-display cache.
            #expect(screen.getApplicationMenuFrame() == frame)
        } else {
            #expect(screen.getApplicationMenuFrame(bypassCache: true) == nil)
        }
        _ = screen.isSystemMenuBarVisible()
    }

    // MARK: - WindowInfo

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

    @Test("The null window ID resolves to no window")
    func nullWindowIDResolvesToNoWindow() {
        #expect(WindowInfo(windowID: kCGNullWindowID) == nil)
    }

    // MARK: - AXIdentityCatalog

    @Test("A snapshot of no hosts is empty")
    func snapshotOfNoHostsIsEmpty() {
        #expect(AXIdentityCatalog.snapshot(hosts: []).isEmpty)
    }

    @Test("A snapshot of the current app only yields framed identities")
    func snapshotOfCurrentAppYieldsFramedIdentities() {
        // The test host has no extras menu bar, so this normally returns [].
        // The point is driving the live-AX adapter: application lookup,
        // messaging timeouts, and the extras-menu-bar guard all run for real.
        let identities = AXIdentityCatalog.snapshot(hosts: [.current])
        #expect(identities.allSatisfy { $0.frame.width >= 0 })
    }

    // MARK: - DiagLog

    @Test("Every DiagLog level forwards without diagnostic logging enabled")
    func diagLogLevelsForwardWhenDisabled() {
        // DiagnosticLogger.shared is disabled in tests, so these hit the
        // os.Logger passthrough and the shared logger's disabled check —
        // no files are opened or written.
        let log = DiagLog(category: "CoverageSweep6")
        log.debug("debug \(42)")
        log.info("info")
        log.notice("notice")
        log.warning("warning")
        log.error("error")
        #expect(!DiagnosticLogger.shared.isEnabled)
    }
}
