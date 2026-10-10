//
//  RecoveryAnchorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// The anchor a stuck-item recovery moves beside, and the fallbacks it walks
/// when the hidden control item's window is not on the bar.
struct RecoveryAnchorTests {
    private let section: (MenuBarItem) -> MenuBarSection.Name? = { item in
        switch item.tag {
        case .hiddenControlItem: .hidden
        case .alwaysHiddenControlItem: .alwaysHidden
        default: .visible
        }
    }

    private func item(
        _ title: String,
        x: CGFloat,
        windowID: UInt32,
        tag: MenuBarItemTag? = nil,
        width: CGFloat = 24
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag ?? MenuBarItemTag(
                namespace: .string("com.example.\(title)"),
                title: title,
                instanceIndex: 0
            ),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A seated hidden control item anchors the recovery")
    func seatedHiddenControlItemAnchors() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let hiddenControl = item("hidden", x: 900, windowID: 2, tag: .hiddenControlItem)
        let rightmost = item("Stats", x: 1000, windowID: 3)

        let anchor = MenuBarItemManager.recoveryAnchor(
            stuck: stuck,
            items: [stuck, hiddenControl, rightmost],
            hiddenControlItemWindowNumber: 2,
            section: section
        )

        #expect(anchor?.windowID == 2)
    }

    /// On macOS 27 an empty Hidden section keeps an unordered window whose number
    /// overflows CGWindowID; recovery must fall back to the rightmost visible item.
    @Test("Unconvertible hidden control window falls back to the rightmost visible item")
    func unconvertibleHiddenControlItemFallsBack() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let middle = item("Alfred", x: 800, windowID: 3)
        let rightmost = item("Stats", x: 1000, windowID: 4)

        let anchor = MenuBarItemManager.recoveryAnchor(
            stuck: stuck,
            items: [stuck, middle, rightmost],
            // 0x3_0000_0000: a window the server never ordered.
            hiddenControlItemWindowNumber: 12_884_901_888,
            section: section
        )

        #expect(anchor?.windowID == 4)
    }

    @Test("Nil hidden control window falls back the same way")
    func missingHiddenControlItemWindowFallsBack() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let rightmost = item("Stats", x: 1000, windowID: 4)

        let anchor = MenuBarItemManager.recoveryAnchor(
            stuck: stuck,
            items: [stuck, rightmost],
            hiddenControlItemWindowNumber: nil,
            section: section
        )

        #expect(anchor?.windowID == 4)
    }

    /// The stuck item itself, a second parked frame, and zero-width frames
    /// are all excluded from the fallback walk.
    @Test("Parked frames and the stuck item never anchor")
    func parkedFramesNeverAnchor() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let parkedDuplicate = item("stuck", x: -1, windowID: 9, tag: .visibleControlItem)
        let zeroWidth = item("ghost", x: 700, windowID: 10, width: 0)
        let healthy = item("Stats", x: 1000, windowID: 11)

        let anchor = MenuBarItemManager.recoveryAnchor(
            stuck: stuck,
            items: [stuck, parkedDuplicate, zeroWidth, healthy],
            hiddenControlItemWindowNumber: nil,
            section: section
        )

        #expect(anchor?.windowID == 11)
    }

    /// Right of the hidden-side control items is the hidden and always
    /// hidden territory, so only the direct (seated) branch may return them.
    @Test("Hidden-side control items never anchor through the fallback")
    func hiddenSideControlsNeverAnchorThroughFallback() {
        let stuck = item("stuck", x: -1, windowID: 1, tag: .visibleControlItem)
        let hiddenControl = item("hidden", x: 900, windowID: 2, tag: .hiddenControlItem)
        let alwaysHiddenControl = item("alwaysHidden", x: 950, windowID: 3, tag: .alwaysHiddenControlItem)
        let healthy = item("Stats", x: 1000, windowID: 4)

        let anchor = MenuBarItemManager.recoveryAnchor(
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

        let anchor = MenuBarItemManager.recoveryAnchor(
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

        let anchor = MenuBarItemManager.recoveryAnchor(
            stuck: stuck,
            items: [stuck, visible, concealed],
            hiddenControlItemWindowNumber: nil,
            section: { item in item.windowID == 5 ? .hidden : .visible }
        )

        #expect(anchor?.windowID == 3)
    }
}
