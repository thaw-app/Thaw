//
//  MenuBarItemAXProvider+Walk.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ThawAXCore

/// The pieces of the walk that decide how many apps are asked at once, in what order and how long
/// each read may take.
nonisolated extension MenuBarItemAXProvider {
    /// Apps asked at once. One after another, about 100 apps outlasted the walk's budget.
    static let walkConcurrency = 8

    /// The walk's per-read AX timeout, below the app-wide default that presses and moves keep.
    static let walkMessagingTimeout = AXPrimitives.defaultMessagingTimeout

    /// The walk's reads wait on other apps' answers, so they run here rather than holding Swift's shared threads.
    private static let readQueue = DispatchQueue(label: "com.stonerl.Thaw.menu-bar-walk", qos: .userInitiated, attributes: .concurrent)

    /// Runs one blocking read on the walk's own queue.
    static func onReadQueue<T: Sendable>(_ read: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            readQueue.async { continuation.resume(returning: read()) }
        }
    }

    /// How the walk lists apps, checks Accessibility and reads one app. Tests pass their own to run it without either.
    struct WalkReader: Sendable {
        var runningApps: @Sendable () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        }

        var isTrusted: @Sendable () -> Bool = { AXHelpers.isProcessTrusted() }
        /// How long one app may take, and the least the whole walk gets. Tests widen both, since
        /// they are wall-clock limits and a busy machine misses them for reasons the test isn't about.
        var perAppBudget = MenuBarItemAXProvider.perAppWalkBudget
        var minimumBudget = Duration.milliseconds(1500)
        var read: @Sendable (
            _ app: NSRunningApplication, _ appBundleID: String, _ ourBundleID: String?, _ formerHosts: Set<String>
        ) -> [RawItem] = { app, appBundleID, ourBundleID, formerHosts in
            MenuBarItemAXProvider.collectApp(
                runningApp: app,
                appBundleID: appBundleID,
                display: nil,
                displayBounds: nil,
                ourBundleID: ourBundleID,
                formerHosts: formerHosts
            ).raw
        }
    }

    /// One app's answer to the walk, or nil when it missed its deadline or the walk was cancelled.
    struct ProbeOutcome: Sendable {
        let ownerPID: pid_t
        let appBundleID: String
        let result: [RawItem]?
        let collected: Task<[RawItem], Never>
    }

    /// Apps with no UI at all, which can't show a menu bar item. The walk asks them last.
    static func backgroundOnlyPIDs(among runningApps: [NSRunningApplication]) -> Set<pid_t> {
        Set(runningApps.filter { $0.activationPolicy == .prohibited }.map(\.processIdentifier))
    }

    /// The extras bar's children, set to the walk's timeout. Elements read from an app take the
    /// app-wide default, which presses and moves keep.
    static func walkChildren(of bar: AXElement) -> [AXElement] {
        bar.setMessagingTimeout(walkMessagingTimeout)
        let children = AXHelpers.children(for: bar)
        for child in children {
            child.setMessagingTimeout(walkMessagingTimeout)
        }
        return children
    }
}
