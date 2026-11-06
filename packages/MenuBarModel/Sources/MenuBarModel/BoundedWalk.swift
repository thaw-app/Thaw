//
//  BoundedWalk.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What a bounded walk does with one item.
public enum BoundedWalkStep<Output: Sendable> {
    /// Nothing to run for this item.
    case skip
    /// Start nothing more; jobs already running are still collected.
    case stop
    /// Run this job alongside the others.
    case run(@Sendable () async -> Output)
}

/// Asks several apps at once instead of one after another, so the walk's time is the slowest
/// answers rather than the sum of them.
public enum BoundedWalk {
    /// Runs start's jobs, at most limit at once, and hands each output to collect. Both run on the
    /// caller, and start runs only when a slot is free, so its deadline check sees the real start time.
    /// start owns cancellation too: return stop when the task is cancelled.
    public static func run<Item, Output: Sendable>(
        _ items: [Item],
        limit: Int,
        start: (Item) async -> BoundedWalkStep<Output>,
        collect: (Output) async -> Void
    ) async {
        let limit = max(limit, 1)
        await withTaskGroup(of: Output.self) { group in
            var running = 0
            for item in items {
                if running >= limit, let output = await group.next() {
                    running -= 1
                    await collect(output)
                }
                let step = await start(item)
                if case .stop = step { break }
                guard case let .run(job) = step else { continue }
                group.addTask { await job() }
                running += 1
            }
            for await output in group {
                await collect(output)
            }
        }
    }
}
