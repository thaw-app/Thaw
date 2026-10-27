//
//  MoveTargetingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw

@Suite("Move targeting resolves anchors against the live bar")
struct MoveTargetingTests {
    private static func item(
        _ title: String,
        windowID: CGWindowID,
        x: CGFloat = 0,
        pid: pid_t = 999_970,
        namespace: MenuBarItemTag.Namespace = .string("com.example.targeting")
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid,
            sourcePID: pid,
            bounds: CGRect(x: x, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private let mover = item("Mover", windowID: 1)

    @Test("An anchor present on the bar is rewritten to its live window")
    func liveAnchorReplacesStale() {
        let stale = Self.item("Anchor", windowID: 10)
        let live = Self.item("Anchor", windowID: 11, x: 300)

        let resolved = MoveTargeting.resolvedDestination(
            for: .rightOfItem(stale),
            fallbacks: [],
            item: mover,
            among: [mover, live]
        )

        #expect(resolved == .rightOfItem(live))
    }

    @Test("An unchanged anchor resolves to itself")
    func unchangedAnchor() {
        let anchor = Self.item("Anchor", windowID: 10)
        let resolved = MoveTargeting.resolvedDestination(
            for: .leftOfItem(anchor),
            fallbacks: [],
            item: mover,
            among: [anchor]
        )
        #expect(resolved == .leftOfItem(anchor))
    }

    @Test("A vanished anchor falls back to the first alternate present")
    func vanishedAnchorUsesAlternate() {
        let gone = Self.item("Gone", windowID: 10)
        let missing = Self.item("Missing", windowID: 12)
        let alternate = Self.item("Alternate", windowID: 13)

        let resolved = MoveTargeting.resolvedDestination(
            for: .leftOfItem(gone),
            fallbacks: [.rightOfItem(missing), .leftOfItem(alternate)],
            item: mover,
            among: [mover, alternate]
        )

        #expect(resolved == .leftOfItem(alternate))
    }

    @Test("An anchor from another process with the same title does not count")
    func otherProcessIsNotTheAnchor() {
        let anchor = Self.item("Anchor", windowID: 10, pid: 1)
        let impostor = Self.item("Anchor", windowID: 11, pid: 2)

        let resolved = MoveTargeting.resolvedDestination(
            for: .leftOfItem(anchor),
            fallbacks: [],
            item: mover,
            among: [impostor]
        )

        #expect(resolved == nil)
    }

    @Test("A crossing write targets the divider side the destination names")
    func crossingSide() {
        let anchor = Self.item("Divider", windowID: 20)
        #expect(MoveTargeting.crossingSide(of: .leftOfItem(anchor)) == .leftOfDivider)
        #expect(MoveTargeting.crossingSide(of: .rightOfItem(anchor)) == .rightOfDivider)
    }

    @Test("Only com.apple identifiers name pinned system items")
    func pinnedSystemItems() {
        #expect(MoveTargeting.namesPinnedSystemItem("com.apple.menuextra.clock:Clock"))
        #expect(!MoveTargeting.namesPinnedSystemItem("com.example.app:Item-0"))
        #expect(MoveTargeting.controlItemSectionName(for: Self.item("Plain", windowID: 3).tag) == nil)
    }

    @Test("Control items, clones and suppressed items are never counted as stranded")
    func strandedSkipsUnfixableItems() {
        let hidden = MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 40,
            ownerPID: 999_970,
            sourcePID: 999_970,
            bounds: CGRect(x: 100, y: 0, width: 1, height: 24),
            title: nil,
            isOnScreen: true
        )
        let suppressed = Self.item("Suppressed", windowID: 41, x: 300)

        let stranded = MoveTargeting.membersStrandedAcrossDivider(
            items: [hidden, suppressed],
            controlItems: ControlItemPair(hidden: hidden, alwaysHidden: nil),
            sectionFor: { _ in .hidden },
            experimentalSystemItemHiding: false,
            isRepairSuppressed: { $0.windowID == suppressed.windowID }
        )

        #expect(stranded.isEmpty)
    }
}
