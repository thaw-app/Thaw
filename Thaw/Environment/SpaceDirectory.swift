//
//  SpaceDirectory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Observation

/// The Spaces the window server knows about, re-read when one is created or deleted.
@MainActor
@Observable
final class SpaceDirectory {
    private(set) var spaces: [Bridging.ManagedSpace]

    @ObservationIgnored private let read: () -> [Bridging.ManagedSpace]
    @ObservationIgnored private var listTask: Task<Void, Never>?

    /// Waits this long after a Space list change before reading, so the window server has published it.
    static let settleDelay: Duration = .milliseconds(500)

    init(read: @escaping () -> [Bridging.ManagedSpace] = { SpaceLabels.liveSpaces() }) {
        self.read = read
        spaces = read()
    }

    /// Re-reads the list on each Space list change from changes, until stop is called.
    func start(changes: SpaceChanges, debounce: Duration = settleDelay) {
        listTask?.cancel()
        listTask = changes.spaceListTask(debounce: debounce) { [weak self] in
            self?.refresh()
        }
    }

    func stop() {
        listTask?.cancel()
        listTask = nil
    }

    func refresh() {
        let latest = read()
        if latest != spaces {
            spaces = latest
        }
    }

    /// The Space with key, or nil when it no longer exists. Settings that name a missing Space are kept.
    func space(forKey key: String) -> Bridging.ManagedSpace? {
        spaces.first { $0.persistentKey == key }
    }
}
