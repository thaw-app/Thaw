//
//  OverflowSpacerExperiment.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import Combine
import MenuBarModel

/// Debug instrument for the "chevron herding" question (plan 031): does the
/// native macOS 27 overflow control's position track item layout, and can a
/// deliberately wide spacer item therefore force overflow to happen — and the
/// chevron to appear — inside the region Thaw manages, instead of wherever the
/// notch dictates?
///
/// Enable by setting a width in points:
///
///     defaults write com.stonerl.Thaw.debug Thaw.debugOverflowSpacerWidth -float 300
///
/// The width is observed live — sweep it with repeated `defaults write` calls
/// and watch the `OverflowSpacerExperiment` log category: after each change the
/// experiment waits for the bar to settle, then probes the native overflow
/// control via the same AX read the section controller uses and logs where (or
/// whether) the chevron landed alongside the spacer's own frame. Set the width
/// to 0 (or delete the key) to remove the spacer.
///
/// This is also the only way to force *real* overflow on a display without a
/// notch, which `Thaw.debugSimulateNotch` cannot do — the simulation is
/// Thaw-side only and macOS never overflows for it.
@MainActor
final class OverflowSpacerExperiment {
    static let shared = OverflowSpacerExperiment()

    /// Set by `performSetup(with:)`; used by the probe to read the spacer's
    /// real placement from the item cache — on macOS 27 the app-side status
    /// item window is a stub (observed frame height 0), so `button?.window`
    /// says nothing about where the composited item actually sits.
    private weak var appState: AppState?

    /// The `Thaw.ControlItem.` prefix matters: items carrying it are
    /// recognized as Thaw's own control items and stay outside the assertion's
    /// concealment. Without it the first probe run showed the spacer created
    /// but never laid out (frame height 0) — Thaw's own hiding ate it.
    private static let spacerAutosaveName = "Thaw.ControlItem.OverflowSpacer"

    private let diagLog = DiagLog(category: "OverflowSpacerExperiment")
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var probeTask: Task<Void, Never>?

