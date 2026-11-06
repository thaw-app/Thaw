//
//  SpaceIndicator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation
import PlatformRuntimeKit

/// What the Space indicator item shows. Must match SpaceIndicatorSnapshot in ThawExtraHelper.
nonisolated struct SpaceIndicatorSnapshot: Codable, Equatable, Sendable {
    struct Space: Codable, Equatable, Sendable {
        var label: String
        var isCurrent: Bool
    }

    struct Display: Codable, Equatable, Sendable {
        var name: String
        var hasMenuBar: Bool
        var spaces: [Space]
    }

    /// The active Space's name, drawn in the menu bar.
    var title: String
    var displays: [Display]

    /// Names Spaces as SpaceLabels does, marking the Space each display shows now.
    static func make(
        spaces: [Bridging.ManagedSpace],
        current: Set<CGSSpaceID>,
        active: CGSSpaceID,
        displayNames: [String: String],
        menuBarDisplay: String?,
        ownerName: (pid_t) -> String?
    ) -> SpaceIndicatorSnapshot {
        let spaceIDs = Dictionary(spaces.map { ($0.persistentKey, $0.spaceID) }) { first, _ in first }
        let groups = SpaceLabels.groups(spaces, displayNames: displayNames, menuBarDisplay: menuBarDisplay, ownerName: ownerName)
        return SpaceIndicatorSnapshot(
            title: SpaceLabels.label(ofSpaceID: active, in: spaces, ownerName: ownerName)
                ?? String(localized: "Space", comment: "The Space indicator's title before Thaw knows the active Space."),
            displays: groups.map { group in
                Display(name: group.displayName, hasMenuBar: group.hasMenuBar, spaces: group.spaces.map { choice in
                    Space(label: choice.label, isCurrent: spaceIDs[choice.id].map(current.contains) ?? false)
                })
            }
        )
    }
}

/// Where Thaw leaves the snapshot for the helper. Must match SpaceIndicatorChannel in ThawExtraHelper.
nonisolated enum SpaceIndicatorChannel {
    static func file(in folder: URL) -> URL {
        folder.appending(path: "space.json")
    }

    static func notification(parent: String) -> Notification.Name {
        Notification.Name("\(parent).extra.space.update")
    }
}

/// Writes each new snapshot and tells the helper to read it.
@MainActor
final class SpaceIndicatorPublisher {
    static let shared = SpaceIndicatorPublisher()

    private let folder: URL
    private let announce: @MainActor () -> Void
    private var last: SpaceIndicatorSnapshot?
    private let log = DiagLog(category: "SpaceIndicator")

    /// The folder and the announcement are parameters so tests write to a scratch folder and post nothing.
    init(folder: URL = ItemStandInSlot.folder, announce: @escaping @MainActor () -> Void = SpaceIndicatorPublisher.announceToHelper) {
        self.folder = folder
        self.announce = announce
    }

    func publish(_ snapshot: SpaceIndicatorSnapshot) {
        guard snapshot != last else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: SpaceIndicatorChannel.file(in: folder), options: .atomic)
        } catch {
            log.error("could not write the Space indicator: \(error.localizedDescription)")
            return
        }
        last = snapshot
        announce()
    }

    private static func announceToHelper() {
        DistributedNotificationCenter.default().postNotificationName(
            SpaceIndicatorChannel.notification(parent: ThawMenuBarIdentity.bundleIdentifier),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

/// Runs the Space indicator item while its setting is on, and hands it the active Space after each switch.
@MainActor
final class SpaceIndicator {
    private let launcher: SystemExtraStandInLauncher
    private let read: @MainActor () -> SpaceIndicatorSnapshot
    private let publish: @MainActor (SpaceIndicatorSnapshot) -> Void
    private(set) var isEnabled = false
    private var tasks: [Task<Void, Never>] = []
    private let log = DiagLog(category: "SpaceIndicator")

    init(
        launcher: SystemExtraStandInLauncher,
        read: @escaping @MainActor () -> SpaceIndicatorSnapshot = SpaceIndicator.liveSnapshot,
        publish: @escaping @MainActor (SpaceIndicatorSnapshot) -> Void = { SpaceIndicatorPublisher.shared.publish($0) }
    ) {
        self.launcher = launcher
        self.read = read
        self.publish = publish
    }

    func start(settings: AdvancedSettings, changes: SpaceChanges, directory: SpaceDirectory) {
        tasks.append(Task { [weak self, weak settings] in
            for await enabled in Observations({ settings?.showSpaceIndicator ?? false }) {
                await self?.setEnabled(enabled)
            }
        })
        tasks.append(changes.activeSpaceTask { [weak self] _ in self?.refresh() })
        tasks.append(Task { [weak self, weak directory] in
            for await _ in Observations({ directory?.spaces ?? [] }) {
                self?.refresh()
            }
        })
    }

    /// The snapshot is written before the item starts, so it never draws an empty title.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard enabled else {
            launcher.stop(.space)
            return
        }
        refresh()
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(SystemExtraStandIn.space.itemIdentifier)
        let section = launcher.controller?.authoredSection(for: identifier) ?? .visible
        do {
            // The item replaces nothing, so there is no original to follow in the order.
            try await launcher.launch(.space, replacing: "", in: section)
        } catch {
            isEnabled = false
            log.error("Space indicator failed to start: \(error.localizedDescription)")
        }
    }

    func refresh() {
        guard isEnabled else { return }
        publish(read())
    }

    static func liveSnapshot() -> SpaceIndicatorSnapshot {
        var names: [String: String] = [:]
        var current: Set<CGSSpaceID> = []
        for screen in NSScreen.screens {
            if let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) {
                names[uuid] = screen.localizedName
            }
            if let spaceID = Bridging.getCurrentSpaceID(for: screen.displayID) {
                current.insert(spaceID)
            }
        }
        return .make(
            spaces: SpaceLabels.liveSpaces(),
            current: current,
            active: Bridging.getActiveSpaceID(),
            displayNames: names,
            menuBarDisplay: Bridging.getActiveMenuBarDisplayUUID(),
            ownerName: SpaceLabels.liveOwnerName
        )
    }
}
