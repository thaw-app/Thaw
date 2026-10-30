//
//  MenuBarItemVolatilityIndexTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("The volatility index classifies how often an item's picture changes", .scratchDefaults)
struct MenuBarItemVolatilityIndexTests {
    private typealias Index = MenuBarItemVolatilityIndex
    private typealias Thresholds = MenuBarItemVolatilityIndex.Thresholds

    private func tag(_ title: String, namespace: MenuBarItemTag.Namespace = .string("com.example.volatile")) -> MenuBarItemTag {
        MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0)
    }

    private func observe(_ index: Index, _ tag: MenuBarItemTag, changes: [Bool]) {
        for changed in changes {
            index.record(tag: tag, changed: changed, width: 22)
        }
    }

    @Test("An item stays unknown until it has enough observations")
    func unknownUntilEnoughObservations() {
        var record = Index.Record()
        #expect(record.volatility == .unknown)
        #expect(record.changeRate == 0)
        for _ in 0 ..< Thresholds.minimumObservations - 1 {
            record.record(changed: false, width: 20)
        }
        #expect(record.volatility == .unknown)
        #expect(record.lastWidth == 20)
    }

    @Test("A long unchanged streak is stable")
    func stableAfterStreak() {
        var record = Index.Record()
        for _ in 0 ..< Thresholds.stableStreak {
            record.record(changed: false, width: nil)
        }
        #expect(record.volatility == .stable)
        #expect(record.unchangedStreak == Thresholds.stableStreak)
        #expect(record.lastWidth == nil)
    }

    @Test("Enough observations without the stable streak read as occasional")
    func occasionalWithoutStreak() {
        var record = Index.Record()
        record.record(changed: true, width: 0)
        for _ in 0 ..< Thresholds.minimumObservations {
            record.record(changed: false, width: -3)
        }
        #expect(record.volatility == .occasional)
        #expect(record.lastWidth == nil)
        #expect(record.changes == 1)
    }

    @Test("Changing on most refreshes is live")
    func liveWhenChangingOften() {
        var record = Index.Record()
        for index in 0 ..< Thresholds.minimumObservations {
            record.record(changed: index.isMultiple(of: 2), width: 30)
        }
        #expect(record.changeRate == 0.5)
        #expect(record.volatility == .live)
    }

    @Test("Classifications are keyed by tag identifier")
    func classificationsByKey() {
        let index = Index()
        let clock = tag("Clock")
        let wifi = tag("Wi-Fi")
        observe(index, clock, changes: Array(repeating: true, count: Thresholds.minimumObservations))
        observe(index, wifi, changes: Array(repeating: false, count: Thresholds.stableStreak))
        observe(index, tag("New"), changes: [false])

        let classes = index.classificationsByKey()

        #expect(classes[clock.tagIdentifier] == .live)
        #expect(classes[wifi.tagIdentifier] == .stable)
        #expect(classes[tag("New").tagIdentifier] == .unknown)
    }

    @Test("Pruning keeps only the given tags, and an empty set prunes nothing")
    func pruning() {
        let index = Index()
        observe(index, tag("A"), changes: [true])
        observe(index, tag("B"), changes: [true])

        index.prune(keeping: [])
        #expect(index.classificationsByKey().count == 2)

        index.prune(keeping: [tag("A")])
        #expect(Array(index.classificationsByKey().keys) == [tag("A").tagIdentifier])
    }

    @Test("Logging the distribution persists stable-namespace records, which a new index loads")
    func persistsAndReloads() {
        let index = Index()
        index.logDistributionIfChanged()
        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) == nil)

        let stable = tag("Battery")
        let session = tag("Session", namespace: .uuid(UUID()))
        observe(index, stable, changes: Array(repeating: false, count: Thresholds.stableStreak))
        observe(index, session, changes: [true, true])
        index.logDistributionIfChanged()
        // A second call with the same counts inside the throttle window is skipped.
        index.logDistributionIfChanged()

        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) != nil)
        let reloaded = Index()
        let classes = reloaded.classificationsByKey()
        #expect(classes[stable.tagIdentifier] == .stable)
        #expect(classes[session.tagIdentifier] == nil)
    }

    @Test("Only session-scoped records are not saved at all")
    func sessionOnlyRecordsAreNotSaved() {
        let index = Index()
        observe(index, tag("Session", namespace: .uuid(UUID())), changes: [true])
        index.logDistributionIfChanged()
        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) == nil)
    }

    @Test("Removing everything clears memory and the store")
    func removeAll() {
        let index = Index()
        observe(index, tag("A"), changes: [false])
        index.logDistributionIfChanged()
        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) != nil)

        index.removeAll()

        #expect(index.classificationsByKey().isEmpty)
        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) == nil)
    }

    @Test("A store from another version is dropped on load")
    func otherVersionIsDropped() {
        let json = #"{"version": 99, "records": {}}"#
        Defaults.set(Data(json.utf8), forKey: .menuBarItemVolatilityIndex)

        let index = Index()

        #expect(index.classificationsByKey().isEmpty)
        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) == nil)
    }

    @Test("An unreadable store is ignored and left in place")
    func unreadableStoreIsIgnored() {
        let garbage = Data("nope".utf8)
        Defaults.set(garbage, forKey: .menuBarItemVolatilityIndex)

        let index = Index()

        #expect(index.classificationsByKey().isEmpty)
        #expect(Defaults.data(forKey: .menuBarItemVolatilityIndex) == garbage)
    }

    @Test("Records unseen for longer than their lifetime are dropped on load")
    func expiredRecordsAreDropped() {
        let old = Date.now.addingTimeInterval(-Thresholds.persistedRecordLifetime - 60).timeIntervalSinceReferenceDate
        let fresh = Date.now.timeIntervalSinceReferenceDate
        let json = """
        {"version": 1, "records": {
          "old": {"observations": 3, "changes": 0, "unchangedStreak": 3, "lastObserved": \(old)},
          "fresh": {"observations": 3, "changes": 1, "unchangedStreak": 0, "lastObserved": \(fresh), "lastWidth": 24}
        }}
        """
        Defaults.set(Data(json.utf8), forKey: .menuBarItemVolatilityIndex)

        let index = Index()

        #expect(Array(index.classificationsByKey().keys) == ["fresh"])
    }

    @Test("Logging with moving items still persists them, and they reload with their class")
    func movingItemsPersist() {
        let index = Index()
        let live = tag("Live")
        let occasional = tag("Occasional")
        observe(index, live, changes: Array(repeating: true, count: Thresholds.minimumObservations))
        observe(index, occasional, changes: [true] + Array(repeating: false, count: Thresholds.minimumObservations))
        index.logDistributionIfChanged()

        let classes = Index().classificationsByKey()
        #expect(classes[live.tagIdentifier] == .live)
        #expect(classes[occasional.tagIdentifier] == .occasional)
    }

    @Test("A counter at its limit is halved with its changes, keeping the change rate")
    func saturatedCounterIsHalved() throws {
        let json = #"{"observations":\#(Int.max),"changes":\#(Int.max - 1),"unchangedStreak":0,"lastObserved":0}"#
        var record = try JSONDecoder().decode(Index.Record.self, from: Data(json.utf8))
        record.record(changed: true, width: nil)
        #expect(record.observations == Int.max / 2 + 1)
        #expect(record.changes == (Int.max - 1) / 2 + 1)
        #expect(record.volatility == .live)
    }
}
