//
//  SpaceIndicatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Two displays: on the left two desktops and a full screen app, on the right one desktop.
private let spaces = [
    Bridging.ManagedSpace(spaceID: 1, persistentKey: "display:L#default", displayIdentifier: "L", ordinal: 1),
    Bridging.ManagedSpace(spaceID: 2, persistentKey: "u2", displayIdentifier: "L", ordinal: 2),
    Bridging.ManagedSpace(spaceID: 3, persistentKey: "u3", displayIdentifier: "L", ordinal: 3, kind: .fullscreen, ownerPID: 77),
    Bridging.ManagedSpace(spaceID: 4, persistentKey: "u4", displayIdentifier: "R", ordinal: 1),
]

private func snapshot(current: Set<CGSSpaceID>, active: CGSSpaceID, menuBarDisplay: String? = "L") -> SpaceIndicatorSnapshot {
    SpaceIndicatorSnapshot.make(
        spaces: spaces,
        current: current,
        active: active,
        displayNames: ["L": "Studio Display", "R": "Built-in Display"],
        menuBarDisplay: menuBarDisplay,
        ownerName: { $0 == 77 ? "Safari" : nil }
    )
}

@Suite("Space indicator snapshot")
struct SpaceIndicatorSnapshotTests {
    @Test("The title is the active Space's Mission Control name")
    func titleNamesTheActiveSpace() {
        #expect(snapshot(current: [2, 4], active: 2).title == "Desktop 2")
        #expect(snapshot(current: [3, 4], active: 3).title == "Safari")
        #expect(snapshot(current: [1, 4], active: 4).title == "Desktop 1")
    }

    @Test("An active Space the list doesn't have yet gets the plain name")
    func unknownActiveSpace() {
        #expect(snapshot(current: [], active: 99).title == String(localized: "Space"))
    }

    @Test("Each display lists its Spaces in order with its current one marked")
    func displaysMarkTheirCurrentSpace() {
        let result = snapshot(current: [2, 4], active: 2)

        #expect(result.displays.map(\.name) == ["Studio Display", "Built-in Display"])
        #expect(result.displays.map(\.hasMenuBar) == [true, false])
        #expect(result.displays[0].spaces == [
            .init(label: "Desktop 1", isCurrent: false),
            .init(label: "Desktop 2", isCurrent: true),
            .init(label: "Safari", isCurrent: false),
        ])
        #expect(result.displays[1].spaces == [.init(label: "Desktop 1", isCurrent: true)])
    }

    @Test("The snapshot survives the trip through the file the helper reads")
    func roundTrips() throws {
        let original = snapshot(current: [1, 4], active: 1)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SpaceIndicatorSnapshot.self, from: data) == original)
    }
}

@MainActor
@Suite("Space indicator publishing")
struct SpaceIndicatorPublisherTests {
    private func scratchFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "SpaceIndicatorTests-\(UUID().uuidString)")
    }

    @Test("A new snapshot is written and announced once; the same one again is not")
    func writesAndAnnouncesChangesOnly() throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var announcements = 0
        let publisher = SpaceIndicatorPublisher(folder: folder) { announcements += 1 }
        let first = snapshot(current: [1, 4], active: 1)

        publisher.publish(first)
        publisher.publish(first)

        #expect(announcements == 1)
        let stored = try Data(contentsOf: SpaceIndicatorChannel.file(in: folder))
        #expect(try JSONDecoder().decode(SpaceIndicatorSnapshot.self, from: stored) == first)

        publisher.publish(snapshot(current: [2, 4], active: 2))
        #expect(announcements == 2)
    }

    @Test("A folder that can't be written announces nothing")
    func unwritableFolderAnnouncesNothing() throws {
        let blocker = scratchFolder()
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data().write(to: blocker)
        var announcements = 0
        let publisher = SpaceIndicatorPublisher(folder: blocker.appending(path: "inside")) { announcements += 1 }

        publisher.publish(snapshot(current: [1], active: 1))

        #expect(announcements == 0)
    }

    @Test("The channel names match the helper's")
    func channelNames() {
        #expect(SpaceIndicatorChannel.file(in: URL(filePath: "/x")).path == "/x/space.json")
        #expect(SpaceIndicatorChannel.notification(parent: "com.example").rawValue == "com.example.extra.space.update")
    }
}

@MainActor
@Suite("Space indicator item")
struct SpaceIndicatorTests {
    @MainActor
    private final class Harness {
        let system = FakeStandInSystem()
        let sections = FakeStandInSections()
        let launcher: SystemExtraStandInLauncher
        var published: [SpaceIndicatorSnapshot] = []
        var current = snapshot(current: [1, 4], active: 1)
        let indicator: SpaceIndicator

