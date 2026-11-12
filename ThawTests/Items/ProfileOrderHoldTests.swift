//
//  ProfileOrderHoldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins how long an applied profile's Visible order outlasts the bar's record of a partial apply.
@MainActor
@Suite("Profile order hold")
struct ProfileOrderHoldTests {
    private static let start = ContinuousClock.now
    /// A pass saw the profile's members a second after it was applied.
    private static let seen = start + .seconds(1)

    // MARK: isOver

    @Test("The hold lasts while a left-out member is watched for")
    func holdsWhileMembersAreLeftOut() {
        let hold = ProfileOrderHold(startedAt: Self.start)

        #expect(!hold.isOver(membersSeenAt: Self.seen, membersStillLeftOut: true, userArrangedAt: nil, now: Self.start + .seconds(30)))
    }

    @Test("A pass that read nothing, or saw the members only before the profile was applied, doesn't end it")
    func emptyReadKeepsTheHold() {
        let hold = ProfileOrderHold(startedAt: Self.start)

        #expect(!hold.isOver(membersSeenAt: nil, membersStillLeftOut: false, userArrangedAt: nil, now: Self.start + .seconds(5)))
        #expect(!hold.isOver(membersSeenAt: Self.start - .seconds(1), membersStillLeftOut: false, userArrangedAt: nil, now: Self.start + .seconds(5)))
    }

    @Test("The hold ends once a pass saw the members and none is left out")
    func endsWhenNothingIsLeftOut() {
        #expect(ProfileOrderHold(startedAt: Self.start).isOver(membersSeenAt: Self.seen, membersStillLeftOut: false, userArrangedAt: nil, now: Self.start))
    }

    @Test("A drag since the profile was applied ends the hold; one before it doesn't")
    func userArrangementEndsTheHold() {
        let hold = ProfileOrderHold(startedAt: Self.start)

        #expect(hold.isOver(membersSeenAt: Self.seen, membersStillLeftOut: true, userArrangedAt: Self.start + .seconds(5), now: Self.start + .seconds(6)))
        #expect(!hold.isOver(membersSeenAt: Self.seen, membersStillLeftOut: true, userArrangedAt: Self.start - .seconds(5), now: Self.start + .seconds(6)))
    }

    @Test("A member that never appears can't hold the record past the limit")
    func limitEndsTheHold() {
        let hold = ProfileOrderHold(startedAt: Self.start)

        #expect(!hold.isOver(membersSeenAt: Self.seen, membersStillLeftOut: true, userArrangedAt: nil, now: Self.start + ProfileOrderHold.limit - .seconds(1)))
        #expect(hold.isOver(membersSeenAt: Self.seen, membersStillLeftOut: true, userArrangedAt: nil, now: Self.start + ProfileOrderHold.limit))
    }

    // MARK: The bar's record

