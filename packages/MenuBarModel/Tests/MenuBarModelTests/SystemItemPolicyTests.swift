//
//  SystemItemPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// Which items Thaw may hide or move, for the items macOS or their owner keep for themselves.
@Suite("System item policy")
struct SystemItemPolicyTests {
    /// 2026-10-22 reports: ⌘-dragging the screen sharing indicator broke the whole bar. macOS
    /// places it wherever the user drops it, so it stays out of ordering like the camera indicator.
    @Test("The screen sharing indicator stays out of ordering and is not a trailing anchor")
    func screenSharingIndicator() {
        let tag = MenuBarItemTag.screenCaptureUI
        #expect(tag.isCaptureActivityIndicator)
        #expect(tag.sectionManagementPolicy == .excluded)
        #expect(!tag.isLayoutAnchoredSystemItem)
        #expect(!tag.isMovable)
        #expect(!tag.canBeHidden)
    }

    @Test("The Game Mode indicator can be hidden and moved like any other item")
    func gameModeIsArrangeable() {
        let tag = MenuBarItemTag.gameMode
        #expect(tag.sectionManagementPolicy == .hideable)
        #expect(tag.canBeHidden)
        #expect(tag.isMovable)
        #expect(!tag.isLayoutAnchoredSystemItem)
    }

    @Test("The camera and microphone indicator never enters managed sections", arguments: ["AudioVideoModule", "com.apple.menuextra.audiovideo"])
    func captureActivityNeverEntersManagedSections(title: String) {
        for host: MenuBarItemTag.Namespace in [.menuBarAgent, .controlCenter, .uuid(UUID())] {
            let tag = MenuBarItemTag(namespace: host, title: title)
            #expect(tag.sectionManagementPolicy == .excluded)
            #expect(!tag.isMovable)
        }
        let thirdParty = MenuBarItemTag(namespace: .string("com.example.recorder"), title: title)
        #expect(thirdParty.sectionManagementPolicy == .hideable)
        #expect(thirdParty.isMovable)
    }

    // The agent sorts a module under its module row, so a write to the status row moves nothing.
    @Test("A pinned module title resolves to its module row", arguments: [
        ("com.apple.menuextra.controlcenter-BentoBox-1", "module:BentoBox-1"),
        ("com.apple.menuextra.controlcenter-BentoBox-7", "module:BentoBox-7"),
        ("BentoBox-3", "module:BentoBox-3"),
        ("BentoBox-0", "module:ControlCenter"),
        ("Something-Else", "module:Something-Else"),
        ("AudioVideoModule", "module:AudioVideoModule"),
        ("com.apple.menuextra.audiovideo", "module:AudioVideoModule"),
    ])
    func moduleKey(title: String, key: String) {
        #expect(SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: title) == key)
    }
}

@Suite("Agent-ungoverned items")
struct AgentUngovernedItemTests {
    private let sideloadly = MenuBarItem.fixture(namespace: .string("sideloadly-daemon"))

    @Test("The bundle-less daemon owner is covered for every title, not just the first")
    func coversEveryTitle() {
        // Item-N shifts when siblings appear; owner matching keeps classification stable.
        for title in ["Item-0", "Item-1", "«none»"] {
            #expect(MenuBarItem.fixture(namespace: .string("sideloadly-daemon"), title: title).tag.isAgentUngoverned)
        }
    }

    @Test("A Wine or CrossOver tray icon is left to macOS")
    func wineTrayIconIsUngoverned() {
        // CrossOver hosts tray icons in explorer.exe, with no bundle ID for the restriction to name.
        let trayIcon = MenuBarItem.fixture(namespace: .string("explorer.exe"))
        #expect(trayIcon.tag.isAgentUngoverned)
        #expect(trayIcon.sectionManagementPolicy == .forcedVisible)
        #expect(!trayIcon.isMovable)
    }

