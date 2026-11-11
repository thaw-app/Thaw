//
//  SpaceChanges.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import AsyncAlgorithms
import MenuBarModel

/// Space switches and Space list changes, each delivered once, as early as the window server reports them.
/// Code that wants a settled bar keeps using the NSWorkspace notification.
@MainActor
final class SpaceChanges {
    private var coalescer = SpaceChangeCoalescer()
    private var subscribers: [UUID: AsyncStream<SpaceChange>.Continuation] = [:]
    private var pump: Task<Void, Never>?
    private let activeSpaceID: () -> CGSSpaceID
    private let now: () -> ContinuousClock.Instant

    init(
        activeSpaceID: @escaping () -> CGSSpaceID = { Bridging.getActiveSpaceID() },
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.activeSpaceID = activeSpaceID
        self.now = now
    }

    /// Reads signals from feed until stop is called or the feed ends. Replaces an earlier feed.
    func start(feed: AsyncStream<SpaceSignal>) {
        pump?.cancel()
        pump = Task { [weak self] in
            for await signal in feed {
                self?.admit(signal)
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
    }

    /// Delivers signal to every subscriber unless it repeats a change already delivered.
    func admit(_ signal: SpaceSignal) {
        guard let change = coalescer.admit(signal, activeSpaceID: activeSpaceID(), at: now()) else { return }
        for continuation in subscribers.values {
            continuation.yield(change)
        }
    }

    /// Every change admitted from now on, until the stream's consumer goes away.
    func changes() -> AsyncStream<SpaceChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SpaceChange>.makeStream()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        subscribers[id] = continuation
        return stream
    }

    /// Runs body for each active Space change, one at a time, until the task is cancelled.
    /// With a debounce, a burst of switches runs body once, for the last Space.
    func activeSpaceTask(
        debounce: Duration? = nil,
        perform body: @escaping @MainActor (CGSSpaceID) async -> Void
    ) -> Task<Void, Never> {
        let switches = changes().compactMap { change -> CGSSpaceID? in
            if case let .activeSpace(spaceID) = change {
                spaceID
            } else {
                nil
            }
        }
        return Task { @MainActor in
            if let debounce {
                for await spaceID in switches.debounce(for: debounce) {
                    await body(spaceID)
                }
            } else {
                for await spaceID in switches {
                    await body(spaceID)
                }
            }
        }
    }

    /// Runs body each time a Space is created or deleted, after debounce has passed quietly.
    func spaceListTask(
        debounce: Duration,
        perform body: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let listChanges = changes().filter { $0 == .spaceList }.debounce(for: debounce)
        return Task { @MainActor in
            for await _ in listChanges {
                await body()
            }
        }
    }
}

extension SpaceChanges {
    private static let diagLog = DiagLog(category: "SpaceChanges")

    /// The window server's Space events merged with NSWorkspace's notification,
    /// which also covers the case where the window server registration fails.
    static func liveFeed(center: NotificationCenter = NSWorkspace.shared.notificationCenter) -> AsyncStream<SpaceSignal> {
        let (stream, continuation) = AsyncStream<SpaceSignal>.makeStream()
        let registered = Bridging.setSpaceEventHandler { event in
            switch event {
            case .activeSpaceChanged: continuation.yield(.activeSpace)
            case .spacesChanged: continuation.yield(.spaceList)
            }
        }
        if !registered {
            diagLog.warning("Window server Space events are unavailable; using NSWorkspace notifications only")
        }
        nonisolated(unsafe) let observer = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil) { _ in
            continuation.yield(.activeSpace)
        }
        continuation.onTermination = { _ in
            center.removeObserver(observer)
        }
        return stream
    }
}
