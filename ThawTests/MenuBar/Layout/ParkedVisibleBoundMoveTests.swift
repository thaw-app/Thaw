//
//  ParkedVisibleBoundMoveTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins ``MenuBarItemManager/MoveDestination/wouldLandOffScreen(screenFrames:)``
/// and the desired-section rule the profile apply's LCS pass pairs it with.
///
/// After a restart on three displays the hidden divider sat parked at -2422
/// with two items stranded behind it. The LCS pass then anchored visible-bound
/// moves on parked items, each chaining off the last, and the bar went from
/// visible=12/hidden=13 to visible=1/hidden=19 (#1027).
///
/// A visible-bound move onto a parked anchor is refused; a concealment move is
/// not, because parking is how concealment works.
@Suite("Parked visible-bound move exclusion")
struct ParkedVisibleBoundMoveTests {
    private static let display = CGRect(x: 0, y: 0, width: 1728, height: 1120)
    private static let screenFrames = [display]

    /// Items behind a collapsed hidden section sit thousands of points left of the display.
    private static let parkedBounds = CGRect(x: -2422, y: 0, width: 24, height: 22)
    private static let onScreenBounds = CGRect(x: 800, y: 0, width: 24, height: 22)

    private static func item(
        _ title: String,
        at bounds: CGRect,
        windowID: CGWindowID = 100
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.\(title)", title: title),
            windowID: windowID,
            bounds: bounds
        )
    }

    // MARK: - wouldLandOffScreen

    @Test("A destination anchored on an on-screen item lands on screen")
    func onScreenAnchorLands() {
        let dest = MenuBarItemManager.MoveDestination.rightOfItem(
            Self.item("tgpro", at: Self.onScreenBounds)
        )
        #expect(!dest.wouldLandOffScreen(screenFrames: Self.screenFrames))
    }

    @Test("A destination anchored on a parked item lands off screen")
    func parkedAnchorDoesNotLand() {
        let dest = MenuBarItemManager.MoveDestination.leftOfItem(
            Self.item("tgpro", at: Self.parkedBounds)
        )
        #expect(dest.wouldLandOffScreen(screenFrames: Self.screenFrames))
    }

    @Test("Both sides of a parked anchor land off screen")
    func bothSidesOfParkedAnchorDoNotLand() {
        let anchor = Self.item("soundsource-Input", at: Self.parkedBounds)
        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(anchor)
                .wouldLandOffScreen(screenFrames: Self.screenFrames)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(anchor)
                .wouldLandOffScreen(screenFrames: Self.screenFrames)
        )
    }

    @Test("A parked divider used as a boundary destination lands off screen")
    func parkedDividerBoundaryDoesNotLand() {
        let controlItems = MenuBarItemManager.ControlItemPair.fixture(hiddenAt: Self.parkedBounds)
        let dest = LayoutReconciler.boundaryDestination(for: .hidden, controlItems: controlItems)
        #expect(dest.wouldLandOffScreen(screenFrames: Self.screenFrames))
    }

    @Test("An anchor on a secondary display lands on screen")
    func secondaryDisplayAnchorLands() {
        let secondary = CGRect(x: -1728, y: 0, width: 1728, height: 1120)
        let dest = MenuBarItemManager.MoveDestination.rightOfItem(
            Self.item("tgpro", at: CGRect(x: -900, y: 0, width: 24, height: 22))
        )
        #expect(!dest.wouldLandOffScreen(screenFrames: [Self.display, secondary]))
        // Same anchor, without the display that contains it.
        #expect(dest.wouldLandOffScreen(screenFrames: Self.screenFrames))
    }

    // MARK: - The desired-section rule

    /// Mirrors the LCS gate: skip only a visible-bound move whose destination is off screen.
    private static func wouldSkip(
        desiredSection: MenuBarSection.Name,
        destination: MenuBarItemManager.MoveDestination
    ) -> Bool {
        desiredSection == .visible
            && destination.wouldLandOffScreen(screenFrames: screenFrames)
    }

    @Test("A visible-bound move onto a parked anchor is skipped")
    func visibleBoundMoveOntoParkedAnchorIsSkipped() {
        let dest = MenuBarItemManager.MoveDestination.leftOfItem(
            Self.item("tgpro", at: Self.parkedBounds)
        )
        #expect(Self.wouldSkip(desiredSection: .visible, destination: dest))
    }

    @Test("A visible-bound move onto an on-screen anchor runs")
    func visibleBoundMoveOntoOnScreenAnchorRuns() {
        let dest = MenuBarItemManager.MoveDestination.leftOfItem(
            Self.item("tgpro", at: Self.onScreenBounds)
        )
        #expect(!Self.wouldSkip(desiredSection: .visible, destination: dest))
    }

    @Test(
        "A concealment move onto a parked anchor runs",
        arguments: [MenuBarSection.Name.hidden, .alwaysHidden]
    )
    func concealmentMoveOntoParkedAnchorRuns(section: MenuBarSection.Name) {
        // App-Cleaner onto a parked H_ctrl and the always-hidden trio onto a parked
        // AH_ctrl were correct in the log and are still permitted.
        let controlItems = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: Self.parkedBounds,
            alwaysHiddenAt: Self.parkedBounds
        )
        let dest = LayoutReconciler.boundaryDestination(for: section, controlItems: controlItems)
        #expect(dest.wouldLandOffScreen(screenFrames: Self.screenFrames))
        #expect(!Self.wouldSkip(desiredSection: section, destination: dest))
    }

    /// The reporter's own move sequence, replayed against the gate.
    @Test("The #1027 sequence skips the six stranding moves and keeps the rest")
    func reporterSequenceIsGatedExactly() {
        // (uid, desired section, anchor parked?) in log order. The visible-bound
        // anchors were parked, either already stranded or stranded by the move before.
        let sequence: [(uid: String, section: MenuBarSection.Name, anchorParked: Bool)] = [
            ("ru.yandex.desktop.disk2:Item-0", .alwaysHidden, true),
            ("com.nextcloud.desktopclient:Item-0", .alwaysHidden, true),
            ("com.steipete.codexbar:codexbar-codex", .visible, true),
            ("com.steipete.codexbar:codexbar-claude", .visible, true),
            ("com.apphousekitchen.aldente-pro:Item-0", .visible, true),
            ("org.p0deje.Maccy:Item-0", .visible, true),
            ("com.apple.TextInputMenuAgent:Item-0", .visible, true),
            ("com.nektony.App-Cleaner-SIII-UIHelper:Item-0", .hidden, true),
            ("com.apple.KerberosMenuExtra:Item-0", .hidden, true),
            ("com.apple.controlcenter:Battery", .hidden, true),
            ("com.electron.dockerdesktop:Item-0", .hidden, true),
            ("com.proxyman.NSProxy:Item-0", .hidden, true),
            ("com.paloaltonetworks.GlobalProtect.client:Item-0", .hidden, true),
            ("com.kaspersky.kav_agent:Item-0", .hidden, true),
            ("com.steipete.codexbar:codexbar-opencode", .alwaysHidden, true),
            ("com.steipete.codexbar:codexbar-cursor", .alwaysHidden, true),
            ("com.shortcutlabs.FlicMac:Item-0", .alwaysHidden, true),
            ("com.stonerl.Thaw:Thaw.ControlItem.Visible", .visible, true),
        ]

        let skipped = sequence.filter { entry in
            let anchor = Self.item(
                entry.uid,
                at: entry.anchorParked ? Self.parkedBounds : Self.onScreenBounds
            )
            return Self.wouldSkip(
                desiredSection: entry.section,
                destination: .leftOfItem(anchor)
            )
        }.map(\.uid)

        #expect(skipped == [
            "com.steipete.codexbar:codexbar-codex",
            "com.steipete.codexbar:codexbar-claude",
            "com.apphousekitchen.aldente-pro:Item-0",
            "org.p0deje.Maccy:Item-0",
            "com.apple.TextInputMenuAgent:Item-0",
            "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        ])
        #expect(skipped.count == 6)
        #expect(sequence.count - skipped.count == 12)
    }
}