        init() {
            launcher = SystemExtraStandInLauncher(system: system.system)
            launcher.controller = sections
            weak var weakSelf: Harness?
            indicator = SpaceIndicator(
                launcher: launcher,
                read: { weakSelf?.current ?? snapshot(current: [], active: 0) },
                publish: { weakSelf?.published.append($0) }
            )
            weakSelf = self
        }
    }

    private var identifier: String {
        MenuBarItemTag.canonicalPersistentIdentifier(SystemExtraStandIn.space.itemIdentifier)
    }

    @Test("Turning it on publishes the Space first, then starts the item in Visible")
    func enablingLaunches() async {
        let harness = Harness()

        await harness.indicator.setEnabled(true)

        #expect(harness.published == [harness.current])
        #expect(harness.system.opened(.space) == 1)
        #expect(harness.sections.authoredSection(for: identifier) == .visible)
    }

    @Test("An item placed in Hidden earlier stays there")
    func keepsAnEarlierPlacement() async {
        let harness = Harness()
        harness.sections.sectionAssignment[identifier] = .hidden

        await harness.indicator.setEnabled(true)

        #expect(harness.sections.authoredSection(for: identifier) == .hidden)
    }

    @Test("Turning it on twice starts one item, and turning it off quits it")
    func disablingStops() async throws {
        let harness = Harness()

        await harness.indicator.setEnabled(true)
        await harness.indicator.setEnabled(true)
        #expect(harness.system.opened(.space) == 1)

        await harness.indicator.setEnabled(false)
        let process = try #require(harness.system.startedProcesses.first)
        #expect(process.terminateCalls == 1)
        #expect(!harness.launcher.wanted.contains(.space))
    }

    @Test("A Space change republishes only while the item is on")
    func refreshFollowsTheSwitch() async {
        let harness = Harness()

        harness.indicator.refresh()
        #expect(harness.published.isEmpty)

        await harness.indicator.setEnabled(true)
        harness.current = snapshot(current: [2, 4], active: 2)
        harness.indicator.refresh()

        #expect(harness.published.last?.title == "Desktop 2")
    }

    @Test("A launch that fails can be tried again")
    func failedLaunchRetries() async {
        let harness = Harness()
        harness.system.missingBundles = [SystemExtraStandIn.space.bundleURL]

        await harness.indicator.setEnabled(true)
        #expect(harness.system.opened(.space) == 0)

        harness.system.missingBundles = []
        await harness.indicator.setEnabled(true)
        #expect(harness.system.opened(.space) == 1)
    }

    @Test("A start the system refuses leaves the launcher without the item, and can be tried again")
    func refusedOpenIsForgotten() async {
        let harness = Harness()
        harness.system.openError = CocoaError(.fileNoSuchFile)

        await harness.indicator.setEnabled(true)
        #expect(!harness.indicator.isEnabled)
        #expect(!harness.launcher.wanted.contains(.space))
        #expect(!harness.launcher.placed.contains(.space))

        harness.system.openError = nil
        await harness.indicator.setEnabled(true)
        #expect(harness.indicator.isEnabled)
        #expect(harness.launcher.wanted.contains(.space))
    }

    @Test("The live read has a title and at most one current Space per display")
    func liveSnapshotIsWellFormed() {
        _ = SpaceIndicator(launcher: SystemExtraStandInLauncher(system: FakeStandInSystem().system))

        let live = SpaceIndicator.liveSnapshot()

        #expect(!live.title.isEmpty)
        #expect(live.displays.allSatisfy { $0.spaces.count(where: \.isCurrent) <= 1 })
    }

    @Test("The setting starts off")
    func settingDefaultsOff() {
        #expect(Defaults.DefaultValue.showSpaceIndicator == false)
    }
}

@MainActor
@Suite("Space indicator wiring", .serialized, .scratchDefaults)
struct SpaceIndicatorWiringTests {
    /// Waits until condition holds, so the observation tasks get to run.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 500 where !condition() {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    @Test("The setting starts and stops the item, and a Space switch republishes")
    func followsTheSettingAndTheSwitch() async {
        let system = FakeStandInSystem()
        let launcher = SystemExtraStandInLauncher(system: system.system)
        launcher.controller = FakeStandInSections()
        var published: [SpaceIndicatorSnapshot] = []
        var active: CGSSpaceID = 1
        let indicator = SpaceIndicator(
            launcher: launcher,
            read: { snapshot(current: [active, 4], active: active) },
            publish: { published.append($0) }
        )
        let settings = SpacesSettings()
        let changes = SpaceChanges(activeSpaceID: { active })
        indicator.start(settings: settings, changes: changes, directory: SpaceDirectory(read: { spaces }))

        settings.showSpaceIndicator = true
        #expect(await eventually { system.opened(.space) == 1 })

        active = 2
        changes.admit(.activeSpace)
        #expect(await eventually { published.last?.title == "Desktop 2" })

        settings.showSpaceIndicator = false
        #expect(await eventually { !indicator.isEnabled })
    }
}
