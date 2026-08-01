//
//  ProvisionalIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Tests for the provisional-identity predicate and the UID set derived from
/// it, the pair that keeps an item whose source PID never resolved from being
/// read as a new arrival and relocated.
///
/// An item is provisionally named when its source PID is unresolved: the
/// namespace then falls back to the process that owns the window, which on
/// macOS 26 is Control Center for every hosted status item. The same item is
/// named after its real app on the next cycle that resolves it, so no
/// identifier-keyed decision (saved position, section assignment) can be
/// trusted for it.
///
/// The truth table is pinned in both directions because each half has been a
/// field bug: treating a resolved Control Center module as provisional would
/// strand Apple's own items, and treating an unresolved third-party item as
/// settled is what dragged BetterTouchTool across sections daily.
@Suite("Provisional identity")
struct ProvisionalIdentityTests {
    private func ccItem(
        title: String,
        windowID: CGWindowID,
        sourcePID: pid_t?
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: title,
                windowID: windowID
            ),
            windowID: windowID,
            sourcePID: sourcePID
        )
    }

    // MARK: - hasProvisionalIdentity

    /// The generic Control Center slot with no resolved PID: the original
    /// Little Snitch shape.
    @Test("An unresolved generic Control Center slot is provisional")
    func unresolvedGenericControlCenterSlotIsProvisional() {
        #expect(ccItem(title: "Item-0", windowID: 1, sourcePID: nil).hasProvisionalIdentity)
    }

    /// The widening this predicate exists for: a hosted item that publishes a
    /// name of its own is renamed by the same fallback, and was relocated for
    /// it in the field (com.apple.controlcenter:BetterTouchTool while
    /// unresolved, com.hegenberg.BetterTouchTool:BetterTouchTool once
    /// attributed).
    @Test("An unresolved named Control Center item is provisional")
    func unresolvedNamedControlCenterItemIsProvisional() {
        #expect(ccItem(title: "BetterTouchTool", windowID: 2, sourcePID: nil).hasProvisionalIdentity)
    }

    /// Control Center's own modules resolve to Control Center's PID through
    /// the spatial pass, so their namespace is an identity rather than a
    /// fallback and they must stay manageable.
    @Test("A resolved Control Center module is not provisional")
    func resolvedControlCenterModuleIsNotProvisional() {
        #expect(!ccItem(title: "Bluetooth", windowID: 3, sourcePID: 1117).hasProvisionalIdentity)
    }

    /// An unresolved item owned by its own app keeps a stable namespace, so
    /// the fallback never applies and it is not provisional.
    @Test("An unresolved non-Control-Center item is not provisional")
    func unresolvedNonControlCenterItemIsNotProvisional() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Item-0"),
            windowID: 4,
            sourcePID: nil
        )
        #expect(!item.hasProvisionalIdentity)
    }

    @Test("A fully resolved third-party item is not provisional")
    func resolvedThirdPartyItemIsNotProvisional() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Item-0"),
            windowID: 5,
            sourcePID: 900
        )
        #expect(!item.hasProvisionalIdentity)
    }

    // MARK: - LayoutSolver.provisionalIdentityUIDs

    /// Only the provisional items contribute, and they contribute the same
    /// uniqueIdentifier the partitioner filters on.
    @Test("Only provisional items reach the UID set")
    func onlyProvisionalItemsReachTheUIDSet() {
        let items = [
            ccItem(title: "Item-0", windowID: 10, sourcePID: nil),
            ccItem(title: "BetterTouchTool", windowID: 11, sourcePID: nil),
            ccItem(title: "Bluetooth", windowID: 12, sourcePID: 1117),
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.app", title: "Item-0"),
                windowID: 13,
                sourcePID: nil
            ),
        ]

        #expect(
            LayoutSolver.provisionalIdentityUIDs(items: items) == [
                "com.apple.controlcenter:Item-0",
                "com.apple.controlcenter:BetterTouchTool",
            ]
        )
    }

    /// The instance index is part of the identifier, so two same-titled
    /// provisional slots stay distinguishable rather than collapsing to one
    /// entry.
    @Test("The instance index is carried into the UID set")
    func instanceIndexIsCarriedIntoTheUIDSet() {
        let items = [
            ccItem(title: "Item-0", windowID: 20, sourcePID: nil),
            MenuBarItem.fixture(
                tag: MenuBarItemTag(
                    namespace: .controlCenter,
                    title: "Item-0",
                    windowID: 21,
                    instanceIndex: 1
                ),
                windowID: 21,
                sourcePID: nil
            ),
        ]

        #expect(
            LayoutSolver.provisionalIdentityUIDs(items: items) == [
                "com.apple.controlcenter:Item-0",
                "com.apple.controlcenter:Item-0:1",
            ]
        )
    }

    @Test("No items yields an empty set")
    func noItemsYieldsAnEmptySet() {
        #expect(LayoutSolver.provisionalIdentityUIDs(items: []).isEmpty)
    }

    /// A bar where nothing failed attribution produces no exclusions, so a
    /// healthy cycle is never quietly narrowed.
    @Test("A fully resolved bar yields an empty set")
    func fullyResolvedBarYieldsAnEmptySet() {
        let items = [
            ccItem(title: "Bluetooth", windowID: 30, sourcePID: 1117),
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.app", title: "Item-0"),
                windowID: 31,
                sourcePID: 900
            ),
        ]
        #expect(LayoutSolver.provisionalIdentityUIDs(items: items).isEmpty)
    }
}