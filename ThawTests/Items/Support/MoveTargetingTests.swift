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

/// The anchor a stuck-item recovery moves beside, and the fallbacks it walks
/// when the hidden control item's window is not on the bar.
@MainActor
@Suite("Recovery anchor")
struct RecoveryAnchorTests {
    private let section: (MenuBarItem) -> MenuBarSection.Name? = { item in
        switch item.tag {
        case .hiddenControlItem: .hidden
        case .alwaysHiddenControlItem: .alwaysHidden
        default: .visible
        }
    }

    private func item(_ title: String, x: CGFloat, windowID: UInt32, tag: MenuBarItemTag? = nil, width: CGFloat = 24) -> MenuBarItem {
        ItemsFixture.item(title, tag: tag, x: x, width: width, windowID: windowID)
    }

    @Test("A seated hidden control item anchors the recovery")
    func seatedHiddenControlItemAnchors() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let hiddenControl = item("hidden", x: 900, windowID: 2, tag: .hiddenControlItem)
        let rightmost = item("Stats", x: 1000, windowID: 3)

        let anchor = MoveTargeting.recoveryAnchor(
            stuck: stuck,
            items: [stuck, hiddenControl, rightmost],
            hiddenControlItemWindowNumber: 2,
            section: section
        )

        #expect(anchor?.windowID == 2)
    }

    /// On macOS 27 an empty Hidden section keeps an unordered window whose number overflows
    /// CGWindowID (0x3_0000_0000, a window the server never ordered).
    @Test(
        "An unconvertible or missing hidden control window falls back to the rightmost visible item",
        arguments: [12_884_901_888, nil] as [Int?]
    )
    func hiddenControlWindowFallsBack(windowNumber: Int?) {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let middle = item("Alfred", x: 800, windowID: 3)
        let rightmost = item("Stats", x: 1000, windowID: 4)

        let anchor = MoveTargeting.recoveryAnchor(
            stuck: stuck,
            items: [stuck, middle, rightmost],
            hiddenControlItemWindowNumber: windowNumber,
            section: section
        )

        #expect(anchor?.windowID == 4)
    }

    @Test("Parked frames and the stuck item never anchor")
    func parkedFramesNeverAnchor() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let parkedDuplicate = item("stuck", x: -1, windowID: 9, tag: .visibleControlItem)
        let zeroWidth = item("ghost", x: 700, windowID: 10, width: 0)
        let healthy = item("Stats", x: 1000, windowID: 11)

        let anchor = MoveTargeting.recoveryAnchor(
            stuck: stuck,
            items: [stuck, parkedDuplicate, zeroWidth, healthy],
            hiddenControlItemWindowNumber: nil,
            section: section
        )

        #expect(anchor?.windowID == 11)
    }

    /// Right of them is concealed territory, so only the seated branch may return them.
    @Test("Hidden-side control items never anchor through the fallback")
    func hiddenSideControlsNeverAnchorThroughFallback() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let hiddenControl = item("hidden", x: 900, windowID: 2, tag: .hiddenControlItem)
        let alwaysHiddenControl = item("alwaysHidden", x: 950, windowID: 3, tag: .alwaysHiddenControlItem)
        let healthy = item("Stats", x: 1000, windowID: 4)

        let anchor = MoveTargeting.recoveryAnchor(
            stuck: stuck,
            items: [stuck, hiddenControl, alwaysHiddenControl, healthy],
            hiddenControlItemWindowNumber: nil,
            section: section
        )

        #expect(anchor?.windowID == 4)
    }

    @Test("Nothing healthy yields no anchor")
    func nothingHealthyYieldsNil() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)

        let anchor = MoveTargeting.recoveryAnchor(
            stuck: stuck,
            items: [stuck],
            hiddenControlItemWindowNumber: nil,
            section: section
        )

        #expect(anchor == nil)
    }

    /// Items filed outside the visible section must not anchor a recovery
    /// whose destination is a visible seat: on macOS 27 concealed items park
    /// with healthy-looking frames right of the visible ones.
    @Test("Concealed items do not anchor through the fallback")
    func concealedItemsDoNotAnchor() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let visible = item("Alfred", x: 800, windowID: 3)
        let concealed = item("DockDoor", x: 1200, windowID: 5)

        let anchor = MoveTargeting.recoveryAnchor(
            stuck: stuck,
            items: [stuck, visible, concealed],
            hiddenControlItemWindowNumber: nil,
            section: { item in item.windowID == 5 ? .hidden : .visible }
        )

        #expect(anchor?.windowID == 3)
    }
}
