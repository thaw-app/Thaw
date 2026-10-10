//
//  ControlItemPairAlwaysHiddenRecoveryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Regression locks for the always-hidden divider recovery in
/// `ControlItemPair` (#991).
///
/// On macOS 26 the parked always-hidden divider intermittently drops out of
/// the enumerated list after a restart. `alwaysHidden` then resolved nil, and
/// profile applies skipped or abandoned mid-apply, so icons never converged.
///
/// `resolveAlwaysHidden(in:authoritativeWindowID:recovery:)` recovers the
/// divider from its own authoritative window when it is absent from the list.
///
/// The unit target owns no real windows, so the recovery leaf is injected and
/// the full-init case can only confirm `alwaysHidden` stays nil here.
@MainActor
@Suite("ControlItemPair always-hidden recovery")
struct ControlItemPairAlwaysHiddenRecoveryTests {
    private let hiddenTitle = "Thaw.ControlItem.Hidden"
    private let alwaysHiddenTitle = "Thaw.ControlItem.AlwaysHidden"

    /// Fixture window IDs live in the 1_000_000+ range, so the real
    /// window-server lookup misses them.
    private let authoritativeAHWindowID: CGWindowID = 1_000_002

    private func hiddenItem(windowID: CGWindowID = 1_000_001) -> MenuBarItem {
        MenuBarItem.fixture(tag: .hiddenControlItem, windowID: windowID, title: hiddenTitle)
    }

    private func alwaysHiddenItem(windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(tag: .alwaysHiddenControlItem, windowID: windowID, title: alwaysHiddenTitle)
    }

    // MARK: resolveAlwaysHidden

    @Test("A present authoritative window is taken from the list, no recovery attempted")
    func presentAuthoritativeWindowIsTakenFromList() {
        var items = [
            hiddenItem(),
            alwaysHiddenItem(windowID: authoritativeAHWindowID),
        ]
        var recoveryCalls = 0

        let resolved = MenuBarItemManager.ControlItemPair.resolveAlwaysHidden(
            in: &items,
            authoritativeWindowID: authoritativeAHWindowID,
            recovery: { _ in
                recoveryCalls += 1
                return nil
            }
        )

        #expect(resolved?.windowID == authoritativeAHWindowID)
        #expect(recoveryCalls == 0, "a window present in the list must not hit the window server")
        #expect(items.count == 1, "the claimed divider must leave the candidate list")
        #expect(items.allSatisfy { $0.windowID != authoritativeAHWindowID })
    }

    @Test("An absent authoritative window is recovered from its own window (#991)")
    func absentAuthoritativeWindowIsRecovered() {
        // The divider is parked offscreen / filtered off the active space:
        // absent from the enumerated list, authoritative ID still in hand.
        var items = [hiddenItem()]
        let recoveredFixture = alwaysHiddenItem(windowID: authoritativeAHWindowID)

        let resolved = MenuBarItemManager.ControlItemPair.resolveAlwaysHidden(
            in: &items,
            authoritativeWindowID: authoritativeAHWindowID,
            recovery: { [recoveredFixture] windowID in
                #expect(windowID == authoritativeAHWindowID)
                return recoveredFixture
            }
        )

        #expect(resolved?.windowID == authoritativeAHWindowID)
        #expect(items.count == 1, "recovery must not consume unrelated list entries")
    }

