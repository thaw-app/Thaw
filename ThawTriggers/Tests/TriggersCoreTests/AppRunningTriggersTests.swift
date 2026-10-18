//
//  AppRunningTriggersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
import ThawModuleTestSupport
@testable import TriggersCore

@MainActor
@Suite("App-running triggers")
struct AppRunningTriggersTests {
    private func rule(app: String = "test.editor", target: String = "test.helper:Item") -> AppRunningTrigger {
        AppRunningTrigger(appBundleID: app, appName: app, targets: [.init(id: target, name: target)])
    }

    private func withManager(_ body: (AppRunningTriggersManager, UserDefaults) throws -> Void) throws {
        let suite = ScratchSuites.name("AppRunningTriggersTests")
        let store = try #require(UserDefaults(suiteName: suite))
        let manager = AppRunningTriggersManager(store: store)
        defer {
            manager.stop()
            ScratchSuites.remove(suite)
        }
        try body(manager, store)
    }

    @Test("App-running condition uses bundle identity, not the frontmost app")
    func condition() {
        var trigger = rule()
        #expect(trigger.matches(runningBundleIDs: ["test.other", "test.editor"]))
        #expect(!trigger.matches(runningBundleIDs: ["test.editor.helper"]))
        trigger.isEnabled = false
        #expect(!trigger.matches(runningBundleIDs: ["test.editor"]))
        trigger.isEnabled = true
        trigger.appBundleID = ""
        #expect(!trigger.matches(runningBundleIDs: [""]))
    }

    @Test("A pid listed twice is one app, not a crash")
    func duplicatePID() {
        let apps = AppRunningTriggersManager.bundleIDsByPID([(10, "test.editor"), (10, "test.editor"), (11, "test.other")])
        #expect(apps == [10: "test.editor", 11: "test.other"])
    }

    @Test("Apps with no pid yet all still count as running")
    func appsWithoutPID() {
        let apps = AppRunningTriggersManager.bundleIDsByPID([(-1, "test.editor"), (-1, "test.other"), (12, "test.third")])
        #expect(Set(apps.values) == ["test.editor", "test.other", "test.third"])
    }

    @Test("Startup, repeated snapshots, and the last process quitting balance one hold")
    func lifecycle() throws {
        try withManager { manager, _ in
            #expect(manager.save(rule()))
            var events: [String] = []
            manager.start(notificationCenter: NotificationCenter(), runningApplications: { [1: "test.editor"] },
                          reveal: { events.append("+\($0)") }, release: { events.append("-\($0)") })
            manager.updateRunningApplications([1: "test.editor", 2: "test.editor"])
            manager.updateRunningApplications([2: "test.editor"])
            #expect(events == ["+test.helper:Item"])
            manager.updateRunningApplications([:])
            manager.updateRunningApplications([:])
            #expect(events == ["+test.helper:Item", "-test.helper:Item"])
        }
    }

    @Test("Overlapping triggers share a hold until the last matching rule ends")
    func overlappingRules() throws {
        try withManager { manager, _ in
            let first = rule()
            let second = rule(app: "test.other")
            manager.save(first)
            manager.save(second)
            var events: [String] = []
            manager.start(notificationCenter: NotificationCenter(), runningApplications: { [1: "test.editor", 2: "test.other"] },
                          reveal: { events.append("+\($0)") }, release: { events.append("-\($0)") })
            manager.remove(id: first.id)
            #expect(events == ["+test.helper:Item"])
            manager.setEnabled(false, id: second.id)
            #expect(events == ["+test.helper:Item", "-test.helper:Item"])
            manager.setEnabled(true, id: second.id)
            #expect(events.last == "+test.helper:Item")
            manager.stop()
            #expect(events.last == "-test.helper:Item")
            #expect(events.count == 4)
            manager.stop()
            #expect(events.count == 4)
        }
    }

    @Test("Editing active targets releases the old target and holds the replacement")
    func edits() throws {
        try withManager { manager, _ in
            var trigger = rule()
            manager.save(trigger)
            var held = Set<String>()
            manager.start(notificationCenter: NotificationCenter(), runningApplications: { [1: "test.editor"] },
                          reveal: { held.insert($0) }, release: { held.remove($0) })
            trigger.targets = [.init(id: "test.new:Item", name: "New item")]
            manager.save(trigger)
            #expect(held == ["test.new:Item"])
            trigger.appBundleID = "test.not-running"
            manager.save(trigger)
            #expect(held.isEmpty)
        }
    }

