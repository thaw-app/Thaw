//
//  SectionGeometryGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers the two section-geometry predicates that feed
/// `LayoutSolver.shouldPersistSavedOrder`. `hiddenSectionHasRoom`
/// additionally gates `applySavedLayout`'s bulk dispatch (#868).
///
/// Both exist for the same reason: `CacheContext.findSection` degrades
/// rather than fails when the dividers cannot describe the sections, and
/// `saveSectionOrder` then writes that degraded reading down as the user's
/// layout. Each predicate also has to stay quiet for the users whose
/// layouts legitimately look like the fault case, which is the half that
/// keeps the fix from becoming a bug of its own.
@Suite("Section geometry persist gate")
struct SectionGeometryGateTests {
    // MARK: - isAlwaysHiddenSectionResolved (#849)

    @Test("A present divider with the section on is resolved")
    func presentDividerIsResolved() {
        #expect(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: true,
            isAlwaysHiddenSectionEnabled: true
        ))
    }

    @Test("A missing divider with the section on is unresolved")
    func missingDividerWithEnabledSectionIsUnresolved() {
        // The #849 state: the section is on, so its items are real, but the
        // boundary that identifies them is missing this cycle.
        #expect(!LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: false,
            isAlwaysHiddenSectionEnabled: true
        ))
    }

    @Test(
        "A disabled always-hidden section is always resolved",
        arguments: [true, false]
    )
    func disabledSectionIsResolved(hasDivider: Bool) {
        // Users who never enabled the section have no divider by design.
        // Treating that as unresolved would block their layout from ever
        // being saved — trading #849 for a worse bug.
        #expect(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: hasDivider,
            isAlwaysHiddenSectionEnabled: false
        ))
    }

    // MARK: - hiddenSectionHasRoom (#795)

    @Test("A healthy gap between the dividers has room")
    func healthyGapHasRoom() {
        // Undocked geometry from the report: AlwaysHidden ends at -4612,
        // Hidden starts at -3935, so the hidden section spans 677pt.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -3935,
            alwaysHiddenControlItemMaxX: -4612,
            savedHiddenItemCount: 41
        ))
    }

    @Test("Dividers collapsed onto the same coordinate have no room")
    func collapsedGapHasNoRoom() {
        // The docked-topology fault: both control items resized to 5016 and
        // landed exactly 5016 apart, so AlwaysHidden.maxX == Hidden.minX and
        // the hidden section is a zero-width span. findSection cannot
        // satisfy `minX >= ah.maxX && maxX <= hidden.minX` at one
        // coordinate, so every on-screen item resolves .visible instead.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4271,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 41
        ))
    }

    @Test("Dividers in the wrong order have no room")
    func invertedDividersHaveNoRoom() {
        // A negative span is at least as broken as a zero one.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4500,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 41
        ))
    }

    @Test("A saved layout with no hidden items is never blocked")
    func emptyHiddenSectionIsNotBlocked() {
        // A user who keeps nothing in the hidden section has no reason for
        // the dividers to sit apart. Blocking here would stop their layout
        // being saved at all, which is the false positive this predicate
        // has to avoid.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4271,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 0
        ))
    }

    @Test("Without an always-hidden divider there is no span to close")
    func absentAlwaysHiddenDividerHasRoom() {
        // Everything left of the hidden divider is .hidden by definition,
        // so there is no second boundary that could collapse against it.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4271,
            alwaysHiddenControlItemMaxX: nil,
            savedHiddenItemCount: 41
        ))
    }

    @Test("A sub-point gap still counts as room")
    func subPointGapHasRoom() {
        // The predicate tests for a closed span, not for a span wide enough
        // to hold anything. Anything above zero is left to the layout
        // engine rather than second-guessed here.
        #expect(LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -4270.5,
            alwaysHiddenControlItemMaxX: -4271,
            savedHiddenItemCount: 41
        ))
    }

    @Test("The apply-path bypass geometry has no room")
    func applyPathBypassGeometryHasNoRoom() {
        // The #868 field incident: dividers collapsed at -5743 with 46
        // items saved hidden. saveSectionOrder refused this geometry, but
        // applySavedLayout read the same collapse as an 11-item section
        // mismatch and dispatched 21 synthetic drags — which separated the
        // dividers, un-tripping the save gate, so the next cycle persisted
        // the misclassification. The apply path now consults this predicate
        // before dispatching, so both writers refuse the same reading.
        #expect(!LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: -5743,
            alwaysHiddenControlItemMaxX: -5743,
            savedHiddenItemCount: 46
        ))
    }

    // MARK: - Gate composition

    @Test("A collapsed hidden section blocks the save on its own")
    func collapsedGeometryBlocksTheGate() {
        // Every other input is clear, which is the situation the reporter
        // was in: resolution had recovered, so the sourcePID guard passed
        // and the collapsed reading reached disk.
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hiddenSectionHasRoom: false
            )
        ))
    }

    @Test("Healthy geometry with everything else clear persists")
    func healthyGeometryPersists() {
        #expect(LayoutSolver.shouldPersistSavedOrder(.init()))
    }
}
