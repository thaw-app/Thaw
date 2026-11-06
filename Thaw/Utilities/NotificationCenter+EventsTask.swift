//
//  NotificationCenter+EventsTask.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Foundation

extension NotificationCenter {
    /// Runs `body` on the main actor for each posting of `name`, one at a time, until the task is cancelled.
    ///
    /// With a `debounce`, a burst of postings runs `body` once, after the burst has been quiet for that long.
    /// The observer belongs to the task: it is added when the task starts and removed when the task ends, so
    /// the caller keeps nothing but the task. A posting that arrives while `body` runs is kept, not dropped.
    @MainActor
    func eventsTask(
        named name: Notification.Name,
        debounce: Duration? = nil,
        perform body: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        return Task { @MainActor [self] in
            let observer = addObserver(forName: name, object: nil, queue: .main) { _ in continuation.yield(()) }
            defer { removeObserver(observer) }
            if let debounce {
                for await _ in events.debounce(for: debounce) {
                    await body()
                }
            } else {
                for await _ in events {
                    await body()
                }
            }
        }
    }
}