    @Test("Rules persist but running state and holds do not")
    func persistence() throws {
        try withManager { manager, store in
            let trigger = rule()
            manager.save(trigger)
            manager.updateRunningApplications([1: "test.editor"])
            let restored = AppRunningTriggersManager(store: store)
            #expect(restored.rules == [trigger])
            #expect(restored.runningBundleIDs.isEmpty)
            #expect(restored.canEdit)
        }
    }

    @Test("Invalid edits leave persisted rules untouched")
    func invalidRules() throws {
        try withManager { manager, store in
            let original = rule()
            manager.save(original)
            let before = store.data(forKey: AppRunningTriggersManager.storageKey)
            var invalid = original
            invalid.targets = []
            #expect(!manager.save(invalid))
            invalid = original
            invalid.targets.append(invalid.targets[0])
            #expect(!manager.save(invalid))
            #expect(manager.rules == [original])
            #expect(store.data(forKey: AppRunningTriggersManager.storageKey) == before)
        }
    }

    @Test("Unreadable or future data is preserved until an explicit reset", arguments: [
        Data("not json".utf8), Data(#"{"version":2,"rules":[]}"#.utf8),
    ])
    func unreadableData(data: Data) throws {
        try withManager { _, store in
            store.set(data, forKey: AppRunningTriggersManager.storageKey)
            let manager = AppRunningTriggersManager(store: store)
            #expect(!manager.canEdit)
            #expect(manager.errorMessage == nil, "The window shows its own section, so no alert as well")
            #expect(!manager.save(rule()))
            manager.remove(id: UUID())
            #expect(store.data(forKey: AppRunningTriggersManager.storageKey) == data)
            manager.reset()
            #expect(manager.canEdit)
            #expect(manager.errorMessage == nil)
            #expect(manager.save(rule()))
        }
    }

    @Test("Unexpected stored types are preserved rather than replaced")
    func unexpectedStoredType() throws {
        try withManager { _, store in
            let key = AppRunningTriggersManager.storageKey
            store.set("old or damaged value", forKey: key)
            let manager = AppRunningTriggersManager(store: store)
            #expect(!manager.canEdit)
            #expect(!manager.save(rule()))
            #expect(store.string(forKey: key) == "old or damaged value")
        }
    }

    @Test("Reset releases holds and removes only the triggers")
    func reset() throws {
        try withManager { manager, store in
            store.set(true, forKey: "unrelated")
            manager.save(rule())
            var held = Set<String>()
            manager.start(notificationCenter: NotificationCenter(), runningApplications: { [1: "test.editor"] },
                          reveal: { held.insert($0) }, release: { held.remove($0) })
            manager.reset()
            #expect(held.isEmpty)
            #expect(manager.rules.isEmpty)
            #expect(store.data(forKey: AppRunningTriggersManager.storageKey) == nil)
            #expect(store.bool(forKey: "unrelated"))
        }
    }

    @Test("Started without a snapshot source, the manager reads the apps that are really running")
    func defaultSnapshotReadsRunningApplications() throws {
        // The test runner of a Swift package has no bundle ID, so borrow one from an app that is running.
        let ownBundle = try #require(NSWorkspace.shared.runningApplications.lazy.compactMap(\.bundleIdentifier).first)
        try withManager { manager, _ in
            manager.save(rule(app: ownBundle, target: "test.helper:Running"))
            manager.save(rule(app: "com.example.thawtests.\(UUID().uuidString)", target: "test.helper:Absent"))
            var events: [String] = []

            manager.start(
                notificationCenter: NotificationCenter(),
                reveal: { events.append("+\($0)") },
                release: { events.append("-\($0)") }
            )

            #expect(events == ["+test.helper:Running"], "That app is running; the made-up app is not")
        }
    }

    @Test("Workspace launch and quit notifications drive updates without polling")
    func notifications() async throws {
        let suite = ScratchSuites.name("AppRunningTriggersTests")
        let store = try #require(UserDefaults(suiteName: suite))
        let manager = AppRunningTriggersManager(store: store)
        defer {
            manager.stop()
            ScratchSuites.remove(suite)
        }
        let center = NotificationCenter()
        var applications: [pid_t: String] = [:]
        manager.save(rule())
        var events: [String] = []
        await confirmation("launch reveals, quit releases", expectedCount: 2) { confirmed in
            manager.start(notificationCenter: center, runningApplications: { applications },
                          reveal: { events.append("+\($0)"); confirmed() },
                          release: { events.append("-\($0)"); confirmed() })
            applications = [1: "test.editor"]
            center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(events == ["+test.helper:Item"])
            applications = [:]
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(events == ["+test.helper:Item", "-test.helper:Item"])
        }
    }
}