    private static let visibleKey = MenuBarSectionName.visible.rawValue
    private static let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982)]

    private static func item(_ app: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(app), title: "Item-0", instanceIndex: 0),
            windowID: CGWindowID(x),
            ownerPID: pid_t(x),
            sourcePID: pid_t(x),
            bounds: CGRect(x: x, y: 4, width: 24, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    /// Wi-Fi drawn first, as a profile applied without SoundSource left it.
    private static let partialBar = [item("com.apple.wifi", x: 960), item("com.rogueamoeba.soundsource", x: 1000)]
    /// The profile's order: SoundSource before Wi-Fi.
    private static let profileOrder = partialBar.reversed().map(\.uniqueIdentifier)

    private static func mirror(_ manager: MenuBarItemManager, placedByUser: Bool = false) {
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = partialBar
        manager.mirrorSavedSectionOrderIfSettled(from: cache, placedByUser: placedByUser, displays: displays)
    }

    private static func withSavedOrderDefaults(_ body: () -> Void) {
        let key = "MenuBarItemManager.savedSectionOrder"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        body()
    }

    @Test("While the hold lasts, the record keeps the profile's Visible order over the bar's")
    func recordKeepsTheProfileOrder() {
        Self.withSavedOrderDefaults {
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = [Self.visibleKey: Self.profileOrder]
            manager.profileOrderHold = ProfileOrderHold(startedAt: .now)
            manager.missingRepublishMemo.noteMissing(["com.apple.TimeMachine:Item-0"])

            Self.mirror(manager)

            #expect(manager.savedSectionOrder[Self.visibleKey] == Self.profileOrder)
            #expect(manager.profileOrderHold != nil)
        }
    }

    @Test("Once a pass saw the members and none is left out, the hold ends and the record follows the bar")
    func recordFollowsTheBarAfterTheHold() {
        Self.withSavedOrderDefaults {
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = [Self.visibleKey: Self.profileOrder]
            manager.profileOrderHold = ProfileOrderHold(startedAt: .now)
            manager.missingRepublishMemo.noteArrived(Self.profileOrder)

            Self.mirror(manager)

            #expect(manager.savedSectionOrder[Self.visibleKey] == Self.partialBar.map(\.uniqueIdentifier))
            #expect(manager.profileOrderHold == nil)
        }
    }

    @Test("A left-out member moved out of Visible since doesn't keep the hold")
    func memberMovedOutOfVisibleEndsTheHold() {
        Self.withSavedOrderDefaults {
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = [Self.visibleKey: Self.profileOrder]
            manager.profileOrderHold = ProfileOrderHold(startedAt: .now)
            manager.missingRepublishMemo.noteMissing(["com.example.movedToHidden:Item-0"])
            manager.missingRepublishMemo.noteArrived(Self.profileOrder)

            Self.mirror(manager)

            #expect(manager.profileOrderHold == nil)
            #expect(manager.savedSectionOrder[Self.visibleKey] == Self.partialBar.map(\.uniqueIdentifier))
        }
    }

    @Test("An arrival restore writes the order saved when it runs, and none while a layout is applied")
    func arrivalRestoreReadsTheOrderWhenItRuns() {
        #expect(ProfileOrderHold.arrivalRestoreOrder(saved: Self.profileOrder, isApplyingLayout: false) == Self.profileOrder)
        #expect(ProfileOrderHold.arrivalRestoreOrder(saved: Self.profileOrder, isApplyingLayout: true) == nil)
        #expect(ProfileOrderHold.arrivalRestoreOrder(saved: ["com.example.only:Item-0"], isApplyingLayout: false) == nil)
        #expect(ProfileOrderHold.arrivalRestoreOrder(saved: nil, isApplyingLayout: false) == nil)
    }

    @Test("A pass that read nothing leaves no one out, but the record still keeps the profile's order")
    func emptyReadKeepsTheRecord() {
        Self.withSavedOrderDefaults {
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = [Self.visibleKey: Self.profileOrder]
            manager.profileOrderHold = ProfileOrderHold(startedAt: .now)
            manager.missingRepublishMemo.noteArrived([String]())

            Self.mirror(manager)

            #expect(manager.savedSectionOrder[Self.visibleKey] == Self.profileOrder)
            #expect(manager.profileOrderHold != nil)
        }
    }

    @Test("An item the user placed ends the hold, and the record follows the bar")
    func userPlacementEndsTheHold() {
        Self.withSavedOrderDefaults {
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = [Self.visibleKey: Self.profileOrder]
            manager.profileOrderHold = ProfileOrderHold(startedAt: .now)
            manager.missingRepublishMemo.noteMissing(["com.apple.TimeMachine:Item-0"])

            Self.mirror(manager, placedByUser: true)

            #expect(manager.savedSectionOrder[Self.visibleKey] == Self.partialBar.map(\.uniqueIdentifier))
            #expect(manager.profileOrderHold == nil)
        }
    }
}
