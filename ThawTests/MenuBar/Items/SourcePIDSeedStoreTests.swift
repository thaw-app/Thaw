//
//  SourcePIDSeedStoreTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Source PID identity continuity")
struct SourcePIDSeedStoreTests {
    private struct LegacySeed: Codable {
        let windowID: CGWindowID
        let windowOwnerGeneration: ProcessGeneration
        let sourceGeneration: ProcessGeneration
        let bundleIdentifier: String?
        let processName: String?
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_400)
    private let sourceGeneration = ProcessGeneration(
        pid: 54484,
        launchDate: Date(timeIntervalSince1970: 1_700_000_100)
    )
    private let alternateGeneration = ProcessGeneration(
        pid: 8086,
        launchDate: Date(timeIntervalSince1970: 1_700_000_200)
    )
    private let ownerGeneration = ProcessGeneration(
        pid: 700,
        launchDate: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private func window(
        id: CGWindowID,
        ownerPID: pid_t = 700,
        bounds: CGRect = CGRect(x: 100, y: 0, width: 24, height: 22),
        title: String? = "Item-0",
        ownerName: String? = "Control Center",
        layer: Int = Int(CGWindowLevelForKey(.statusWindow))
    ) -> WindowInfo {
        WindowInfo(
            windowID: id,
            ownerPID: ownerPID,
            bounds: bounds,
            layer: layer,
            title: title,
            ownerName: ownerName
        )
    }

    private func seed(
        window itemWindow: WindowInfo,
        sourceGeneration: ProcessGeneration? = nil,
        bundleIdentifier: String? = "com.example.IconSwitcher",
        processName: String? = "Icon Switcher",
        capturedAt: Date? = nil
    ) -> SourcePIDSeed {
        SourcePIDSeed(
            windowID: itemWindow.windowID,
            windowOwnerGeneration: ownerGeneration,
            windowFingerprint: SourcePIDWindowFingerprint(window: itemWindow),
            sourceGeneration: sourceGeneration ?? self.sourceGeneration,
            bundleIdentifier: bundleIdentifier,
            processName: processName,
            capturedAt: capturedAt ?? now.addingTimeInterval(-30)
        )
    }

    private var bundledWindow: WindowInfo {
        window(id: 2314)
    }

    private var bundled: SourcePIDSeed {
        seed(window: bundledWindow)
    }

    private var bundlelessWindow: WindowInfo {
        window(id: 5467, title: "Bundleless")
    }

    private var bundleless: SourcePIDSeed {
        seed(
            window: bundlelessWindow,
            sourceGeneration: ProcessGeneration(
                pid: 12460,
                launchDate: Date(timeIntervalSince1970: 1_700_000_200)
            ),
            bundleIdentifier: nil,
            processName: "IconSwitcher"
        )
    }

    private func identity(
        generation: ProcessGeneration,
        bundleIdentifier: String?,
        processName: String?
    ) -> SourceProcessIdentity {
        SourceProcessIdentity(
            generation: generation,
            bundleIdentifier: bundleIdentifier,
            processName: processName
        )
    }

    private func ownerIdentity(
        generation: ProcessGeneration? = nil
    ) -> SourceProcessIdentity {
        identity(
            generation: generation ?? ownerGeneration,
            bundleIdentifier: "com.apple.controlcenter",
            processName: "Control Center"
        )
    }

    private func bundledSourceIdentity(
        generation: ProcessGeneration? = nil,
        bundleIdentifier: String? = "com.example.IconSwitcher"
    ) -> SourceProcessIdentity {
        identity(
            generation: generation ?? sourceGeneration,
            bundleIdentifier: bundleIdentifier,
            processName: "Icon Switcher"
        )
    }

    @Test("A bundled seed requires the exact source launch, bundle, host, and window")
    func bundledSeedRequiresExactIdentity() {
        let identities = [
            ownerGeneration.pid: ownerIdentity(),
            sourceGeneration.pid: bundledSourceIdentity(),
        ]
        #expect(SourcePIDSeedStore.isTrustworthy(
            bundled,
            for: bundledWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        ))

