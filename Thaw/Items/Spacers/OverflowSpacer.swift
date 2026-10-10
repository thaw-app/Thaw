//
//  OverflowSpacer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import Combine
import MenuBarModel

/// Debug instrument: can a wide spacer force the macOS 27 overflow chevron to
/// appear inside the region Thaw manages instead of where the notch dictates?
///
/// Enable with a width in points (0 or no key removes it), observed live:
/// defaults write com.stonerl.Thaw.debug Thaw.debugOverflowSpacerWidth -float 300
/// Each change logs, under OverflowSpacer, where the chevron landed.
///
/// Also the only way to force real overflow without a notch:
/// Thaw.debugSimulateNotch is Thaw-side only.
@MainActor
final class OverflowSpacer {
    static let shared = OverflowSpacer()

    /// Lets the probe read placement from the item cache: on macOS 27 the
    /// app-side status item window is a zero-height stub.
    private weak var appState: AppState?

    /// The Thaw.ControlItem. prefix keeps the spacer outside the assertion's
    /// concealment; without it Thaw's own hiding ate it.
    private static let spacerAutosaveName = "Thaw.ControlItem.OverflowSpacer"

    private let diagLog = DiagLog(category: "OverflowSpacer")
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var probeTask: Task<Void, Never>?

    /// Logs every AX element under the menu-bar-owning agents, three levels
    /// deep, so unfamiliar chrome can identify itself.
    private func dumpMenuBarTrees(context: String) {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.notice("dump (\(context)): AX not trusted")
            return
        }
        for bundleID in [SharedConstants.menuBarHostingBundleID, "com.apple.systemuiserver"] {
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
        let attributes = AXHelpers.descendantAttributes(for: element, includingChildren: depth < 3)
        let role = attributes.role ?? "?"
        let identifier = attributes.identifier ?? ""
        let title = attributes.title ?? ""
        let description = attributes.accessibilityDescription ?? ""
        let frame = attributes.frame
        let frameString = frame.map {
            "(\(Int($0.origin.x)),\(Int($0.origin.y)),\(Int($0.width)),\(Int($0.height)))"
        } ?? "?"
        let indent = String(repeating: "  ", count: depth)
        diagLog.notice(
            "dump (\(context)): \(indent)\(label) role=\(role) id='\(identifier)' title='\(title)' desc='\(description)' frame=\(frameString)"
        )
        for child in attributes.children {
            dump(element: child, label: "·", depth: depth + 1, context: context)
        }
    }

    /// Hit-tests across the main screen's menu bar strip and logs each distinct
    /// element with its owner: the only reliable view of what is drawn there.
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
            if frame == lastFrame, frame != .null {
                continue
            }
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

    /// A dim slab at the requested width, visible on purpose: an invisible
    /// spacer cannot be told from a missing one.
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
        // Polled: didChangeNotification misses external defaults writes, and
        // KVO cannot observe a key containing dots.
        cancellable = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common)
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
            // Park it just left of the Thaw icon (larger position = further
            // left). Written before creation so there is no visible hop.
            let thawIconPosition: CGFloat =
                ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] ?? 0
            ControlItemDefaults[.preferredPosition, Self.spacerAutosaveName] = thawIconPosition + 1
            // macOS 27 also reads a per-item "VisibleCC" switch; a stale 0
            // there keeps the item off the bar, so assert both keys.
            UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(Self.spacerAutosaveName)")
            UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC \(Self.spacerAutosaveName)")
            let item = NSStatusBar.system.statusItem(withLength: width)
            item.autosaveName = Self.spacerAutosaveName
            // A contentless button composites as nothing on macOS 27.
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

            if let cached = self.appState?.itemManager.managedItems
                .first(where: { $0.tag.title.contains("OverflowSpacer") })
            {
                let bounds = cached.bounds
                self.diagLog.notice(
                    "probe (\(context)): spacer in item cache, bounds=(\(Int(bounds.origin.x)), \(Int(bounds.origin.y)), \(Int(bounds.width)), \(Int(bounds.height))) onScreen=\(cached.isOnScreen)"
                )
            } else if self.statusItem != nil {
                self.diagLog.notice("probe (\(context)): spacer exists but is NOT in the item cache yet")
            } else {
                self.diagLog.notice("probe (\(context)): no spacer")
            }

            // nativeOverflowObservation can miss the notchless chevron, so dump
            // everything and let it identify itself.
            self.dumpMenuBarTrees(context: context)

            // The tree dump misses items exposed by their own apps, including
            // overflow arrows; the strip hit-test names every element and owner.
            self.scanStrip(context: context)

            for screen in NSScreen.screens {
                let observation = MenuBarItemAXProvider.nativeOverflowObservation(on: screen.displayID)
                switch observation {
                case .unavailable:
                    self.diagLog.notice("probe (\(context)): display \(screen.displayID) overflow=unavailable")
                case .absent:
                    self.diagLog.notice("probe (\(context)): display \(screen.displayID) overflow=absent")
                case let .present(bounds):
                    let described = bounds
                        .map { "(\(Int($0.origin.x)), \(Int($0.origin.y)), \(Int($0.width)), \(Int($0.height)))" }
                        .joined(separator: ", ")
                    self.diagLog.notice("probe (\(context)): display \(screen.displayID) overflow=present at \(described)")
                }
            }
        }
    }
}
