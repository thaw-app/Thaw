//
//  SectionTransitionDestinationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Section transition destination")
struct SectionTransitionDestinationTests {
    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        ItemsFixture.item(title, x: x, windowID: UInt32(x) + 1)
    }

    private let hidden = SectionTransitionDestinationTests.item("Hidden divider", x: 100)
    private let alwaysHidden = SectionTransitionDestinationTests.item("Always hidden divider", x: 200)
    private let predecessor = SectionTransitionDestinationTests.item("Predecessor", x: 300)

    private func destination(
        _ section: MenuBarSection.Name,
        after predecessor: MenuBarItem? = nil,
        alwaysHiddenDivider: MenuBarItem?,
        enabled: Bool
    ) -> MoveDestination {
        SectionTransitionDestination.destination(
            for: section,
            after: predecessor,
            hiddenDivider: hidden,
            alwaysHiddenDivider: alwaysHiddenDivider,
            alwaysHiddenEnabled: enabled
        )
    }

    // MARK: Predecessor

    @Test("A predecessor wins for every section and every divider state")
    func predecessorWins() {
        for section in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
            for divider in [alwaysHidden, nil] {
                for enabled in [true, false] {
                    #expect(
                        destination(section, after: predecessor, alwaysHiddenDivider: divider, enabled: enabled)
                            == .rightOfItem(predecessor)
                    )
                }
            }
        }
    }

    // MARK: Band boundary

    @Test("Visible joins to the right of the hidden divider whatever else is set")
    func visibleBoundary() {
        for divider in [alwaysHidden, nil] {
            for enabled in [true, false] {
                #expect(
                    destination(.visible, alwaysHiddenDivider: divider, enabled: enabled)
                        == .rightOfItem(hidden)
                )
            }
        }
    }

    @Test("Hidden joins to the right of the always-hidden divider when that section is on and its divider exists")
    func hiddenWithAlwaysHidden() {
        #expect(
            destination(.hidden, alwaysHiddenDivider: alwaysHidden, enabled: true)
                == .rightOfItem(alwaysHidden)
        )
    }

    @Test("Hidden joins to the left of the hidden divider when always-hidden is off")
    func hiddenWithAlwaysHiddenDisabled() {
        #expect(
            destination(.hidden, alwaysHiddenDivider: alwaysHidden, enabled: false)
                == .leftOfItem(hidden)
        )
    }

    @Test("Hidden joins to the left of the hidden divider when the always-hidden divider is missing")
    func hiddenWithoutAlwaysHiddenDivider() {
        for enabled in [true, false] {
            #expect(
                destination(.hidden, alwaysHiddenDivider: nil, enabled: enabled)
                    == .leftOfItem(hidden)
            )
        }
    }

    @Test("Always-hidden joins to the left of its divider when it exists, ignoring the enabled flag")
    func alwaysHiddenWithDivider() {
        for enabled in [true, false] {
            #expect(
                destination(.alwaysHidden, alwaysHiddenDivider: alwaysHidden, enabled: enabled)
                    == .leftOfItem(alwaysHidden)
            )
        }
    }

    @Test("Always-hidden falls back to the left of the hidden divider when its divider is missing")
    func alwaysHiddenWithoutDivider() {
        for enabled in [true, false] {
            #expect(
                destination(.alwaysHidden, alwaysHiddenDivider: nil, enabled: enabled)
                    == .leftOfItem(hidden)
            )
        }
    }
}
