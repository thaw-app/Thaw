//
//  MenuBarItemDirectPresser.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Cocoa
import MenuBarModel

/// Opens a menu-bar item's menu without posting into the global HID event
/// stream.
///
/// Tried before the synthetic path, which warps the cursor (visible jitter)
/// and lands on whatever is under it by then.
///
/// Returns nil when nothing opened, the signal to fall through. A nil is not a
/// diagnosis: an in-place redraw looks the same as an ignored press.
nonisolated enum MenuBarItemDirectPresser {
    private static let diagLog = DiagLog(category: "MenuBarItemDirectPresser")

    /// Presses item and reports what its owner was observed to do.
    ///
    /// @concurrent keeps the blocking hit-test and press off the main actor,
    /// where a hung app would hold the desktop's input.
    @concurrent
    static func press(item: MenuBarItem) async -> ClickReactionVerifier.Reaction? {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.info("press: not trusted for accessibility")
            return nil
        }

        guard let point = await pressPoint(for: item) else {
            return nil
        }
        // Logged at info because debug messages are not persisted. Can drop to
        // debug once the rungs below have established behavior.
        guard let element = element(at: point) else {
            diagLog.info(
                "press: no element at (\(Int(point.x)), \(Int(point.y))) for \(item.logString)"
            )
            return nil
        }
        // A revealed item's reported position can lag where MenuBarAgent draws it, and the element
        // there then belongs to a neighbour; pressing it would open the wrong app.
        var elementPID: pid_t = 0
        AXUIElementGetPid(element, &elementPID)
        guard isPressable(
            elementPID: elementPID,
            for: item.reactionPIDs,
            sameApp: isSameApp(elementPID: elementPID, as: item)
        ) else {
            diagLog.info("press: the element at (\(Int(point.x)), \(Int(point.y))) belongs to pid \(elementPID), not \(item.logString)")
            return nil
        }

        let target = MenuBarItemPressTarget(element: element, ownerPID: item.ownerPID)
        let snapshot = ClickReactionVerifier.snapshot(for: item)
        let outcome = await MenuBarItemPresserProvider.current.press(
            target,
            at: processTargetedFallbackPoint(for: item, at: point)
        )
        guard outcome.didOpen else {
            diagLog.info("press: \(item.logString) did not open: \(outcome.diagnosticDescription)")
            return nil
        }

        diagLog.info("press: \(item.logString) opened: \(outcome.diagnosticDescription)")
        return await ClickReactionVerifier.verify(against: snapshot)
    }

    /// Where to hit-test for item: where it is drawn, as the real click aims. Nil for a parked or
    /// off-bar frame, where an open window of the same app would pass the process check.
    private static func pressPoint(for item: MenuBarItem) async -> CGPoint? {
        let displays = BarAxis.liveDisplayBounds()
        if let rejection = ClickTargetCheck.rejection(
            for: item.bounds,
            barWidth: ClickTargetCheck.barWidth(for: item.bounds, displays: displays),
            displays: displays
        ) {
            diagLog.info("press: \(item.logString) frame \(item.bounds) is \(rejection.rawValue); not pressing")
            return nil
        }
        guard let aimed = await DrawnItemFrame.clickFrame(
            for: item.bounds,
            ownerPID: item.ownerPID,
            sourcePID: item.sourcePID,
            in: MenuBarItemAXProvider.drawnBarConcurrent(),
            displays: displays
        ) else {
            diagLog.info("press: \(item.logString) frame \(item.bounds) sits on another app's item and it is not drawn; not pressing")
            return nil
        }
        return aimed.center
    }

    /// Where the process-targeted record may be aimed, or nil to withhold
    /// that rung entirely.
    ///
    /// Only for MenuBarAgent's composited items (overflow chevron, Live
    /// Activities); elsewhere the synthetic click has understood semantics.
    /// Whether the agent honors such a record is still unmeasured.
    private static func processTargetedFallbackPoint(
        for item: MenuBarItem,
        at point: CGPoint
    ) -> CGPoint? {
        item.owningApplication?.bundleIdentifier == SharedConstants.menuBarHostingBundleID ? point : nil
    }

    /// Whether an element of elementPID may be pressed for an item whose reaction can come from
    /// reactionPIDs, or whose app elementPID runs: a relaunched menu-bar-only app keeps stale PIDs.
    static func isPressable(elementPID: pid_t, for reactionPIDs: Set<pid_t>, sameApp: Bool = false) -> Bool {
        guard elementPID > 0 else { return false }
        return sameApp || reactionPIDs.contains { $0 > 0 && $0 == elementPID }
    }

    /// Whether elementPID runs the app the item is named for. MenuBarAgent hosts other apps'
    /// items, so its elements never count as the item's own app.
    private static func isSameApp(elementPID: pid_t, as item: MenuBarItem) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: elementPID)?.bundleIdentifier,
              bundleID != SharedConstants.menuBarHostingBundleID
        else { return false }
        return bundleID == item.tag.namespace.description
    }

    /// The accessibility element at a screen point.
    ///
    /// Hit-tests because the tree walk cannot see elements such as the
    /// notchless overflow chevron.
    private static func element(at point: CGPoint) -> AXUIElement? {
        AXHelpers.nativeElement(at: point)
    }
}
