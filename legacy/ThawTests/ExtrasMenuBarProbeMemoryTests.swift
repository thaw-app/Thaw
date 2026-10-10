//
//  ExtrasMenuBarProbeMemoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins what carries across launches about which applications have an extras
/// menu bar, and what does not.
///
/// The memory keeps the first scan off apps that never had one (seconds of
/// probing, #956). A wrong entry costs a scan, never an answer, but it must
/// not stay wrong, so every rule is biased toward re-probing.
@Suite("Extras menu bar probe memory")
struct ExtrasMenuBarProbeMemoryTests {
    // MARK: Seeding

    /// An unknown application is probed on the cold-start scan as usual.
    @Test("An unknown application is not seeded")
    func unknownApplicationIsNotSeeded() {
        #expect(ExtrasMenuBarProbeMemory.seed(forRememberedMisses: nil) == nil)
    }

    /// An application probed while still launching can report no extras menu bar.
    @Test("A single remembered miss is not enough to seed")
    func singleMissIsNotEnoughToSeed() {
        #expect(ExtrasMenuBarProbeMemory.seed(forRememberedMisses: 1) == nil)
        #expect(ExtrasMenuBarProbeMemory.seed(forRememberedMisses: 0) == nil)
    }

    /// The count carries so a confirming miss resumes the ladder instead of
    /// climbing it a second time.
    @Test("A settled application resumes its rung on the ladder")
    func settledApplicationResumesItsRung() {
        let seed = ExtrasMenuBarProbeMemory.seed(forRememberedMisses: 3)
        #expect(seed?.misses == 3)
    }

    /// Memory skips the cold-start scan but must not buy five minutes of
    /// silence from an app that gained a status item since last launch.
    @Test("A seeded deadline is always the first rung")
    func seededDeadlineIsAlwaysTheFirstRung() {
        for misses in 2...50 {
            #expect(
                ExtrasMenuBarProbeMemory.seed(forRememberedMisses: misses)?.initialTTL
                    == ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 1)
            )
        }
    }

    /// Counting past the ladder's top rung records nothing it can act on.
    @Test("A seeded count is capped where the ladder saturates")
    func seededCountIsCapped() {
        #expect(ExtrasMenuBarProbeMemory.seed(forRememberedMisses: 900)?.misses
            == ExtrasMenuBarProbeMemory.maximumRememberedMisses)
    }

    // MARK: Merging

    /// An application that came back empty twice is skipped next launch.
    @Test("A settled miss is remembered")
    func settledMissIsRemembered() {
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: [:],
            observed: ["com.example.quiet": 3],
            runningBundleIDs: ["com.example.quiet"]
        )
        #expect(merged["com.example.quiet"] == 3)
    }

    /// A stale entry here would skip the app's probe on every future launch.
    @Test("An application that gained an extras menu bar is forgotten")
    func applicationThatGainedABarIsForgotten() {
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: ["com.example.grew": 4],
            observed: ["com.example.grew": 0],
            runningBundleIDs: ["com.example.grew"]
        )
        #expect(merged["com.example.grew"] == nil)
    }

    /// A single miss neither earns an entry nor keeps one.
    @Test("An unsettled miss is not remembered")
    func unsettledMissIsNotRemembered() {
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: ["com.example.flaky": 4],
            observed: ["com.example.flaky": 1],
            runningBundleIDs: ["com.example.flaky"]
        )
        #expect(merged["com.example.flaky"] == nil)
    }

    /// An application that was not running says nothing about itself, so what
    /// was learned about it survives sessions it sits out.
    @Test("An application that was not running keeps its entry")
    func absentApplicationKeepsItsEntry() {
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: ["com.example.absent": 4],
            observed: ["com.example.present": 2],
            runningBundleIDs: ["com.example.present"]
        )
        #expect(merged["com.example.absent"] == 4)
        #expect(merged["com.example.present"] == 2)
    }

    /// Counts are stored capped, so the ladder's top rung is the widest thing
    /// the memory can ask for.
    @Test("A stored count is capped where the ladder saturates")
    func storedCountIsCapped() {
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: [:],
            observed: ["com.example.ancient": 800],
            runningBundleIDs: ["com.example.ancient"]
        )
        #expect(merged["com.example.ancient"] == ExtrasMenuBarProbeMemory.maximumRememberedMisses)
    }

    /// Growth is bounded. Entries for apps that are not running go first,
    /// since they may never be read again.
    @Test("Overflow sheds the applications that are not running")
    func overflowShedsAbsentApplications() {
        let stale = (0..<(ExtrasMenuBarProbeMemory.capacity * 2)).reduce(into: [String: Int]()) {
            $0["com.example.stale\($1)"] = 4
        }
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: stale,
            observed: ["com.example.live": 2],
            runningBundleIDs: ["com.example.live"]
        )
        #expect(merged == ["com.example.live": 2])
    }

    /// Under capacity nothing is shed, so an application that simply was not
    /// running this session is not evicted for it.
    @Test("A memory under capacity is left intact")
    func memoryUnderCapacityIsLeftIntact() {
        let persisted = (0..<10).reduce(into: [String: Int]()) { $0["com.example.app\($1)"] = 4 }
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: persisted,
            observed: [:],
            runningBundleIDs: []
        )
        #expect(merged == persisted)
    }
}
