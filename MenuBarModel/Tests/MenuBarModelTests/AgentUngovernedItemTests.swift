//
//  AgentUngovernedItemTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Agent-ungoverned items")
struct AgentUngovernedItemTests {
    private func item(
        namespace: MenuBarItemTag.Namespace,
        title: String = "Item-0"
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title),
            windowID: 0x9000_0001,
            ownerPID: 700,
            sourcePID: 700,
            bounds: CGRect(x: 1117, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    private var sideloadly: MenuBarItem {
        item(namespace: .string("sideloadly-daemon"))
    }

    // MARK: Membership

    @Test("The bundle-less daemon owner is recognized")
    func recognizesOwner() {
        #expect(sideloadly.tag.isAgentUngoverned)
    }

    @Test("An ordinary owner is not")
    func ordinaryOwnerIsGoverned() {
        #expect(!item(namespace: .string("com.raycast.macos")).tag.isAgentUngoverned)
    }

    @Test("The main app bundle is not the daemon")
    func mainBundleIsGoverned() {
        // Sideloadly's own bundle hosts no status item; only the helper does,
        // so forcing the app itself visible would be wrong.
        #expect(!item(namespace: .string("io.sideloadly.sideloadly")).tag.isAgentUngoverned)
    }

    @Test("A non-string namespace cannot match")
    func nonStringNamespace() {
        #expect(!item(namespace: .null).tag.isAgentUngoverned)
        #expect(!item(namespace: .uuid(UUID())).tag.isAgentUngoverned)
    }

    @Test("Every title from the owner is covered, not just the first")
    func coversEveryTitle() {
        // Item-N shifts when siblings appear; owner matching keeps classification stable.
        for title in ["Item-0", "Item-1", "«none»"] {
            #expect(item(namespace: .string("sideloadly-daemon"), title: title).tag.isAgentUngoverned)
        }
    }

    // MARK: Consequences

    @Test("It is forced visible, so it can never be parked in the hidden section")
    func forcedVisible() {
        #expect(sideloadly.sectionManagementPolicy == .forcedVisible)
        #expect(!sideloadly.canBeHidden)
        #expect(!sideloadly.canBeHidden(experimentalSystemItemHiding: true))
    }

    @Test("It stays in the layout editor rather than vanishing")
    func staysVisibleInLayout() {
        #expect(sideloadly.sectionManagementPolicy.isVisibleInLayout)
    }

    @Test("It is not movable, and the experimental gate does not rescue it")
    func notMovable() {
        #expect(!sideloadly.isMovable)
        #expect(!sideloadly.isMovable(experimentalSystemItemHiding: true))
        #expect(!sideloadly.isPhysicallyOrderable(experimentalSystemItemHiding: false))
        #expect(!sideloadly.isPhysicallyOrderable(experimentalSystemItemHiding: true))
    }

    @Test("The refusal names the real reason")
    func refusalReason() {
        #expect(
            sideloadly.orderabilityRefusal(experimentalSystemItemHiding: false) == .notAgentManaged
        )
        #expect(
            sideloadly.orderabilityRefusal(experimentalSystemItemHiding: true) == .notAgentManaged
        )
    }

    @Test("It is not classified as a trailing anchor")
    func notATrailingAnchor() {
        // Trailing-anchor classification would make the planner fight this leading-edge pin.
        #expect(!sideloadly.tag.isLayoutAnchoredSystemItem)
    }

    // MARK: Neighbours are untouched

    @Test("An ordinary item keeps its full management")
    func ordinaryItemUnaffected() {
        let raycast = item(namespace: .string("com.raycast.macos"))
        #expect(raycast.isMovable)
        #expect(raycast.canBeHidden)
        #expect(raycast.sectionManagementPolicy == .hideable)
        #expect(raycast.orderabilityRefusal(experimentalSystemItemHiding: false) == nil)
    }

    @Test("Hiding-unsupported owners stay reorderable")
    func hidingUnsupportedStillReorderable() {
        // Hiding-unsupported items must remain reorderable, unlike agent-ungoverned items.
        for bundleID in MenuBarItemTag.hidingUnsupportedBundleIDs {
            let subject = item(namespace: .string(bundleID))
            #expect(subject.sectionManagementPolicy == .forcedVisible)
            #expect(subject.isMovable)
        }
    }
}
