//
//  MoveFailureAttributionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// How a move's failure is attributed once it leaves the engine: which
/// failures the ledger may file as an owner that ignores events and how long
/// a refusal by macOS keeps an item's saved slot.
@MainActor
@Suite("Move failure attribution")
struct MoveFailureAttributionTests {
    typealias EventError = MenuBarItemManager.EventError

    private let item = MenuBarItem.fixture(
        tag: .appItem(bundleID: "com.example.IconSwitcher", title: "Item-0"),
        windowID: 2314
    )

    // MARK: Ledger

    /// The 13:00:51 mark: a timeout on a Control-Center-hosted item during a
    /// reverting episode, filed for fourteen days against an owner that had
    /// answered every press.
    @Test("A timeout on a Control-Center-hosted item is not the owner's silence")
    func hostedTimeoutIsNotFiledAgainstOwner() {
        let kind = MenuBarItemManager.ledgerFailureKind(
            for: .itemResponseTimeout(item),
            ownerIsControlCenter: true,
            hasProvisionalIdentity: false
        )
        #expect(kind == .other)
    }

    /// The case the mark exists for: an app that owns its own window and
    /// never acknowledges the events posted to it.
    @Test("A timeout on an app-owned item is the owner's silence")
    func appOwnedTimeoutIsFiledAgainstOwner() {
        let kind = MenuBarItemManager.ledgerFailureKind(
            for: .eventOperationTimeout(item),
            ownerIsControlCenter: false,
            hasProvisionalIdentity: false
        )
        #expect(kind == .unresponsiveOwner)
    }

    @Test("A hung owner is filed only when it is not Control Center")
    func hungOwnerAttribution() {
        #expect(
            MenuBarItemManager.ledgerFailureKind(
                for: .ownerUnresponsive(item),
                ownerIsControlCenter: false,
                hasProvisionalIdentity: false
            ) == .unresponsiveOwner
        )
        #expect(
            MenuBarItemManager.ledgerFailureKind(
                for: .ownerUnresponsive(item),
                ownerIsControlCenter: true,
                hasProvisionalIdentity: false
            ) == .other
        )
    }

    @Test("A provisional identity is never marked")
    func provisionalIdentityIsNeverMarked() {
        let kind = MenuBarItemManager.ledgerFailureKind(
            for: .itemResponseTimeout(item),
            ownerIsControlCenter: false,
            hasProvisionalIdentity: true
        )
        #expect(kind == .other)
    }

    @Test("Failures that are not silence never earn a mark", arguments: [
        EventError.dropReverted(.fixture(tag: .appItem(bundleID: "a", title: "b"), windowID: 1)),
        .staleDestination(.fixture(tag: .appItem(bundleID: "a", title: "b"), windowID: 1)),
        .moveTimedOut(.fixture(tag: .appItem(bundleID: "a", title: "b"), windowID: 1)),
        .moveEngineBusy(.fixture(tag: .appItem(bundleID: "a", title: "b"), windowID: 1)),
        .missingItemBounds(.fixture(tag: .appItem(bundleID: "a", title: "b"), windowID: 1)),
        .cannotComplete,
    ])
    func nonSilenceIsNeverMarked(error: EventError) {
        let kind = MenuBarItemManager.ledgerFailureKind(
            for: error,
            ownerIsControlCenter: false,
            hasProvisionalIdentity: false
        )
        #expect(kind == .other)
    }

    // MARK: Refused moves

    @Test("A refusal stands for its lifetime and then lapses")
    func refusalLifetime() {
        let recordedAt = ContinuousClock.Instant.now
        #expect(MenuBarItemManager.refusedMoveIsCurrent(recordedAt: recordedAt, now: recordedAt))
        #expect(
            MenuBarItemManager.refusedMoveIsCurrent(
                recordedAt: recordedAt,
                now: recordedAt.advanced(by: .seconds(9 * 60))
            )
        )
        #expect(
            !MenuBarItemManager.refusedMoveIsCurrent(
                recordedAt: recordedAt,
                now: recordedAt.advanced(by: MenuBarItemManager.refusedMoveLifetime)
            )
        )
    }

    @Test("A refusal record is kept by the manager until it lapses")
    func refusalRecordLifecycle() {
        let manager = MenuBarItemManager()
        let now = ContinuousClock.Instant.now
        manager.noteRefusedMove(of: item)
        #expect(manager.refusedMoveIdentifiers(now: now) == [item.uniqueIdentifier])
        #expect(manager.refusedMoveIdentifiers(now: now.advanced(by: .seconds(11 * 60))).isEmpty)

        manager.noteRefusedMove(of: item)
        manager.clearRefusedMove(of: item)
        #expect(manager.refusedMoveIdentifiers(now: now).isEmpty)
    }
}
