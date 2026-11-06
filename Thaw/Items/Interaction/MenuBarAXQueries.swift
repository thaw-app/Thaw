//
//  MenuBarAXQueries.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import MenuBarModel
import ThawAXClient
import ThawAXCore

/// Pointer-path AX reads and presses, kept off the main thread: the input taps
/// run there, so an AX round trip would stall every click until the app answered.
/// They run in the AX helper when enabled, otherwise on the concurrent pool.
/// The helper gives them their own lanes, so they never queue behind a walk.
nonisolated enum MenuBarAXQueries {
    /// A pointer read that takes longer than this is no use to the pointer.
    private static let timeoutSeconds = 1.0

    private static let diagLog = DiagLog(category: "MenuBarAXQueries")

    /// Sends request to the helper, or returns nil so the caller reads
    /// in-process: helper off, unusable, or never granted Accessibility.
    ///
    /// Hit-tests are latest-wins in the helper, so a superseded one is retried
    /// once.
    private static func viaHelper(_ request: AXHelperRequest) async -> AXHelperReply? {
        guard let client = MenuBarAXSubprocess.client else { return nil }
        for attempt in 1 ... 2 {
            do {
                let reply = try await client.send(request, timeoutSeconds: timeoutSeconds)
                guard reply.accessibilityTrusted else { return nil }
                return reply
            } catch AXSubprocessError.superseded where attempt == 1 {
                continue
            } catch is CancellationError {
                return nil
            } catch {
                diagLog.error("helper request failed, reading in-process: \(error)\(client.lastExitDescription.map { " (\($0))" } ?? "")")
                return nil
            }
        }
        return nil
    }

    // MARK: Application menu

    /// Frames of the app's menu bar titles, or nil when they could not be read.
    @concurrent
    static func applicationMenuFrames(pid: pid_t) async -> [CGRect]? {
        if case let .applicationMenuFrames(frames, _) = await viaHelper(.applicationMenuFrames(pid: pid)) {
            return frames
        }
        return AXPrimitives.applicationMenuFrames(pid: pid)
    }

    // MARK: Foreign widget hit-test

    /// Whether the element under point belongs to a third-party widget that
    /// should get the click instead of Thaw, as opposed to empty menu bar
    /// space, Thaw itself, or the front app's own menu bar.
    @concurrent
    static func isForeignWidget(at point: CGPoint) async -> Bool {
        let hit: AXHitTestResult? = if case let .hitTest(result, _) = await viaHelper(.hitTest(x: point.x, y: point.y)) {
            result
        } else if let element = AXHelpers.element(at: point),
                  let pid = AXHelpers.pid(for: element)
        {
            AXHitTestResult(pid: pid, role: AXHelpers.roleString(for: element))
        } else {
            nil
        }
        guard let hit, hit.pid > 0, hit.pid != getpid() else {
            return false
        }
        // SystemUIServer, and on macOS 27 MenuBarAgent, render the menu bar
        // background, so a hit on them is empty menu bar space. WindowServer
        // renders menu bar surfaces too but has no bundle identifier.
        switch NSRunningApplication(processIdentifier: hit.pid)?.bundleIdentifier {
        case "com.apple.systemuiserver", SharedConstants.menuBarHostingBundleID:
            return false
        default:
            break
        }
        if isWindowServer(hit.pid) {
            return false
        }
        // Between File/Edit/View the front app's menu bar answers with its own
        // PID but a menu-bar-class role; that is the app's menu, not a widget.
        switch hit.role {
        case "AXMenuBar", "AXMenu", "AXMenuItem", "AXMenuBarItem":
            return false
        default:
            return true
        }
    }

    private static func isWindowServer(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return -1 }
            return proc_name(pid, base, UInt32(pointer.count))
        }
        guard length > 0 else { return false }
        let name = buffer.prefix { $0 != 0 }.map(UInt8.init)
        return String(bytes: name, encoding: .utf8) == "WindowServer"
    }

    // MARK: Presses

    /// How far a status item's frame centre may lie from the target point and still be the one pressed.
    private static let statusItemMatchTolerance = 10.0

    /// Presses one of pid's own status items. With several, only the one
    /// whose frame centre lies within statusItemMatchTolerance of target is pressed.
    @concurrent
    static func pressStatusItem(pid: pid_t, target: CGPoint) async -> Bool {
        await pressNearestStatusItem(pid: pid, target: target, action: kAXPressAction) {
            .pressStatusItem(pid: pid, targetX: target.x, targetY: target.y, tolerance: $0)
        }
    }

    /// Opens the menu a right click would open on one of pid's status items,
    /// matched to target the same way pressStatusItem matches.
    @concurrent
    static func showStatusItemMenu(pid: pid_t, target: CGPoint) async -> Bool {
        await pressNearestStatusItem(pid: pid, target: target, action: kAXShowMenuAction) {
            .showStatusItemMenu(pid: pid, targetX: target.x, targetY: target.y, tolerance: $0)
        }
    }

    /// Through the AX helper when it answers, else in process.
    @concurrent
    private static func pressNearestStatusItem(
        pid: pid_t,
        target: CGPoint,
        action: String,
        request: (Double) -> AXHelperRequest
    ) async -> Bool {
        if case let .press(pressed, _) = await viaHelper(request(statusItemMatchTolerance)) {
            return pressed
        }
        return AXPrimitives.pressNearestStatusItem(pid: pid, target: target, tolerance: statusItemMatchTolerance, action: action)
    }

    /// Presses a status item MenuBarAgent hosts on behalf of sourcePID.
    @concurrent
    static func pressHostedItem(sourcePID: pid_t) async -> Bool {
        if case let .press(pressed, _) = await viaHelper(.pressHostedItem(sourcePID: sourcePID)) {
            return pressed
        }
        return MenuBarItemAXProvider.pressHostedItem(sourcePID: sourcePID)
    }

    // MARK: Revealed items

    /// Waits until MenuBarAgent draws one of pid's items and pid has a status item a press can
    /// reach, its own or one MenuBarAgent hosts for it, and returns whether both held before
    /// timeout. A shown item can take a moment to be drawn and to reach Accessibility, and under
    /// an auto-hidden bar that is out of sight it does not reach it at all.
    @concurrent
    static func waitForDrawnStatusItem(pid: pid_t, timeout: Duration) async -> Bool {
        guard pid > 0 else { return false }
        let start = ContinuousClock.now
        while !isDrawn(pid: pid) || !hasPressableStatusItem(pid: pid) {
            guard !Task.isCancelled, start.duration(to: .now) < timeout else {
                diagLog.debug("pid \(pid) had no drawn, pressable status item within \(timeout)")
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        diagLog.debug("pid \(pid) has a drawn, pressable status item after \(start.duration(to: .now))")
        return true
    }

    private static func isDrawn(pid: pid_t) -> Bool {
        AXPrimitives.menuBarAgentDrawnOwners()?.contains(pid) == true
    }

    private static func hasPressableStatusItem(pid: pid_t) -> Bool {
        if let bar = AXPrimitives.extrasMenuBar(pid: pid), !AXPrimitives.children(of: bar).isEmpty {
            return true
        }
        guard let host = AXPrimitives.menuBarAgentExtrasBar() else { return false }
        return AXPrimitives.children(of: host).contains { AXPrimitives.pid(of: $0) == pid }
    }
}
