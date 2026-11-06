//
//  AXWalkSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Dispatch
import Synchronization

/// How the helper's walk orders and spreads its per-app reads, matching the app's own walk.
/// Kept here because ThawAX has no dependencies, so it can't use MenuBarModel's BoundedWalk.
public enum AXWalkSchedule {
    /// Apps read at once. One after another, about 100 apps took the helper two seconds.
    public static let concurrency = 8

    /// items with the deferred ones, such as background-only apps that can't show items, moved last.
    public static func ordered<T>(_ items: [T], isDeferred: (T) -> Bool) -> [T] {
        items.filter { !isDeferred($0) } + items.filter(isDeferred)
    }

    /// Runs read for each index with at most limit running at once, on a queue of its own since
    /// each read blocks on another app, and returns the results in index order. Blocks the caller,
    /// which in the helper is the request's own thread.
    public static func map<T: Sendable>(_ count: Int, limit: Int, _ read: @escaping @Sendable (Int) -> T) -> [T] {
        guard count > 0 else { return [] }
        let queue = DispatchQueue(label: "com.stonerl.Thaw.ax-helper-walk", qos: .userInitiated, attributes: .concurrent)
        let slots = DispatchSemaphore(value: max(limit, 1))
        let group = DispatchGroup()
        let results = Mutex([T?](repeating: nil, count: count))
        for index in 0 ..< count {
            slots.wait()
            queue.async(group: group) {
                defer { slots.signal() }
                let result = read(index)
                results.withLock { $0[index] = result }
            }
        }
        group.wait()
        let ordered = results.withLock { $0.compactMap(\.self) }
        precondition(ordered.count == count, "every read stores its result")
        return ordered
    }
}
