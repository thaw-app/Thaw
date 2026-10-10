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

        // Logged at info because debug messages are not persisted. Can drop to
        // debug once the rungs below have established behavior.
        let point = item.bounds.center
        guard let element = element(at: point) else {
            diagLog.info(
                "press: no element at (\(Int(point.x)), \(Int(point.y))) for \(item.logString)"
            )
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

    /// The accessibility element at a screen point.
    ///
    /// Hit-tests because the tree walk cannot see elements such as the
    /// notchless overflow chevron. Raw, since AXSwift6 seals its element.
    private static func element(at point: CGPoint) -> AXUIElement? {
        AXHelpers.nativeElement(at: point)
    }
}
