//
//  SiriNotAnchoredTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Siri on macOS 27 is not a layout anchor")
struct SiriNotAnchoredTests {
    private static let spellings: [MenuBarItemTag] = [
        .siri,
        MenuBarItemTag(namespace: .menuBarAgent, title: "Siri"),
        MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.siri"),
    ]

    private func item(_ tag: MenuBarItemTag) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 0x9000_0001,
            ownerPID: 700,
            sourcePID: 700,
            bounds: CGRect(x: 1100, y: 0, width: 24, height: 22),
            title: tag.title,
            isOnScreen: true
        )
    }

    @Test("Siri is recognized in every spelling", arguments: spellings)
    func recognized(tag: MenuBarItemTag) {
        #expect(tag.isSiri)
    }

    @Test("Siri is movable and not an anchor", arguments: spellings)
    func movable(tag: MenuBarItemTag) {
        #expect(!tag.isLayoutAnchoredSystemItem)
        #expect(tag.isMovable)
        #expect(item(tag).isPhysicallyOrderable(experimentalSystemItemHiding: false))
    }

    @Test("Clock and Control Center stay anchors")
    func othersStayAnchored() {
        for tag in [MenuBarItemTag.clock, .controlCenter] {
            #expect(tag.isLayoutAnchoredSystemItem)
            #expect(!tag.isSiri)
        }
    }

    @Test("Siri stays forced visible without Standard hiding", arguments: spellings)
    func forcedVisibleByDefault(tag: MenuBarItemTag) {
        #expect(tag.sectionManagementPolicy == .forcedVisible)
        #expect(item(tag).sectionManagementPolicy(experimentalSystemItemHiding: false) == .forcedVisible)
    }

    @Test("Siri is hideable with Standard hiding", arguments: spellings)
    func hideableWithStandardHiding(tag: MenuBarItemTag) {
        #expect(item(tag).sectionManagementPolicy(experimentalSystemItemHiding: true) == .hideable)
    }

    @Test("Siri does not rank in the trailing anchor group", arguments: spellings)
    func rank(tag: MenuBarItemTag) {
        #expect(MenuBarItemTag.anchoredSystemItemRank(tag) == 3)
        #expect(MenuBarItemTag.anchoredSystemItemRank(.controlCenter) == 1)
        #expect(MenuBarItemTag.anchoredSystemItemRank(.clock) == 2)
    }

    @Test("The legacy divider layout still treats Siri as fixed")
    func legacyLayoutUnchanged() {
        #expect(!MenuBarItemTag.siri.isMovableInLegacySectionLayout)
    }
}
