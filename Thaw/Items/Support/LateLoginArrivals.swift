//
//  LateLoginArrivals.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// A few cheap looks, after every launch, for icons that login items add a minute or more after Thaw starts.
/// Such an icon has no window of its own, so the periodic window-list check never sees it arrive.
@MainActor
enum LateLoginArrivals {
    private static let diagLog = DiagLog(category: "LateLoginArrivals")

    /// When to look, measured from launch.
    static nonisolated let offsets: [Duration] = [.seconds(20), .seconds(40), .seconds(60), .seconds(90)]

    /// The waits between looks for the offsets still ahead, given how long ago Thaw launched.
    static nonisolated func waits(sinceLaunch elapsed: Duration, offsets: [Duration] = offsets) -> [Duration] {
        let ahead = offsets.filter { $0 > elapsed }
        return zip([elapsed] + ahead, ahead).map { $1 - $0 }
    }

    /// Whether the bar's items differ from the cached ones. Order is ignored: a reorder is not an arrival.
    static nonisolated func itemSetChanged(cached: [String], current: [String]) -> Bool {
        Set(cached) != Set(current)
    }

    /// Looks once after each wait and settles whenever the item set changed. Returns how many looks settled.
    /// `read` returns the cached and current item signatures, or nil when there is nothing to compare.
    @discardableResult
    static func run(
        waits: [Duration],
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        read: () async -> (cached: [String], current: [String])?,
        settle: () async -> Void
    ) async -> Int {
        var settled = 0
        for (index, wait) in waits.enumerated() {
            do { try await sleep(wait) } catch { return settled }
            guard let (cached, current) = await read(), itemSetChanged(cached: cached, current: current) else { continue }
            diagLog.info("Look \(index + 1) of \(waits.count): the item set changed (\(cached.count) cached, \(current.count) now); settling")
            await settle()
            settled += 1
        }
        return settled
    }

    /// Starts the looks for this launch. The task holds the manager weakly and ends with it.
    @discardableResult
    static func schedule(for manager: MenuBarItemManager, launchedAt: Date? = NSRunningApplication.current.launchDate) -> Task<Void, Never> {
        let elapsed = Duration.seconds(launchedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
        let waits = waits(sinceLaunch: elapsed)
        return Task { @MainActor [weak manager] in
            await run(
                waits: waits,
                read: {
                    guard manager != nil else { return nil }
                    let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                    guard let manager, let current = MenuBarBackendProvider.current.itemCacheSignature(items) else { return nil }
                    return (manager.cacheCycleState.cachedItemSignature, current)
                },
                settle: { await manager?.cacheItemsRegardless() }
            )
        }
    }
}