        let recycledSource = bundledSourceIdentity(
            generation: ProcessGeneration(
                pid: sourceGeneration.pid,
                launchDate: sourceGeneration.launchDate.addingTimeInterval(30)
            )
        )
        #expect(!SourcePIDSeedStore.isTrustworthy(
            bundled,
            for: bundledWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { pid in
                [ownerGeneration.pid: ownerIdentity(), sourceGeneration.pid: recycledSource][pid]
            }
        ))

        #expect(!SourcePIDSeedStore.isTrustworthy(
            bundled,
            for: bundledWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { pid in
                [
                    ownerGeneration.pid: ownerIdentity(),
                    sourceGeneration.pid: bundledSourceIdentity(bundleIdentifier: "com.example.Other"),
                ][pid]
            }
        ))
    }

    @Test("A bundle-less seed requires the same process name and exact launch")
    func bundlelessSeedRequiresMatchingName() {
        let matchingSource = identity(
            generation: bundleless.sourceGeneration,
            bundleIdentifier: nil,
            processName: "IconSwitcher"
        )
        #expect(SourcePIDSeedStore.isTrustworthy(
            bundleless,
            for: bundlelessWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { pid in
                [ownerGeneration.pid: ownerIdentity(), bundleless.pid: matchingSource][pid]
            }
        ))

        let newlyBundledSource = identity(
            generation: bundleless.sourceGeneration,
            bundleIdentifier: "com.example.IconSwitcher",
            processName: "IconSwitcher"
        )
        #expect(!SourcePIDSeedStore.isTrustworthy(
            bundleless,
            for: bundlelessWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { pid in
                [ownerGeneration.pid: ownerIdentity(), bundleless.pid: newlyBundledSource][pid]
            }
        ))
    }

    @Test("The newest of two live Control Center generations is required")
    func newestControlCenterGenerationRejectsRetiringHost() throws {
        let newestOwner = ProcessGeneration(
            pid: 701,
            launchDate: ownerGeneration.launchDate.addingTimeInterval(20)
        )
        let selected = try #require(SourcePIDSeedStore.newestGeneration(in: [
            newestOwner,
            ownerGeneration,
        ]))
        #expect(selected == newestOwner)

        let identities = [
            ownerGeneration.pid: ownerIdentity(),
            newestOwner.pid: ownerIdentity(generation: newestOwner),
            sourceGeneration.pid: bundledSourceIdentity(),
        ]
        #expect(!SourcePIDSeedStore.isTrustworthy(
            bundled,
            for: bundledWindow,
            currentControlCenterGeneration: selected,
            now: now,
            liveIdentity: { identities[$0] }
        ))
    }

    @Test("Seeds fill only unresolved windows with exact process generations")
    func applyingSeedsPreservesFreshResultsAndRejectsRecycledPIDs() {
        let recycledWindow = window(id: 71, title: "Recycled")
        let recycledGeneration = ProcessGeneration(
            pid: 12460,
            launchDate: Date(timeIntervalSince1970: 1_600_000_000)
        )
        let recycled = seed(
            window: recycledWindow,
            sourceGeneration: recycledGeneration,
            bundleIdentifier: "com.example.Old",
            processName: "Old"
        )
        let liveRecycledGeneration = ProcessGeneration(
            pid: recycledGeneration.pid,
            launchDate: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let identities: [pid_t: SourceProcessIdentity] = [
            ownerGeneration.pid: ownerIdentity(),
            sourceGeneration.pid: bundledSourceIdentity(),
            recycledGeneration.pid: identity(
                generation: liveRecycledGeneration,
                bundleIdentifier: "com.example.Old",
                processName: "Old"
            ),
        ]
        var pids: [pid_t?] = [nil, 8086, nil]

        let applied = SourcePIDSeedStore.apply(
            seeds: [bundled.windowID: bundled, recycled.windowID: recycled],
            to: &pids,
            windows: [bundledWindow, window(id: 2556), recycledWindow],
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        )

        #expect(Set(applied.keys) == [bundled.windowID])
        #expect(pids == [sourceGeneration.pid, 8086, nil])
    }

    @Test("Confirmed, seeded miss, then stale alternate keeps the confirmed baseline")
    func threeCycleResolverMissDoesNotLoseConfirmedBaseline() throws {
        let identities = [
            ownerGeneration.pid: ownerIdentity(),
            sourceGeneration.pid: bundledSourceIdentity(),
        ]

        let cycleOne = SourcePIDSeedStore.mergedConfirmedBaselines(
            previous: [:],
            fresh: [bundled],
            provisional: [:]
        )
        #expect(cycleOne[bundled.windowID] == bundled)

        var missedPID: [pid_t?] = [nil]
        let applied = SourcePIDSeedStore.apply(
            seeds: cycleOne,
            to: &missedPID,
            windows: [bundledWindow],
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        )
        let cycleTwo = SourcePIDSeedStore.mergedConfirmedBaselines(
            previous: cycleOne,
            fresh: [],
            provisional: applied
        )
        #expect(cycleTwo == cycleOne)

        let baseline = try #require(cycleTwo[bundled.windowID])
        let reconciledPID = SourcePIDSeedStore.reconciledSourcePID(
            currentPID: alternateGeneration.pid,
            previous: baseline,
            for: bundledWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        )
        #expect(reconciledPID == sourceGeneration.pid)
    }

    @Test("Same-host reuse of a window ID needs bounded fingerprint continuity")
    func sameHostWindowIDReuseIsRejected() {
        let identities = [
            ownerGeneration.pid: ownerIdentity(),
            sourceGeneration.pid: bundledSourceIdentity(),
        ]
        let reusedWindow = window(
            id: bundled.windowID,
            bounds: CGRect(x: 100, y: 0, width: 36, height: 22),
            title: "Other Item"
        )
        #expect(!SourcePIDSeedStore.isTrustworthy(
            bundled,
            for: reusedWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        ))

        let expired = seed(
            window: bundledWindow,
            capturedAt: now.addingTimeInterval(-SourcePIDSeedStore.maximumSeedAge - 1)
        )
        #expect(!SourcePIDSeedStore.isTrustworthy(
            expired,
            for: bundledWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        ))

        let movedWindow = window(
            id: bundled.windowID,
            bounds: CGRect(x: -4000, y: 0, width: 24, height: 22)
        )
        #expect(SourcePIDSeedStore.isTrustworthy(
            bundled,
            for: movedWindow,
            currentControlCenterGeneration: ownerGeneration,
            now: now,
            liveIdentity: { identities[$0] }
        ))
    }

    @Test("Only resolved non-control windows on the selected host produce seeds")
    func seedExtractionFiltersUnsafeEntries() {
        let items = [
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.IconSwitcher", title: "Item-0", windowID: 2314),
                windowID: 2314,
                sourcePID: sourceGeneration.pid,
                ownerPID: ownerGeneration.pid
            ),
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.IconSwitcher", title: "Item-0", windowID: 2314),
                windowID: 2314,
                sourcePID: sourceGeneration.pid,
                ownerPID: ownerGeneration.pid
            ),
            MenuBarItem.fixture(
                tag: .hiddenControlItem,
                windowID: 5718,
                sourcePID: 17950,
                ownerPID: ownerGeneration.pid
            ),
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.Unknown", title: "Item-0", windowID: 99),
                windowID: 99,
                sourcePID: 999,
                ownerPID: ownerGeneration.pid
            ),
        ]
        let identities = [
            ownerGeneration.pid: ownerIdentity(),
            sourceGeneration.pid: bundledSourceIdentity(),
        ]

        let seeds = SourcePIDSeedStore.seeds(
            from: items,
            windowsByID: [bundled.windowID: bundledWindow],
            currentControlCenterGeneration: ownerGeneration,
            capturedAt: bundled.capturedAt,
            identity: { identities[$0] }
        )

        #expect(seeds == [bundled])
    }

    @Test("Fresh confirmations persist beside independently retained provisional entries")
    func mixedProvisionalAndFreshPersistence() {
        let freshWindow = window(id: 9001, title: "Fresh")
        let fresh = seed(
            window: freshWindow,
            sourceGeneration: alternateGeneration,
            bundleIdentifier: "com.example.Fresh",
            processName: "Fresh"
        )
        let vanished = seed(window: window(id: 7777, title: "Vanished"))
        let previous = [
            bundled.windowID: bundled,
            vanished.windowID: vanished,
        ]

        let confirmed = SourcePIDSeedStore.mergedConfirmedBaselines(
            previous: previous,
            fresh: [fresh],
            provisional: [bundled.windowID: bundled]
        )
        #expect(confirmed == [bundled.windowID: bundled, fresh.windowID: fresh])

        let persisted = SourcePIDSeedStore.mergedPersistedSeeds(
            fresh: [fresh],
            provisional: [bundled.windowID: bundled]
        )
        #expect(persisted == [bundled, fresh])
    }

    @Test("Unchanged seeds coalesce writes but periodically refresh freshness")
    func captureTimeCoalescingAvoidsPerCycleWrites() {
        let recent = seed(window: bundledWindow, capturedAt: now.addingTimeInterval(-30))
        let proposed = seed(window: bundledWindow, capturedAt: now)

        #expect(SourcePIDSeedStore.coalescingCaptureTimes(
            proposed: [proposed],
            previous: [recent.windowID: recent],
            now: now
        ) == [recent])

        let old = seed(window: bundledWindow, capturedAt: now.addingTimeInterval(-61))
        #expect(SourcePIDSeedStore.coalescingCaptureTimes(
            proposed: [proposed],
            previous: [old.windowID: old],
            now: now
        ) == [proposed])
    }

    @Test("Seeds round-trip while corrupt and pre-fingerprint defaults fail closed")
    func persistenceRoundTripAndMigration() throws {
        let suiteName = "com.stonerl.Thaw.tests.SourcePIDSeeds.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SourcePIDSeedStore.save([bundled, bundleless], to: defaults)
        #expect(SourcePIDSeedStore.load(from: defaults) == [
            bundled.windowID: bundled,
            bundleless.windowID: bundleless,
        ])

        let legacy = LegacySeed(
            windowID: bundled.windowID,
            windowOwnerGeneration: ownerGeneration,
            sourceGeneration: sourceGeneration,
            bundleIdentifier: bundled.bundleIdentifier,
            processName: bundled.processName
        )
        try defaults.set(JSONEncoder().encode([legacy]), forKey: SourcePIDSeedStore.defaultsKey)
        #expect(SourcePIDSeedStore.load(from: defaults).isEmpty)

        defaults.set(Data("not json".utf8), forKey: SourcePIDSeedStore.defaultsKey)
        #expect(SourcePIDSeedStore.load(from: defaults).isEmpty)
    }
}
