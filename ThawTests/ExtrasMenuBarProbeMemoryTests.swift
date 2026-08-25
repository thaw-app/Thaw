//
//  ExtrasMenuBarProbeMemoryTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins what carries across launches about which applications have an extras
/// menu bar, and — more importantly — what does not.
///
/// The memory exists to keep the first scan of a session off the ~155 of ~170
/// running applications that have never had an extras menu bar, which cost
/// 3.85s in the #956 log. It is allowed to be wrong: a wrong entry costs a
/// scan, never an answer. What it is not allowed to do is go on being wrong,
/// which is why every rule below is biased toward re-probing.
@Suite("Extras menu bar probe memory")
struct ExtrasMenuBarProbeMemoryTests {
    // MARK: Seeding

    /// Nothing remembered is nothing to act on: the application is probed on
    /// the cold-start scan exactly as it was before this memory existed.
    @Test("An unknown application is not seeded")
    func unknownApplicationIsNotSeeded() {
        #expect(ExtrasMenuBarProbeMemory.seed(forRememberedMisses: nil) == nil)
    }

    /// One miss is not evidence — an application probed while it was still
    /// launching reports no extras menu bar for reasons of its own.
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

    /// The deadline is the first rung whatever the count says. Memory is good
    /// enough to stay out of the cold-start scan and not good enough to buy
    /// five minutes of silence from an application that gained a status item
    /// since last launch.
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

    /// The ordinary case: an application that came back empty twice is worth
    /// skipping first thing next launch.
    @Test("A settled miss is remembered")
    func settledMissIsRemembered() {
        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: [:],
            observed: ["com.example.quiet": 3],
            runningBundleIDs: ["com.example.quiet"]
        )
        #expect(merged["com.example.quiet"] == 3)
    }

    /// The case that matters most. An application that has since published an
    /// extras menu bar loses its entry outright — a stale entry here would
    /// cost that application's items a skipped probe on every future launch,
    /// which is a permanent cost for a one-session observation.
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

    /// Growth is bounded across years of installing and removing apps. The
    /// overflow is shed rather than the live set, since an entry for an
    /// application that is not running is the one that may never be read
    /// again.
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