    @Test(
        "Ordinary owners, the main Sideloadly bundle and non-string namespaces are governed",
        arguments: [
            MenuBarItemTag.Namespace.string("com.raycast.macos"),
            // Sideloadly's own bundle hosts no status item; only the helper does.
            .string("io.sideloadly.sideloadly"),
            .null,
            .uuid(UUID()),
        ]
    )
    func governedOwners(namespace: MenuBarItemTag.Namespace) {
        #expect(!MenuBarItem.fixture(namespace: namespace).tag.isAgentUngoverned)
    }

    @Test("It is shown and pinned, and the experimental gate does not rescue it")
    func shownAndPinned() {
        #expect(sideloadly.sectionManagementPolicy == .forcedVisible)
        #expect(sideloadly.sectionManagementPolicy.isVisibleInLayout)
        #expect(!sideloadly.canBeHidden)
        #expect(!sideloadly.canBeHidden(experimentalSystemItemHiding: true))
        #expect(!sideloadly.isMovable)
        #expect(!sideloadly.isMovable(experimentalSystemItemHiding: true))
        #expect(sideloadly.orderabilityRefusal(experimentalSystemItemHiding: false) == .notAgentManaged)
        #expect(sideloadly.orderabilityRefusal(experimentalSystemItemHiding: true) == .notAgentManaged)
        // Trailing-anchor classification would make the planner fight this leading-edge pin.
        #expect(!sideloadly.tag.isLayoutAnchoredSystemItem)
    }

    @Test("An ordinary item keeps its full management")
    func ordinaryItemUnaffected() {
        let raycast = MenuBarItem.fixture(namespace: .string("com.raycast.macos"))
        #expect(raycast.isMovable)
        #expect(raycast.canBeHidden)
        #expect(raycast.sectionManagementPolicy == .hideable)
        #expect(raycast.orderabilityRefusal(experimentalSystemItemHiding: false) == nil)
    }

    @Test("Hiding-unsupported owners stay reorderable")
    func hidingUnsupportedStillReorderable() {
        for bundleID in MenuBarItemTag.hidingUnsupportedBundleIDs {
            let subject = MenuBarItem.fixture(namespace: .string(bundleID))
            #expect(subject.sectionManagementPolicy == .forcedVisible)
            #expect(subject.isMovable)
        }
    }
}

/// macOS draws a Live Activity where it likes. A weight written for it is ignored and a drag does
/// not move it, so Thaw shows it and leaves it alone.
@Suite("Live Activity pills")
struct LiveActivityPillTests {
    private let pill = MenuBarItem.agent("live-activity-pill-com.apple.chrono.WidgetRenderer-Activities")

    @Test("A Live Activity is recognised by its identifier, whatever app it belongs to")
    func recognisedByIdentifier() {
        #expect(pill.tag.isLiveActivityPill)
        #expect(MenuBarItem.agent("live-activity-pill-com.example.Timer").tag.isLiveActivityPill)
        #expect(!MenuBarItem.agent("com.apple.menuextra.sound").tag.isLiveActivityPill)
        #expect(!MenuBarItemTag(namespace: .string("com.example.App"), title: "live-activity-pill-x").isLiveActivityPill)
    }

    @Test("It is shown and cannot be moved or hidden, with or without the Everything method")
    func shownAndPinned() {
        #expect(!pill.isMovable)
        #expect(!pill.isMovable(experimentalSystemItemHiding: false))
        #expect(!pill.isMovable(experimentalSystemItemHiding: true))
        #expect(pill.orderabilityRefusal(experimentalSystemItemHiding: false) == .systemAnchored)
        #expect(pill.orderabilityRefusal(experimentalSystemItemHiding: true) == .systemAnchored)
        #expect(pill.sectionManagementPolicy == .forcedVisible)
        #expect(pill.sectionManagementPolicy(experimentalSystemItemHiding: true) == .forcedVisible)
        #expect(!pill.canBeHidden)
        #expect(!pill.canBeHidden(experimentalSystemItemHiding: true))
    }

    @Test("An ordinary module keeps its verdicts")
    func ordinaryModulesAreUnaffected() {
        let wifi = MenuBarItem.agent("com.apple.menuextra.wifi")
        #expect(wifi.isMovable)
        #expect(wifi.sectionManagementPolicy == .hideable)
    }
}