    /// Logs every AX element under the menu-bar-owning agents, three levels
    /// deep, so unfamiliar chrome (the notchless overflow chevron) can be
    /// identified by its role/identifier/frame. Debug instrument only.
    private func dumpMenuBarTrees(context: String) {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.notice("dump (\(context)): AX not trusted")
            return
        }
        for bundleID in ["com.apple.MenuBarAgent", "com.apple.systemuiserver"] {
            guard let runningApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first,
                let app = AXHelpers.application(for: runningApp)
            else {
                diagLog.notice("dump (\(context)): \(bundleID) not running/readable")
                continue
            }
            for (barName, bar) in [
                ("extras", AXHelpers.extrasMenuBar(for: app)),
                ("menuBar", AXHelpers.menuBar(for: app)),
            ] {
                guard let bar else { continue }
                dump(element: bar, label: "\(bundleID)/\(barName)", depth: 0, context: context)
            }
        }
    }

    private func dump(element: AXSwift6.UIElement, label: String, depth: Int, context: String) {
        guard depth <= 3 else { return }
        let role = AXHelpers.roleString(for: element) ?? "?"
        let identifier = AXHelpers.identifier(for: element) ?? ""
        let title = AXHelpers.title(for: element) ?? ""
        let description = AXHelpers.description(for: element) ?? ""
        let frame = AXHelpers.frame(for: element)
        let frameString = frame.map {
            "(\(Int($0.origin.x)),\(Int($0.origin.y)),\(Int($0.width)),\(Int($0.height)))"
        } ?? "?"
        let indent = String(repeating: "  ", count: depth)
        diagLog.notice(
            "dump (\(context)): \(indent)\(label) role=\(role) id='\(identifier)' title='\(title)' desc='\(description)' frame=\(frameString)"
        )
        for child in AXHelpers.childrenIfAvailable(for: element) ?? [] {
            dump(element: child, label: "·", depth: depth + 1, context: context)
        }
    }

    /// Hit-tests across the menu bar strip of the main screen and logs each
    /// distinct element with its owning process — the only reliable way to
    /// enumerate what is *actually drawn* on the strip, since every app
    /// AX-exposes its own status items.
    private func scanStrip(context: String) {
        guard let screen = NSScreen.screens.first else { return }
        // AX hit-testing uses top-left-origin global coordinates.
        let y = CGFloat(12)
        let menuBarWidth = screen.frame.width
        var lastFrame = CGRect.null
        var logged = 0

        for x in stride(from: CGFloat(0), to: menuBarWidth, by: 15) {
            guard logged < 80 else {
                diagLog.notice("scan (\(context)): output cap reached")
                break
            }
            guard let element = AXHelpers.element(at: CGPoint(x: x, y: y)) else { continue }
            let frame = AXHelpers.frame(for: element) ?? .null
            if frame == lastFrame, frame != .null { continue }
            lastFrame = frame

            let owner = AXHelpers.pid(for: element)
                .flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName ?? "pid \($0)" } ?? "?"
            let role = AXHelpers.roleString(for: element) ?? "?"
            let identifier = AXHelpers.identifier(for: element) ?? ""
            let title = AXHelpers.title(for: element) ?? ""
            let description = AXHelpers.description(for: element) ?? ""
            let frameString = frame == .null
                ? "?"
                : "(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height)))"
            diagLog.notice(
                "scan (\(context)): x=\(Int(x)) owner='\(owner)' role=\(role) id='\(identifier)' title='\(title)' desc='\(description)' frame=\(frameString)"
            )
            logged += 1
        }
    }

    /// A dim, hard-to-miss slab at the requested width. Deliberately visible:
    /// the point of the experiment is knowing where the spacer is and how wide
    /// it renders; an invisible spacer cannot be distinguished from a missing
    /// one. Production would draw clear.
    private static func spacerImage(width: CGFloat) -> NSImage {
        let size = NSSize(width: width, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemGray.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private var configuredWidth: CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: Defaults.Key.debugOverflowSpacerWidth.rawValue))
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        apply()
        // Poll rather than observe: UserDefaults.didChangeNotification does
        // not fire reliably for external `defaults write` calls (observed
        // 2026-07-26 — a live width change from the CLI was never applied),
        // and KVO cannot observe a key containing dots. A 1 s poll on a debug
        // instrument costs nothing; `apply()` early-returns when unchanged.
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.apply()
            }
    }

    private func apply() {
        let width = configuredWidth

        guard width > 0 else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
                diagLog.notice("spacer removed")
                scheduleProbe(context: "after removal")
            }
            return
        }

        let spacerImage = Self.spacerImage(width: width)

        if statusItem == nil {
            // Park the spacer immediately left of the Thaw icon — between it
            // and the hidden-section items — so growing it pushes those items
            // further left. Preferred position is distance from the right
            // screen edge (larger = further left), so one step past the Thaw
            // icon's own position lands in exactly that slot. Written before
            // creation so AppKit applies it on the first layout instead of
            // after a visible hop.
            let thawIconPosition: CGFloat =
                ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] ?? 0
            ControlItemDefaults[.preferredPosition, Self.spacerAutosaveName] = thawIconPosition + 1
            // macOS 27 also consults a per-item "VisibleCC" switch — the same
            // CC-preference channel Thaw's module manager hides items with.
            // Earlier anonymous incarnations of this spacer were flagged 0
            // there, which kept every later one off the bar regardless of
            // content. Assert both visibility keys before creation.
            UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(Self.spacerAutosaveName)")
            UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC \(Self.spacerAutosaveName)")
            let item = NSStatusBar.system.statusItem(withLength: width)
            item.autosaveName = Self.spacerAutosaveName
            // A contentless button gets composited as nothing on macOS 27 —
            // the first probe runs showed the item in Thaw's cache but absent
            // from the strip. Give it a real (deliberately visible — this is
            // an instrument) image sized to the requested width.
            item.button?.image = spacerImage
            item.button?.imageScaling = .scaleNone
            item.button?.toolTip = "Thaw overflow spacer (debug experiment)"
            item.button?.window?.title = Self.spacerAutosaveName
            statusItem = item
            diagLog.notice(
                "spacer created, width=\(Int(width))pt, parked left of Thaw icon (position \(Int(thawIconPosition + 1)))"
            )
        } else if statusItem?.length != width {
            statusItem?.length = width
            statusItem?.button?.image = spacerImage
            diagLog.notice("spacer resized, width=\(Int(width))pt")
        } else {
            return
        }

        scheduleProbe(context: "width=\(Int(width))pt")
    }

    /// Waits for the bar to settle, then logs the spacer's own frame and the
    /// native overflow control's observation for every screen with a menu bar.
    private func scheduleProbe(context: String) {
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }

            if let cached = self.appState?.itemManager.itemCache.managedItems
                .first(where: { $0.tag.title.contains("OverflowSpacer") }) {
                let bounds = cached.bounds
                self.diagLog.notice(
                    "probe (\(context)): spacer in item cache — bounds=(\(Int(bounds.origin.x)), \(Int(bounds.origin.y)), \(Int(bounds.width)), \(Int(bounds.height))) onScreen=\(cached.isOnScreen)"
                )
            } else if self.statusItem != nil {
                self.diagLog.notice("probe (\(context)): spacer exists but is NOT in the item cache yet")
            } else {
                self.diagLog.notice("probe (\(context)): no spacer")
            }

            guard #available(macOS 27, *) else {
                self.diagLog.notice("probe (\(context)): native overflow probing requires macOS 27")
                return
            }

            // Raw AX dump: `nativeOverflowObservation` reported `absent` while
            // the maintainer was literally clicking the notchless chevron
            // (2026-07-26), so the notchless variant is not where that read
            // looks. Dump everything so the chevron identifies itself.
            self.dumpMenuBarTrees(context: context)

            // The tree dump only sees MenuBarAgent/SystemUIServer, but status
            // items are AX-exposed by their owning apps — the overflow arrows
            // that replaced real items (CodexBar, ProtonDrive) never appear in
            // those trees. Hit-test across the strip instead: every element
            // names itself and its owner regardless of who draws it.
            self.scanStrip(context: context)

            for screen in NSScreen.screens {
                let observation = MenuBarItemAXProvider.nativeOverflowObservation(on: screen.displayID)
                switch observation {
                case .unavailable:
                    self.diagLog.notice("probe (\(context)): display \(screen.displayID) overflow=unavailable")
                case .absent:
                    self.diagLog.notice("probe (\(context)): display \(screen.displayID) overflow=absent")
                case .present(let bounds):
                    let described = bounds
                        .map { "(\(Int($0.origin.x)), \(Int($0.origin.y)), \(Int($0.width)), \(Int($0.height)))" }
                        .joined(separator: ", ")
                    self.diagLog.notice("probe (\(context)): display \(screen.displayID) overflow=present at \(described)")
                }
            }
        }
    }
}