    @Test("A known-but-absent authoritative window never adopts a lookalike from the list")
    func knownButAbsentAuthoritativeWindowDoesNotAdoptLookalike() {
        // A lookalike divider (another Thaw instance, stale cache) shares the
        // tag but not the authoritative window ID and must not be adopted.
        let lookalikeWindowID: CGWindowID = 21543
        var items = [
            hiddenItem(),
            alwaysHiddenItem(windowID: lookalikeWindowID),
        ]

        let resolved = MenuBarItemManager.ControlItemPair.resolveAlwaysHidden(
            in: &items,
            authoritativeWindowID: authoritativeAHWindowID,
            recovery: { _ in nil }
        )

        #expect(resolved == nil)
        #expect(
            items.contains { $0.windowID == lookalikeWindowID },
            "the lookalike must stay in the candidate list, unconsumed"
        )
    }

    @Test("Without an authoritative ID the remaining list is tag-matched")
    func nilAuthoritativeIDFallsBackToTagMatching() {
        var items = [
            hiddenItem(),
            alwaysHiddenItem(windowID: 366),
        ]
        var recoveryCalls = 0

        let resolved = MenuBarItemManager.ControlItemPair.resolveAlwaysHidden(
            in: &items,
            authoritativeWindowID: nil,
            recovery: { _ in
                recoveryCalls += 1
                return nil
            }
        )

        #expect(resolved?.windowID == 366)
        #expect(recoveryCalls == 0)
        #expect(items.count == 1)
    }

    @Test("A null window ID counts as no ID and tag-matches the divider")
    func zeroAuthoritativeIDFallsBackToTagMatching() {
        // A status item without a window yet converts to kCGNullWindowID,
        // which must not skip tag matching.
        var items = [
            hiddenItem(),
            alwaysHiddenItem(windowID: 366),
        ]
        var recoveryCalls = 0

        let resolved = MenuBarItemManager.ControlItemPair.resolveAlwaysHidden(
            in: &items,
            authoritativeWindowID: 0,
            recovery: { _ in
                recoveryCalls += 1
                return nil
            }
        )

        #expect(resolved?.windowID == 366)
        #expect(recoveryCalls == 0, "kCGNullWindowID must not reach the window server")
        #expect(items.count == 1)
    }

    @Test("Without an authoritative ID, our PID plus the canonical title answers a noncanonical tag")
    func sourcePIDAndTitleFallbackAnswersNoncanonicalTag() {
        // On macOS 26 the enumerated title can drift from the autosave name,
        // so tag matching fails; own process plus canonical title still identifies it.
        let lookalike = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .string("com.example.lookalike"),
                title: alwaysHiddenTitle
            ),
            windowID: 366,
            sourcePID: ProcessInfo.processInfo.processIdentifier
        )
        var items = [hiddenItem(), lookalike]

        let resolved = MenuBarItemManager.ControlItemPair.resolveAlwaysHidden(
            in: &items,
            authoritativeWindowID: nil,
            recovery: { _ in nil }
        )

        #expect(resolved?.windowID == 366)
        #expect(items.count == 1)
    }

    @Test("The full pair resolves a tag-matchable divider past a null window ID")
    func pairResolvesDividerPastNullWindowID() {
        // The always-hidden window does not exist yet, so the divider must
        // resolve from the list by tag.
        var items = [
            hiddenItem(windowID: 1_000_001),
            alwaysHiddenItem(windowID: 366),
        ]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: 1_000_001,
            alwaysHiddenControlItemWindowID: 0
        )

        #expect(pair?.hidden.windowID == 1_000_001)
        #expect(pair?.alwaysHidden?.windowID == 366)
        #expect(pair?.resolution == .identity)
    }

    // MARK: Full-init characterization of the #991 cycle

    @Test("Tag-path apply with an absent AH window stays identity-resolved and honestly nil")
    func tagPathWithAbsentAHWindowRemainsIdentityResolved() {
        // The #991 cycle: always-hidden divider absent, authoritative ID given.
        // The fixture ID cannot be confirmed here, so it stays nil at .identity.
        var items = [hiddenItem()]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: nil,
            alwaysHiddenControlItemWindowID: authoritativeAHWindowID
        )

        let pairValue = try? #require(pair)
        #expect(pairValue?.resolution == .identity)
        #expect(pairValue?.alwaysHidden == nil)
        #expect(pairValue?.canRepositionControlItems == true)
    }

    // MARK: Decision predicate

    @Test("shouldRecoverOwnControlItem fires exactly when the ID is known and absent")
    func recoveryPredicateMatchesAbsence() {
        let presentIDs: Set<CGWindowID> = [1, 2, 3]

        #expect(MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
            authoritativeWindowID: 1_000_002,
            itemWindowIDs: presentIDs
        ))
        #expect(!MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
            authoritativeWindowID: 2,
            itemWindowIDs: presentIDs
        ))
        #expect(!MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
            authoritativeWindowID: nil,
            itemWindowIDs: presentIDs
        ))
    }
}