/// MenuBarAgent sorts a pinned Control Center control by a chrono:<instance UUID> row, and the
/// tag drops that UUID on purpose, so no weight Thaw writes reaches it. Moving it would
/// shuffle the icons around it on every reveal.
@Suite("Pinned Control Center controls")
struct PinnedControlCenterControlTests {
    private static let screenshotIdentity =
        ":com.apple.screenshot.launcher:com.apple.controls.screenshot:com.apple.controls.screenshot.capture-custom"

    @Test("The stable identity and the live form with an instance UUID are both recognized", arguments: [
        screenshotIdentity,
        ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode",
        ":com.apple.controlcenter:com.apple.controls.display:com.apple.controls.display.dark-mode:51AF06CF-28BB-497D-94A1-33DD3AFA9A3A",
    ])
    func recognizesAPinnedControl(title: String) {
        #expect(MenuBarItemTag(namespace: .menuBarAgent, title: title).isPinnedControlCenterControl)
    }

    @Test("Menu extras, modules and third-party items are not pinned controls", arguments: [
        "com.apple.menuextra.sound",
        "Item-0",
        "live-activity-pill-1",
    ])
    func ordinaryAgentChildrenAreNot(title: String) {
        #expect(!MenuBarItemTag(namespace: .menuBarAgent, title: title).isPinnedControlCenterControl)
    }

    @Test("The same identity under an app's namespace is not a pinned control")
    func onlyUnderMenuBarAgent() {
        #expect(!MenuBarItemTag(namespace: .string("com.example.app"), title: Self.screenshotIdentity).isPinnedControlCenterControl)
    }

    @Test("It is shown and anchored by macOS, and no setting lifts that")
    func shownAndAnchored() {
        let control = MenuBarItem.agent(Self.screenshotIdentity)
        #expect(!control.isMovable)
        #expect(!control.isMovable(experimentalSystemItemHiding: true))
        #expect(control.orderabilityRefusal(experimentalSystemItemHiding: false) == .systemAnchored)
        #expect(control.orderabilityRefusal(experimentalSystemItemHiding: true) == .systemAnchored)
        #expect(control.sectionManagementPolicy == .forcedVisible)
    }
}

/// Accessibility exposes the native overflow chevron as a MenuBarAgent extra.
/// Treat it as chrome: excluded from sections and never physically orderable.
@Suite("Native overflow control")
struct NativeOverflowControlTests {
    @Test("Recognizes every title form the control has been seen with", arguments: [
        "AXOverflowButton",
        "axoverflowbutton",
        "Double backward chevron",
        "<",
        "<<",
        "‹ ›",
        "»",
        "Show Hidden Menu Bar Items",
        " Show Hidden Menu Bar Items ",
    ])
    func recognizesTheControlUnderMenuBarAgent(title: String) {
        #expect(MenuBarItemTag(namespace: .menuBarAgent, title: title).isNativeOverflowControl)
        #expect(MenuBarItemTag.isNativeOverflowControlTitle(title))
    }

