//
//  PlanSectionOrderStormTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Regression tests for the macOS 27 reorder "storm". Root cause: menu bar
/// items that vary their title (MeetingBar / Granola countdowns, live metrics)
/// mint a new saved identifier every time the title changes, and
/// planSectionOrder preserved every past title as a "closed app" — so
/// savedSectionOrder grew without bound (observed in the wild: 1,565 entries).
/// Because planSectionOrder is O(n²), that bloat made a single call take
/// ~250 ms and pinned a core on every recache. planSectionOrder now drops a
/// saved entry when its app (namespace) is present but the exact identifier is
/// not — a stale title-variant of a still-running app.
@Suite("Plan section order storm pruning")
struct PlanSectionOrderStormTests {
    @Test("Stale title-variants of a still-running app are pruned")
    func staleTitleVariantsOfRunningAppArePruned() {
        // "leits.MeetingBar" is running now with one current title.
        let current = ["leits.MeetingBar:Meeting in 3m", "com.other.app:Item-0"]
        // Saved order accumulated a long tail of past countdown titles.
        var saved = ["com.other.app:Item-0"]
        for minutes in 4 ... 120 { saved.append("leits.MeetingBar:Meeting in \(minutes)m") }
        saved.append("leits.MeetingBar:Meeting in 3m") // the current one

        let result = LayoutSolver.planSectionOrder(
            currentInSection: current,
            oldSavedForSection: saved,
            allCurrentIdentifiers: Set(current),
            allCurrentBaseIdentifiers: Set(current),
            allCurrentNamespaces: ["leits.MeetingBar", "com.other.app"]
        )

        let meetingBarEntries = result.filter { $0.hasPrefix("leits.MeetingBar:") }
        #expect(
            meetingBarEntries == ["leits.MeetingBar:Meeting in 3m"],
            "stale MeetingBar title-variants of the running app should be pruned, not preserved"
        )
        #expect(result.contains("com.other.app:Item-0"))
    }

    @Test("A genuinely closed app still keeps its saved position")
    func genuinelyClosedAppStillPreserved() {
        let current = ["com.a.app:Item-0", "com.c.app:Item-0"]
        let saved = ["com.a.app:Item-0", "com.b.app:Item-0", "com.c.app:Item-0"]

        let result = LayoutSolver.planSectionOrder(
            currentInSection: current,
            oldSavedForSection: saved,
            allCurrentIdentifiers: Set(current),
            allCurrentBaseIdentifiers: Set(current),
            allCurrentNamespaces: ["com.a.app", "com.c.app"] // com.b.app is NOT present
        )

        #expect(
            result == ["com.a.app:Item-0", "com.b.app:Item-0", "com.c.app:Item-0"],
            "com.b.app has quit entirely, so its saved position must be preserved"
        )
    }

    @Test("Namespace parsing stops at the first colon even when the title contains one")
    func namespaceParsedAsPrefixBeforeFirstColon() {
        let current = ["com.granola.app:Public: in 7m"]
        let saved = ["com.granola.app:Private: in 9m", "com.granola.app:Public: in 7m"]

        let result = LayoutSolver.planSectionOrder(
            currentInSection: current,
            oldSavedForSection: saved,
            allCurrentIdentifiers: Set(current),
            allCurrentBaseIdentifiers: Set(current),
            allCurrentNamespaces: ["com.granola.app"]
        )

        #expect(
            result == ["com.granola.app:Public: in 7m"],
            "the stale 9m variant should be pruned"
        )
    }

    @Test("With no namespaces provided, legacy closed-app preservation is unchanged")
    func defaultParamPreservesLegacyBehavior() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A"],
            oldSavedForSection: ["A", "leits.MeetingBar:in 5m"],
            allCurrentIdentifiers: ["A"],
            allCurrentBaseIdentifiers: ["A"]
            // allCurrentNamespaces omitted → pruning disabled
        )
        #expect(
            result.contains("leits.MeetingBar:in 5m"),
            "with no namespaces provided, legacy closed-app preservation is unchanged"
        )
    }
}
