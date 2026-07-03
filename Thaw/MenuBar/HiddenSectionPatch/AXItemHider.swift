//
//  AXItemHider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import AXSwift
import Cocoa

/// Hides menu-bar items by setting `AXHidden` on their AX elements.
///
/// On macOS 27, menu bar items live in `MenuBarAgent`'s AX tree rather than
/// each source app's `AXExtrasMenuBar`, and `AXHidden` is not settable on those
/// hosted menu-bar items. This hider is therefore gated out on macOS 27 and
/// retained for older or future OS paths where AX hiding works.
///
/// This is a *complement* to ``CGSWindowHider``. The CGS hider runs first
/// (handles pre-27 macOS where per-item windows exist); this hider runs second
/// and catches PIDs the CGS hider could not handle.
@MainActor
final class AXItemHider {
    private let diagLog = DiagLog(category: "AXItemHider")

    private var hiddenElements: [CGWindowID: UIElement] = [:]
    private var terminationObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreAll() }
        }
    }

    isolated deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    /// Hides the menu-bar items belonging to `hiddenPIDs` by setting `AXHidden`
    /// on each item's AX element. Restores any previously hidden items whose
    /// PID is no longer in the set.
    ///
    /// - Parameters:
    ///   - hiddenPIDs: PIDs whose menu-bar items should be hidden.
    ///   - allItems: The full item list, used to resolve AX elements by frame
    ///     matching. Items are matched by PID + bounds overlap.
    /// - Returns: The subset of `hiddenPIDs` for which at least one item was
    ///   resolved and hidden. Callers should only strip these PIDs from the
    ///   assertion input.
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>, allItems: [MenuBarItem]) -> Set<pid_t> {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.warning("apply: accessibility permission missing; cannot hide")
            return []
        }

        let desiredHidden = resolveAXElements(for: hiddenPIDs, allItems: allItems)
        var handledPIDs = Set<pid_t>()

        // Restore items that should no longer be hidden.
        for (windowID, element) in hiddenElements where !desiredHidden.keys.contains(windowID) {
            do {
                try element.setAttribute(.hidden, value: false)
                diagLog.debug("restored AXHidden on windowID \(windowID)")
            } catch {
                diagLog.error("failed to restore AXHidden on windowID \(windowID): \(error)")
            }
            hiddenElements.removeValue(forKey: windowID)
        }

        // Hide desired items.
        for (windowID, (element, pid)) in desiredHidden {
            if hiddenElements[windowID] === element {
                continue // Already hidden.
            }
            do {
                try element.setAttribute(.hidden, value: true)
                hiddenElements[windowID] = element
                handledPIDs.insert(pid)
                diagLog.debug("set AXHidden on windowID \(windowID) (pid \(pid))")
            } catch {
                diagLog.error("failed to set AXHidden on windowID \(windowID): \(error)")
            }
        }

        if !handledPIDs.isEmpty {
            diagLog.info("apply: hiding \(hiddenElements.count) item(s) via AX, handled \(handledPIDs.count) PID(s)")
        }
        return handledPIDs
    }

    /// Restores every item this hider has hidden.
    func restoreAll() {
        guard !hiddenElements.isEmpty else { return }
        for (windowID, element) in hiddenElements {
            do {
                try element.setAttribute(.hidden, value: false)
            } catch {
                diagLog.error("restoreAll: failed on windowID \(windowID): \(error)")
            }
        }
        diagLog.info("restoreAll: restored \(hiddenElements.count) item(s)")
        hiddenElements.removeAll()
    }

    // MARK: Private

    /// Walks the AX tree for each target PID and returns a mapping from
    /// synthetic windowID to (AX element, pid) for every matching item.
    private func resolveAXElements(
        for pids: Set<pid_t>,
        allItems: [MenuBarItem]
    ) -> [CGWindowID: (UIElement, pid_t)] {
        var result: [CGWindowID: (UIElement, pid_t)] = [:]

        // Group items by PID for efficient AX lookups.
        let itemsByPID: [pid_t: [MenuBarItem]] = Dictionary(
            grouping: allItems.filter { pids.contains($0.ownerPID) },
            by: { $0.ownerPID }
        )

        for (pid, items) in itemsByPID {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let axApp = AXHelpers.application(for: app),
                  let bar = AXHelpers.extrasMenuBar(for: axApp)
            else {
                diagLog.debug("resolveAXElements: pid \(pid) → no AXExtrasMenuBar")
                continue
            }

            let children = AXHelpers.children(for: bar)
            for item in items {
                guard let matchedChild = findMatchingChild(in: children, for: item) else {
                    diagLog.debug("resolveAXElements: pid \(pid) → no AX child matching \(item.identityDescription)")
                    continue
                }
                result[item.windowID] = (matchedChild, pid)
            }
        }

        return result
    }

    /// Finds the AX child whose frame overlaps the stored item bounds.
    /// On first match, diagnostics logs the AX element's supported attributes,
    /// actions, and whether `AXAlternateUIVisible` or `AXPosition` are settable,
    /// so we can identify which attribute is effective on macOS 27.
    private func findMatchingChild(
        in children: [UIElement],
        for item: MenuBarItem
    ) -> UIElement? {
        for child in children {
            guard let frame = AXHelpers.frame(for: child) else { continue }
            // Match by PID-bounded frame intersection with small tolerance.
            if item.bounds.intersects(frame.insetBy(dx: -4, dy: -4)) {
                probeAXElement(child, for: item)
                return child
            }
        }
        return nil
    }

    /// One-shot diagnostic: logs supported attributes/actions on a menu bar
    /// item AX element to help identify the correct hide mechanism.
    private static var didProbe = false
    private func probeAXElement(_ element: UIElement, for item: MenuBarItem) {
        guard !Self.didProbe else { return }
        Self.didProbe = true
        do {
            let attrs = try element.attributesAsStrings()
            diagLog.info("probe: \(item.identityDescription) → attributes: \(attrs.joined(separator: ", "))")
            let actions = try element.actionsAsStrings()
            diagLog.info("probe: \(item.identityDescription) → actions: \(actions.joined(separator: ", "))")
            for attr in ["AXAlternateUIVisible", "AXPosition", "AXHidden"] {
                let settable = (try? element.attributeIsSettable(attr)) ?? false
                diagLog.info("probe: \(attr) settable=\(settable)")
            }
        } catch {
            diagLog.error("probe failed: \(error)")
        }
    }
}

private extension MenuBarItem {
    var identityDescription: String {
        tag.tagIdentifier
    }
}
