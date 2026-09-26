//
//  ProvisionalIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Keeps an item whose source PID never resolved from being treated as a new
/// arrival and relocated.
///
/// Unresolved, the namespace falls back to the window owner, which on macOS 26
/// is Control Center for every hosted item; the next cycle renames it, so no
/// identifier-keyed decision can be trusted for it.
///
/// Both directions have been field bugs: a resolved Control Center module
/// marked provisional strands Apple's items, and an unresolved third-party
/// item treated as settled dragged BetterTouchTool across sections daily.
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

    /// The generic Control Center slot with no resolved PID, the original Little Snitch shape.
    @Test("An unresolved generic Control Center slot is provisional")
    func unresolvedGenericControlCenterSlotIsProvisional() {
        #expect(ccItem(title: "Item-0", windowID: 1, sourcePID: nil).hasProvisionalIdentity)
    }

    /// A hosted item with its own name is renamed by the same fallback
    /// (com.apple.controlcenter:BetterTouchTool until attributed) and was relocated for it.
    @Test("An unresolved named Control Center item is provisional")
    func unresolvedNamedControlCenterItemIsProvisional() {
        #expect(ccItem(title: "BetterTouchTool", windowID: 2, sourcePID: nil).hasProvisionalIdentity)
    }

    /// Control Center's modules resolve to its PID in the spatial pass, so their
    /// namespace is real and they must stay manageable.
    @Test("A resolved Control Center module is not provisional")
    func resolvedControlCenterModuleIsNotProvisional() {
        #expect(!ccItem(title: "Bluetooth", windowID: 3, sourcePID: 1117).hasProvisionalIdentity)
    }

    /// An app-owned item keeps a stable namespace, so the fallback never applies.
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

    /// Provisional items contribute the same uniqueIdentifier the partitioner filters on.
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

    /// The instance index keeps two same-titled provisional slots distinct.
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

    /// A healthy cycle is never quietly narrowed.
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