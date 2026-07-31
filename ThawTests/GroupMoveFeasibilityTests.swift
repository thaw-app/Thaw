//
//  GroupMoveFeasibilityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
@testable import Thaw
import XCTest

/// The single authority for "can this whole group move to that section".
///
/// A group is indivisible, so this must be all-or-nothing and must name what
/// blocked it — a refused drag otherwise just springs back and reads as the app
/// ignoring the gesture.
@MainActor
final class GroupMoveFeasibilityTests: XCTestCase {
    private func item(_ bundle: String, _ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundle, title: title),
            windowID: windowID,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 22)
        )
    }

    private func feasibility(
        members: [MenuBarItem],
        expected: Int? = nil,
        to section: MenuBarSection.Name = .hidden,
        experimentalSystemItemHiding: Bool = false,
        isHidingAvailable: Bool = true
    ) -> GroupMoveFeasibility {
        MenuBarSectionController.groupMoveFeasibility(
            members: members,
            expectedMemberCount: expected ?? members.count,
            to: section,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            isHidingAvailable: isHidingAvailable
        )
    }

    // MARK: - Allowed

    func testOrdinaryThirdPartyGroupMayMoveToHidden() {
        let members = [item("com.a", "One", windowID: 1), item("com.b", "Two", windowID: 2)]
        XCTAssertTrue(feasibility(members: members).isAllowed)
    }

    func testMovingToVisibleIsAlwaysAllowed() {
        // Visible needs no hiding capability, so even a non-hideable member and
        // an unavailable backend must not block a move back to Visible.
        let members = [item("com.a", "One", windowID: 1), item("com.b", "Two", windowID: 2)]
        XCTAssertTrue(
            feasibility(members: members, to: .visible, isHidingAvailable: false).isAllowed
        )
    }

    // MARK: - Refusals

    /// The whole point: one blocked member refuses the entire move rather than
    /// letting the rest go and splitting the group.
    func testOneProtectedMemberRefusesTheWholeGroup() {
        let members = [
            item("com.a", "One", windowID: 1),
            MenuBarItem.fixture(tag: .visibleControlItem, windowID: 9),
        ]

        guard case let .refused(reason) = feasibility(members: members) else {
            return XCTFail("expected a refusal")
        }
        guard case let .protectedMember(blocked) = reason else {
            return XCTFail("expected .protectedMember, got \(reason)")
        }
        XCTAssertEqual(blocked.tag, .visibleControlItem)
    }

    func testUnavailableHidingRefusesAMoveOutOfVisible() {
        let members = [item("com.a", "One", windowID: 1), item("com.b", "Two", windowID: 2)]

        guard case let .refused(reason) = feasibility(members: members, isHidingAvailable: false) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(reason, .hidingUnavailable)
    }

    /// Finding only part of a group must refuse. Moving the part we found is
    /// exactly the split the invariant exists to prevent.
    func testFewerLiveMembersThanExpectedRefuses() {
        let members = [item("com.a", "One", windowID: 1)]

        guard case let .refused(reason) = feasibility(members: members, expected: 3) else {
            return XCTFail("expected a refusal")
        }
        guard case let .unresolvedMembers(missing) = reason else {
            return XCTFail("expected .unresolvedMembers, got \(reason)")
        }
        XCTAssertEqual(missing, 2)
    }

    // MARK: - Refusal copy

    /// The message has to name the app. `com.bjango.istatmenus.status:Battery`
    /// is not something to show a user.
    func testRefusalNamesTheAppNotTheIdentifier() {
        let blocked = item("com.example.tool", "Widget", windowID: 4)
        let reason = GroupMoveRefusal.hidingUnsupported(item: blocked)

        XCTAssertTrue(
            reason.localizedReason.contains(blocked.displayName),
            "expected the display name in: \(reason.localizedReason)"
        )
        XCTAssertFalse(reason.localizedReason.contains("com.example.tool:"))
    }

    func testRefusalExposesTheBlockingItem() {
        let blocked = item("com.example.tool", "Widget", windowID: 4)

        XCTAssertEqual(GroupMoveRefusal.notHideable(item: blocked).blockingItem?.tag, blocked.tag)
        XCTAssertNil(GroupMoveRefusal.hidingUnavailable.blockingItem)
        XCTAssertNil(GroupMoveRefusal.unresolvedMembers(missingCount: 1).blockingItem)
    }

    func testBlockedGroupMoveMessageStatesNothingMoved() {
        let blocked = item("com.example.tool", "Widget", windowID: 4)
        let refusal = LayoutBarFeedbackCenter.blockedGroupMove(
            groupName: "Work",
            section: .hidden,
            refusal: .hidingUnsupported(item: blocked)
        )

        XCTAssertTrue(refusal.title.contains("Work"))
        XCTAssertTrue(refusal.message.contains(blocked.displayName))
        // The visible result is a snap-back; saying so is what makes it read as
        // a decision rather than a dropped gesture.
        XCTAssertTrue(refusal.message.lowercased().contains("no items were moved"))
    }

    func testRegatherMessageNamesTheGroupAndSection() {
        let refusal = LayoutBarFeedbackCenter.groupRegatherIncomplete(
            groupName: "Work",
            section: .hidden
        )

        XCTAssertTrue(refusal.title.contains("Work"))
        XCTAssertTrue(refusal.message.contains(MenuBarSection.Name.hidden.displayString))
    }
}
