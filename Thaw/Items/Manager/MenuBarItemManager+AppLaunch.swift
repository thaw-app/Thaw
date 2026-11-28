//
//  MenuBarItemManager+AppLaunch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Combine
import Foundation

extension MenuBarItemManager {
    /// A launch refreshes the cache to find new items and puts a relaunched app's items back in their
    /// sections. A quit drops the app's items and refreshes. Both debounce to a second.
    func watchAppLaunchesAndExits() -> AnyCancellable {
        let (launches, launched) = AsyncStream<Void>.makeStream()
        let (exits, exited) = AsyncStream<Void>.makeStream()
        let watch = RunningApplicationsWatch { [weak self] change in
            for app in change.terminated {
                // At once, so a relaunch re-reads the icon and Layout drops the rows without waiting.
                OverflowFallbackIcon.forgetIcon(forPID: app.processIdentifier)
                self?.purgeItemsOwnedBy(app)
            }
            // Noted as they arrive: the refresh is debounced, and keeping only the last launch of a
            // burst lost a tracked relaunch that an unrelated app followed within the second.
            for app in change.launched {
                self?.noteAppLaunched(bundleID: app.bundleIdentifier, processIdentifier: app.processIdentifier)
            }
            if !change.launched.isEmpty { launched.yield() }
            if !change.terminated.isEmpty { exited.yield() }
        }
        let launchTask = Task { @MainActor [weak self] in
            for await _ in launches.debounce(for: .seconds(1)) {
                await self?.refreshForLaunchedApps()
            }
        }
        let exitTask = Task { @MainActor [weak self] in
            for await _ in exits.debounce(for: .seconds(1)) {
                Self.diagLog.debug("App terminated, refreshing cache")
                // Unconditional: an item published only as an AXExtrasMenuBar child owns no window,
                // so its app can quit without changing the menu bar window list.
                await self?.cacheItemsRegardless()
            }
        }
        return AnyCancellable {
            withExtendedLifetime(watch) {
                launched.finish()
                exited.finish()
                launchTask.cancel()
                exitTask.cancel()
            }
        }
    }

    /// Logs a launch and settles the bar when it is a relaunch of an app Thaw tracks an item for.
    func noteAppLaunched(bundleID: String?, processIdentifier: pid_t?) {
        Self.diagLog.debug("App launched\(bundleID.map { " (\($0))" } ?? "")")
        if let bundleID, let processIdentifier {
            ownerPurge.noteLaunched(bundleID, processIdentifier: processIdentifier)
        }
        if let settle = Self.launchSettle(bundleID: bundleID, knownIdentifiers: knownItemIdentifiers) {
            barSettling.note(settle)
        }
    }

    /// Handles tracked apps the liveness check found running again as launches with no notice:
    /// settles on each and rescans. Their hidden items come back from their conceal snapshots.
    func noteAppsRunningAgain(_ bundleIDs: Set<String>) {
        guard !bundleIDs.isEmpty else { return }
        for bundleID in bundleIDs.sorted() {
            Self.diagLog.debug("App running again without a launch notice (\(bundleID))")
            if let settle = Self.launchSettle(bundleID: bundleID, knownIdentifiers: knownItemIdentifiers) {
                barSettling.note(settle)
            }
        }
        Task { [weak self] in await self?.refreshForLaunchedApps() }
    }

    /// Rescans for the items of launched apps now, and again at +2.5 s and +5 s.
    func refreshForLaunchedApps() async {
        Self.diagLog.debug("Refreshing cache for potential new items after app launches")
        await cacheItemsRegardless()
        // Many apps register their status item more than a second after they start. The window-list
        // gate is dropped first: an item published only as an AXExtrasMenuBar child adds no window.
        for _ in 0 ..< 2 {
            try? await Task.sleep(for: .seconds(2.5))
            periodicWindowListSignature = nil
            await cacheItemsIfNeeded()
        }
    }

    /// The settle a launch starts. A tracked app's item is about to re-register, and the move pass waits on
    /// barSettling.settled() until it re-pairs, or a bulk apply on the moving bar sweeps hidden items into Visible.
    static nonisolated func launchSettle(bundleID: String?, knownIdentifiers: Set<String>) -> BarSettling.Disturbance? {
        guard let bundleID, tracksMenuBarItem(bundleID: bundleID, in: knownIdentifiers) else { return nil }
        return .appLaunched(bundleID: bundleID)
    }
}
