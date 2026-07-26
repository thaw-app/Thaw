//
//  MenuBarChevronCover.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import PlatformRuntimeKit

/// Covers the native macOS 27 overflow chevron with a clean, menu-bar-matched
/// strip (plan 031).
///
/// Five independent reverse-engineering passes established that the chevron —
/// the `‹···›` / "Double backward chevron" indicator MenuBarAgent draws when
/// Thaw conceals third-party items — cannot be removed, suppressed, moved, or
/// touched by any third-party means: it is a `CALayer` inside MenuBarAgent's
/// SkyLight window, and control requires the Apple-only entitlement
/// `com.apple.private.menubar.allow`. The only path left is to *cover* it.
///
/// This is the first, deliberately minimal instantiation: a borderless,
/// click-eating panel filled with the menu bar's average color, positioned over
/// the chevron's detected bounds.
///
/// It runs its **own** detection poll (via `RuntimeOverflowChevronProbe`) rather
/// than piggybacking the section controller's `nativeOverflowDisplayIDs`: that
/// signal is populated by an event-gated probe that does not fire while a
/// chevron simply persists, so the cover would miss it. Polling keeps the cover
/// self-sufficient — and lets the decoy test harness exercise it on demand.
///
/// Behind ``Defaults/Key/debugChevronCover`` while it proves out. Known
/// follow-ups: background *fidelity* (a solid color is a first cut; the 27 bar
/// is translucent, so real coverage needs wallpaper + blur matching); a cheaper
/// trigger than a blind poll for production (e.g. only while items are hidden);
/// and pre-emptive covering at the restriction-apply point to beat the flash.
@MainActor
final class MenuBarChevronCover {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    /// One cover panel per display that currently shows a chevron.
    private var panels: [CGDirectDisplayID: NSPanel] = [:]

    private let diagLog = DiagLog(category: "MenuBarChevronCover")

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Defaults.Key.debugChevronCover.rawValue)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState

        // Detection poll + re-tint on menu-bar color change + reposition on
        // screen-layout change, coalesced.
        Publishers.Merge(
            Timer.publish(every: 0.75, on: .main, in: .common).autoconnect().map { _ in () },
            appState.menuBarManager.$averageColors.map { _ in () }
        )
        .sink { [weak self] in
            self?.update()
        }
        .store(in: &cancellables)

        update()
    }

    /// Detects chevrons on every display and reconciles the cover panels.
    private func update() {
        guard isEnabled else {
            teardownAll()
            return
        }

        let additionalOwners = Self.additionalChevronOwners()
        var covered = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            let displayID = screen.displayID
            let chevrons = RuntimeOverflowChevronProbe.detectChevrons(
                in: CGDisplayBounds(displayID),
                additionalOwnerBundleIDs: additionalOwners
            )
            guard let coverRect = coverFrame(for: chevrons) else { continue }
            present(displayID: displayID, coverRect: coverRect)
            covered.insert(displayID)
        }

        for displayID in panels.keys where !covered.contains(displayID) {
            teardown(displayID)
        }
    }

    /// The union of the chevron bounds, converted from top-left CG global
    /// coordinates to bottom-left Cocoa global coordinates, or `nil` when there
    /// is nothing to cover.
    private func coverFrame(for bounds: [CGRect]) -> CGRect? {
        let valid = bounds.filter { !$0.isNull && !$0.isEmpty }
        guard var union = valid.first else { return nil }
        for rect in valid.dropFirst() {
            union = union.union(rect)
        }
        // Both CG-global and Cocoa-global share the primary display's left
        // origin; they differ only by a vertical flip about the primary's
        // height. `NSScreen.screens.first` is the primary (menu-bar) screen,
        // whose frame origin is (0, 0).
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
        return CGRect(
            x: union.origin.x,
            y: primaryMaxY - union.maxY,
            width: union.width,
            height: union.height
        )
    }

    private func present(displayID: CGDirectDisplayID, coverRect: CGRect) {
        let isNew = panels[displayID] == nil
        let panel = panels[displayID] ?? makePanel()
        panels[displayID] = panel

        panel.setFrame(coverRect, display: true)
        panel.backgroundColor = fillColor(for: displayID)
        if !panel.isVisible {
            panel.orderFront(nil)
        }
        if isNew {
            diagLog.notice("cover shown on display \(displayID) at \(NSStringFromRect(coverRect))")
        }
    }

    private func fillColor(for displayID: CGDirectDisplayID) -> NSColor {
        if let info = appState?.menuBarManager.averageColors[displayID] {
            return NSColor(cgColor: info.color) ?? .black
        }
        return .black
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = true
        panel.hasShadow = false
        // Above the chevron's menu-bar level (24); the same level Thaw's other
        // menu-bar overlays use.
        panel.level = .mainMenu + 1
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        // Absorbs clicks (default) so tapping the covered chevron cannot expand
        // it; nonactivating so absorbing the click never steals focus.
        panel.ignoresMouseEvents = false
        // Exclude from screen capture at the window level so Thaw's own refresh
        // loop can never re-ingest the cover (public equivalent of the SkyLight
        // sharing-state fix).
        panel.sharingType = .none
        panel.contentView = NSView()
        return panel
    }

    private func teardown(_ displayID: CGDirectDisplayID) {
        guard let panel = panels.removeValue(forKey: displayID) else { return }
        panel.orderOut(nil)
        diagLog.notice("cover removed on display \(displayID)")
    }

    private func teardownAll() {
        guard !panels.isEmpty else { return }
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    /// Extra process bundle identifiers whose chevron-shaped items the probe
    /// should also accept, read from the `Thaw.debugChevronProbeExtraOwners`
    /// default (space/comma separated). Empty in normal use; a private,
    /// out-of-repo test rig points this at its own bundle id to exercise the
    /// cover without real overflow. Production detection (real chevron owned by
    /// MenuBarAgent) is unaffected.
    private static func additionalChevronOwners() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: "Thaw.debugChevronProbeExtraOwners") else {
            return []
        }
        let ids = raw.split { $0 == "," || $0 == " " }.map(String.init).filter { !$0.isEmpty }
        return Set(ids)
    }
}
