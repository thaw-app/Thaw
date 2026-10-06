//
//  DisplayTopology.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

/// The one owner of display changes.
///
/// macOS posts several screen-parameter notifications for one dock, lid,
/// wake or KVM switch, and the active menu bar moves with focus without
/// posting any. Each burst settles into one event with one generation, and
/// the reactions that change state run in a fixed order, each finishing
/// before the next starts: caches, then the item rescan, then spacing, then
/// the display's profile. Views that only re-measure or close subscribe to
/// screenParametersChanged instead, which fires at once.
@MainActor
final class DisplayTopology {
    static let shared = DisplayTopology()

    enum Source: Sendable {
        case screenParameters
        case activeBarMoved
    }

    struct Event: Sendable {
        let generation: Int
        let change: DisplayTopologyChange
        let source: Source
        let snapshot: DisplayTopologySnapshot
    }

    typealias Reaction = @MainActor (Event) async -> Void

    /// Long enough to swallow a dock or KVM flap, each of which could
    /// otherwise start a spacing relaunch wave.
    static let settleInterval = Duration.seconds(1)

    /// Every raw screen-parameter notification, delivered at once.
    let screenParametersChanged = PassthroughSubject<Void, Never>()

    private(set) var snapshot: DisplayTopologySnapshot
    private(set) var generation = 0

    private let snapshotProvider: @MainActor () -> DisplayTopologySnapshot
    private let settleInterval: Duration
    private var reactions = [Reaction]()
    private var pendingSource: Source?
    private var settleTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let diagLog = DiagLog(category: "DisplayTopology")

    init(
        settleInterval: Duration = DisplayTopology.settleInterval,
        snapshotProvider: @escaping @MainActor () -> DisplayTopologySnapshot = DisplayTopology.liveSnapshot
    ) {
        self.settleInterval = settleInterval
        self.snapshotProvider = snapshotProvider
        snapshot = snapshotProvider()
    }

    /// Starts listening. reactions run in this order for every settled event.
    func start(reactions: [Reaction]) {
        self.reactions = reactions
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteScreenParametersChanged() }
        }
    }

    func noteScreenParametersChanged() {
        screenParametersChanged.send()
        schedule(.screenParameters)
    }

    /// For callers that notice the active bar moved, which posts nothing.
    func noteActiveBarMayHaveMoved() {
        guard Self.resolveActiveDisplayID() != snapshot.activeDisplayID else { return }
        schedule(.activeBarMoved)
    }

    /// The display whose menu bar is active, or nil while macOS names no
    /// connected display. The window server is asked rather than AppKit,
    /// which is wrong with "Displays have separate Spaces" off and lags after
    /// a topology change; its main-display fallback is what nil replaces.
    static func resolveActiveDisplayID() -> CGDirectDisplayID? {
        guard let displayID = Bridging.getActiveMenuBarDisplayID(),
              NSScreen.managedScreens.contains(where: { $0.displayID == displayID })
        else {
            return nil
        }
        return displayID
    }

    static func liveSnapshot() -> DisplayTopologySnapshot {
        DisplayTopologySnapshot(
            displays: NSScreen.managedScreens.map { .init(id: $0.displayID, frame: $0.frame) },
            activeDisplayID: resolveActiveDisplayID()
        )
    }

    private func schedule(_ source: Source) {
        // A screen-parameter change in the burst outranks an active-bar move.
        if pendingSource != .screenParameters {
            pendingSource = source
        }
        settleTask?.cancel()
        settleTask = Task { [weak self, settleInterval] in
            try? await Task.sleep(for: settleInterval)
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func settle() {
        guard let source = pendingSource else { return }
        pendingSource = nil
        let previousRun = reactionTask
        reactionTask = Task { [weak self] in
            // Events never overlap: the next waits for the previous one's reactions.
            await previousRun?.value
            await self?.deliver(source)
        }
    }

    private func deliver(_ source: Source) async {
        let current = snapshotProvider()
        let change = DisplayTopologyChange.between(snapshot, current)
        snapshot = current
        generation += 1
        let event = Event(generation: generation, change: change, source: source, snapshot: current)
        diagLog.info(
            "event \(event.generation): \(Self.describe(change)) from \(source), \(current.displays.count) display(s), active \(current.activeDisplayID.map { "\($0)" } ?? "none")"
        )
        for reaction in reactions {
            await reaction(event)
        }
    }

    private static func describe(_ change: DisplayTopologyChange) -> String {
        let names: [(DisplayTopologyChange, String)] = [
            (.connected, "connected"), (.disconnected, "disconnected"),
            (.rearranged, "rearranged"), (.activeBarMoved, "active bar moved"),
        ]
        let present = names.filter { change.contains($0.0) }.map(\.1)
        return present.isEmpty ? "no change" : present.joined(separator: ", ")
    }
}