    @Test("Reads the control's labels in every language of MenuBarAgent's string table")
    func readsLocalizedLabels() throws {
        let strings = [
            "en": ["menuBar.showOverflowItemsAccessibilityLabel": "Show Hidden Menu Bar Items"],
            "fr": [
                "menuBar.showOverflowItemsAccessibilityLabel": "Afficher les éléments masqués de la barre des menus",
                "menuBar.hideOverflowItemsAccessibilityLabel": "Masquer les éléments de la barre des menus",
                "menuBar.clockAccessibilityLabel": "Horloge",
            ],
        ]
        let table = try PropertyListSerialization.data(fromPropertyList: strings, format: .binary, options: 0)
        #expect(MenuBarItemTag.overflowControlTitles(inStringTable: table) == [
            "Show Hidden Menu Bar Items",
            "Afficher les éléments masqués de la barre des menus",
            "Masquer les éléments de la barre des menus",
        ])
        #expect(MenuBarItemTag.overflowControlTitles(inStringTable: nil).isEmpty)
        #expect(MenuBarItemTag.overflowControlTitles(inStringTable: Data("not a table".utf8)).isEmpty)
    }

    @Test("Real MenuBarAgent extras are not the control", arguments: [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter",
        "com.apple.menuextra.sound",
        "Item-0",
        "Wi-Fi",
        "<<<<<",
        "",
        "   ",
    ])
    func leavesRealExtrasAlone(title: String) {
        #expect(!MenuBarItemTag(namespace: .menuBarAgent, title: title).isNativeOverflowControl)
    }

    @Test("Only MenuBarAgent hosts the control", arguments: [
        MenuBarItemTag(namespace: .string("com.example.app"), title: "Show Hidden Menu Bar Items"),
        MenuBarItemTag(namespace: .string("com.example.app"), title: "<"),
        MenuBarItemTag(namespace: .controlCenter, title: "AXOverflowButton"),
    ])
    func requiresTheMenuBarAgentNamespace(tag: MenuBarItemTag) {
        #expect(!tag.isNativeOverflowControl)
    }

    @Test("The control is excluded from sections and never orderable, whatever the experimental gate says")
    func excludedAndNeverOrderable() {
        let item = MenuBarItem.agent("Show Hidden Menu Bar Items")
        #expect(item.isNativeOverflowControl)
        #expect(item.sectionManagementPolicy == .excluded)
        #expect(item.sectionManagementPolicy(experimentalSystemItemHiding: true) == .excluded)
        #expect(!item.canBeHidden(experimentalSystemItemHiding: true))
        // The tag is movable because it is not an anchor; the overflow-control check must refuse ordering.
        #expect(item.isMovable)
        #expect(item.orderabilityRefusal(experimentalSystemItemHiding: false) == .nativeOverflowControl)
        #expect(item.orderabilityRefusal(experimentalSystemItemHiding: true) == .nativeOverflowControl)
    }

    @Test("An ordinary MenuBarAgent module keeps its existing verdicts")
    func ordinaryModulesAreUnaffected() {
        let sound = MenuBarItem.agent("com.apple.menuextra.sound")
        #expect(!sound.isNativeOverflowControl)
        #expect(sound.sectionManagementPolicy != .excluded)
        #expect(sound.orderabilityRefusal(experimentalSystemItemHiding: false) != .nativeOverflowControl)
    }
}

@Suite("Siri on macOS 27 is not a layout anchor")
struct SiriPolicyTests {
    private static let spellings: [MenuBarItemTag] = [
        .siri,
        MenuBarItemTag(namespace: .menuBarAgent, title: "Siri"),
        MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.siri"),
    ]

    @Test("Siri in every spelling is movable, ranks after the anchors and hides only with Standard hiding", arguments: spellings)
    func verdicts(tag: MenuBarItemTag) {
        let item = MenuBarItem.fixture(tag)
        #expect(tag.isSiri)
        #expect(!tag.isLayoutAnchoredSystemItem)
        #expect(tag.isMovable)
        #expect(item.isPhysicallyOrderable(experimentalSystemItemHiding: false))
        #expect(MenuBarItemTag.anchoredSystemItemRank(tag) == 3)
        #expect(tag.sectionManagementPolicy == .forcedVisible)
        #expect(item.sectionManagementPolicy(experimentalSystemItemHiding: false) == .forcedVisible)
        #expect(item.sectionManagementPolicy(experimentalSystemItemHiding: true) == .hideable)
    }

    @Test("Control Center and Clock stay ranked anchors")
    func othersStayAnchored() {
        for (tag, rank) in [(MenuBarItemTag.controlCenter, 1), (.clock, 2)] {
            #expect(tag.isLayoutAnchoredSystemItem)
            #expect(!tag.isSiri)
            #expect(MenuBarItemTag.anchoredSystemItemRank(tag) == rank)
        }
    }

    @Test("The legacy divider layout still treats Siri as fixed")
    func legacyLayoutUnchanged() {
        #expect(!MenuBarItemTag.siri.isMovableInLegacySectionLayout)
    }
}
