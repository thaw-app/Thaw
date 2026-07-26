//
//  MenuBarItemTagTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarHost
import PlatformRuntimeKit
@testable import Thaw
import XCTest

// MARK: - MenuBarItemTag.Namespace Tests

final class MenuBarItemTagNamespaceTests: XCTestCase {
    // MARK: - Initialization Tests

    func testNullNamespace() {
        let namespace = MenuBarItemTag.Namespace.null

        XCTAssertTrue(namespace.isNull)
        XCTAssertFalse(namespace.isString)
        XCTAssertFalse(namespace.isUUID)
        XCTAssertEqual(namespace.description, "null")
    }

    func testStringNamespace() {
        let namespace = MenuBarItemTag.Namespace.string("com.example.app")

        XCTAssertFalse(namespace.isNull)
        XCTAssertTrue(namespace.isString)
        XCTAssertFalse(namespace.isUUID)
        XCTAssertEqual(namespace.description, "com.example.app")
    }

    func testUUIDNamespace() {
        let uuid = UUID()
        let namespace = MenuBarItemTag.Namespace.uuid(uuid)

        XCTAssertFalse(namespace.isNull)
        XCTAssertFalse(namespace.isString)
        XCTAssertTrue(namespace.isUUID)
        XCTAssertEqual(namespace.description, uuid.uuidString)
    }

    func testOptionalWithValue() {
        let namespace = MenuBarItemTag.Namespace.optional("com.test.app")

        XCTAssertTrue(namespace.isString)
        XCTAssertEqual(namespace.description, "com.test.app")
    }

    func testOptionalWithNil() {
        let namespace = MenuBarItemTag.Namespace.optional(nil)

        XCTAssertTrue(namespace.isNull)
    }

    // MARK: - Equality Tests

    func testNamespaceEquality() {
        let ns1 = MenuBarItemTag.Namespace.string("com.example.app")
        let ns2 = MenuBarItemTag.Namespace.string("com.example.app")
        let ns3 = MenuBarItemTag.Namespace.string("com.other.app")

        XCTAssertEqual(ns1, ns2)
        XCTAssertNotEqual(ns1, ns3)
    }

    func testNullNamespaceEquality() {
        let ns1 = MenuBarItemTag.Namespace.null
        let ns2 = MenuBarItemTag.Namespace.null

        XCTAssertEqual(ns1, ns2)
    }

    func testUUIDNamespaceEquality() {
        let uuid = UUID()
        let ns1 = MenuBarItemTag.Namespace.uuid(uuid)
        let ns2 = MenuBarItemTag.Namespace.uuid(uuid)
        let ns3 = MenuBarItemTag.Namespace.uuid(UUID())

        XCTAssertEqual(ns1, ns2)
        XCTAssertNotEqual(ns1, ns3)
    }

    func testDifferentTypesNotEqual() {
        let stringNs = MenuBarItemTag.Namespace.string("test")
        let nullNs = MenuBarItemTag.Namespace.null

        XCTAssertNotEqual(stringNs, nullNs)
    }

    // MARK: - Hashable Tests

    func testNamespaceInSet() {
        var set = Set<MenuBarItemTag.Namespace>()
        set.insert(.string("com.example.app"))
        set.insert(.string("com.example.app")) // duplicate
        set.insert(.null)

        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Static Constants Tests

    func testThawNamespace() {
        let thaw = MenuBarItemTag.Namespace.thaw
        XCTAssertTrue(thaw.isString)
        XCTAssertEqual(thaw.description, Constants.bundleIdentifier)
    }

    func testControlCenterNamespace() {
        let cc = MenuBarItemTag.Namespace.controlCenter
        XCTAssertTrue(cc.isString)
        XCTAssertEqual(cc.description, "com.apple.controlcenter")
    }

    func testSystemUIServerNamespace() {
        let sys = MenuBarItemTag.Namespace.systemUIServer
        XCTAssertTrue(sys.isString)
        XCTAssertEqual(sys.description, "com.apple.systemuiserver")
    }
}

// MARK: - MenuBarItemTag Tests

final class MenuBarItemTagTests: XCTestCase {
    // MARK: - Initialization Tests

    func testBasicInit() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem"
        )

        XCTAssertEqual(tag.namespace, .string("com.example.app"))
        XCTAssertEqual(tag.title, "TestItem")
        XCTAssertNil(tag.windowID)
        XCTAssertEqual(tag.instanceIndex, 0)
    }

    func testInitWithWindowID() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            windowID: 12345
        )

        XCTAssertEqual(tag.windowID, 12345)
    }

    func testInitWithInstanceIndex() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            instanceIndex: 3
        )

        XCTAssertEqual(tag.instanceIndex, 3)
    }

    // MARK: - Description Tests

    func testDescriptionBasic() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem"
        )

        XCTAssertEqual(tag.description, "com.example.app:TestItem")
    }

    func testDescriptionWithInstanceIndex() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            instanceIndex: 2
        )

        XCTAssertTrue(tag.description.contains(":2"))
    }

    func testDescriptionWithEmptyTitle() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: ""
        )

        XCTAssertEqual(tag.description, "com.example.app")
    }

    // MARK: - Tag Identifier Tests

    func testTagIdentifierBasic() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem"
        )

        XCTAssertEqual(tag.tagIdentifier, "com.example.app:TestItem")
    }

    func testTagIdentifierWithInstanceIndex() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            instanceIndex: 5
        )

        XCTAssertEqual(tag.tagIdentifier, "com.example.app:TestItem:5")
    }

    func testTagIdentifierZeroInstanceIndexOmitted() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            instanceIndex: 0
        )

        XCTAssertEqual(tag.tagIdentifier, "com.example.app:TestItem")
        XCTAssertFalse(tag.tagIdentifier.hasSuffix(":0"))
    }

    // MARK: - System Item Tests

    func testIsSystemItemForControlCenter() {
        let tag = MenuBarItemTag(
            namespace: .controlCenter,
            title: "SomeItem"
        )

        XCTAssertTrue(tag.isSystemItem)
    }

    func testIsSystemItemForSystemUIServer() {
        let tag = MenuBarItemTag(
            namespace: .systemUIServer,
            title: "SomeItem"
        )

        XCTAssertTrue(tag.isSystemItem)
    }

    func testIsSystemItemForThaw() {
        let tag = MenuBarItemTag(
            namespace: .thaw,
            title: "SomeItem"
        )

        XCTAssertTrue(tag.isSystemItem)
    }

    func testIsNotSystemItemForThirdPartyApp() {
        let tag = MenuBarItemTag(
            namespace: .string("com.thirdparty.app"),
            title: "SomeItem"
        )

        XCTAssertFalse(tag.isSystemItem)
    }

    func testIsNotSystemItemForUUID() {
        let tag = MenuBarItemTag(
            namespace: .uuid(UUID()),
            title: "SomeItem"
        )

        XCTAssertFalse(tag.isSystemItem)
    }

    func testAppleStringNamespaceIsNonConcealableSystemItem() {
        let siri = MenuBarItemTag(
            namespace: .string("com.apple.systemuiserver"),
            title: "Siri"
        )

        XCTAssertTrue(siri.isSystemItem)
        XCTAssertTrue(siri.isNonConcealableSystemItem)

        // Any other `com.apple.*` owner AX reports as a plain string namespace
        // is still non-concealable even when it is not a named system constant.
        let unknownHost = MenuBarItemTag(
            namespace: .string("com.apple.legacyhost"),
            title: "Item-0"
        )

        XCTAssertFalse(unknownHost.isSystemItem)
        XCTAssertTrue(unknownHost.isNonConcealableSystemItem)
    }

    func testMenuBarAgentItemIsNonConcealableSystemItem() {
        let sound = MenuBarItemTag(
            namespace: .menuBarAgent,
            title: "com.apple.menuextra.sound"
        )

        XCTAssertTrue(sound.isNonConcealableSystemItem)
    }

    func testMenuBarAgentChevronOnlyItemIsNativeOverflowPlaceholder() {
        XCTAssertTrue(
            MenuBarItemTag(namespace: .menuBarAgent, title: "<<").isNativeOverflowPlaceholder
        )
        XCTAssertTrue(
            MenuBarItemTag(namespace: .menuBarAgent, title: "‹ ‹").isNativeOverflowPlaceholder
        )
        if #available(macOS 27, *) {
            XCTAssertEqual(
                MenuBarItemTag(namespace: .menuBarAgent, title: "<<").sectionManagementPolicy,
                .excluded
            )
        }
    }

    func testNativeOverflowPlaceholderDoesNotMatchRealItems() {
        XCTAssertFalse(
            MenuBarItemTag(namespace: .string("com.example.app"), title: "<<").isNativeOverflowPlaceholder
        )
        XCTAssertFalse(
            MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi").isNativeOverflowPlaceholder
        )
        XCTAssertFalse(
            MenuBarItemTag(namespace: .menuBarAgent, title: "Wi-Fi").isNativeOverflowPlaceholder
        )
    }

    func testThirdPartyItemIsConcealable() {
        let tag = MenuBarItemTag(
            namespace: .string("com.thirdparty.app"),
            title: "SomeItem"
        )

        XCTAssertFalse(tag.isNonConcealableSystemItem)
    }

    // MARK: - Movable Tests

    func testClockIsNotMovable() {
        let clock = MenuBarItemTag.clock
        XCTAssertFalse(clock.isMovable)
    }

    func testControlCenterIsNotMovable() {
        let cc = MenuBarItemTag.controlCenter
        XCTAssertFalse(cc.isMovable)
    }

    func testRegularItemIsMovable() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "RegularItem"
        )

        XCTAssertTrue(tag.isMovable)
    }

    func testLegacyMovabilityIsIndependentFromMacOS27Anchoring() {
        let screenCapture = MenuBarItemTag.screenCaptureUI
        let legacyClock = MenuBarItemTag(namespace: .controlCenter, title: "Clock")

        XCTAssertTrue(screenCapture.isLayoutAnchoredSystemItem)
        XCTAssertFalse(screenCapture.isMovable)
        XCTAssertTrue(screenCapture.isMovableInLegacySectionLayout)
        XCTAssertFalse(legacyClock.isMovableInLegacySectionLayout)
    }

    func testMacOS27OnlyTrailingSystemItemsAreAnchored() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let anchoredTags = [
            MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"),
            MenuBarItemTag(namespace: .menuBarAgent, title: "BentoBox-0"),
            MenuBarItemTag(namespace: .menuBarAgent, title: "Siri"),
            MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.controlcenter"),
            MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.siri"),
            MenuBarItemTag(namespace: .systemUIServer, title: "Siri"),
        ]

        for tag in anchoredTags {
            XCTAssertTrue(tag.isLayoutAnchoredSystemItem, tag.description)
            XCTAssertFalse(tag.isMovable, tag.description)
            XCTAssertFalse(tag.canBeHidden, tag.description)
        }
    }

    func testMacOS27OtherMenuBarAgentModulesAreMovable() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let movableTitles = [
            "WiFi",
            "Sound",
            "Bluetooth",
            "NowPlaying",
            "FocusModes",
            "com.apple.menuextra.wifi",
            "com.apple.menuextra.sound",
            "com.apple.menuextra.bluetooth",
            "com.apple.menuextra.now-playing",
            "com.apple.menuextra.focusmode",
        ]

        for title in movableTitles {
            let tag = MenuBarItemTag(namespace: .menuBarAgent, title: title)

            XCTAssertFalse(tag.isLayoutAnchoredSystemItem, title)
            XCTAssertTrue(tag.isMovable, title)
        }
    }

    @MainActor
    func testMacOS27NonGovernableMenuBarAgentModulesAreHideableOnlyUnderTheToggle() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent policy is macOS 27-specific")
        }

        for title in ["Sound", "Volume", "Displays", "Display", "Keyboard", "ScreenMirroring"] {
            let tag = MenuBarItemTag(namespace: .menuBarAgent, title: title)
            let item = MenuBarItem.fixture(tag: tag, windowID: 1)

            XCTAssertTrue(tag.isMovable, title)
            XCTAssertEqual(tag.sectionManagementPolicy, .forcedVisible, title)
            XCTAssertFalse(item.canBeHidden(experimentalSystemItemHiding: false), title)
            XCTAssertTrue(item.canBeHidden(experimentalSystemItemHiding: true), title)
            XCTAssertTrue(item.isPhysicallyOrderable(experimentalSystemItemHiding: false), title)
            XCTAssertFalse(
                MenuBarSectionController.canAssign(
                    item,
                    to: .hidden,
                    experimentalSystemItemHiding: false
                ),
                title
            )
            XCTAssertTrue(
                MenuBarSectionController.canAssign(
                    item,
                    to: .hidden,
                    experimentalSystemItemHiding: true
                ),
                title
            )
        }
    }

    func testMacOS27AllMenuBarAgentItemsAreForcedVisible() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent policy is macOS 27-specific")
        }

        let wifi = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi")
        let unknown = MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0")

        XCTAssertEqual(wifi.sectionManagementPolicy, .forcedVisible)
        XCTAssertEqual(unknown.sectionManagementPolicy, .forcedVisible)
    }

    @MainActor
    func testMacOS27FocusAndNowPlayingCanBePositionManaged() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent position management is macOS 27-specific")
        }

        for title in ["com.apple.menuextra.focusmode", "com.apple.menuextra.now-playing"] {
            let tag = MenuBarItemTag(namespace: .menuBarAgent, title: title)
            let item = MenuBarItem.fixture(tag: tag, windowID: 1)

            XCTAssertTrue(tag.isPositionManageableMenuBarAgentItem, title)
            XCTAssertTrue(MenuBarItemTag.isPositionManageableMenuBarAgentIdentifier(tag.description), title)
            XCTAssertFalse(tag.isMenuBarAgentItemForcedVisible, title)
            XCTAssertEqual(tag.sectionManagementPolicy, .hideable, title)
            XCTAssertTrue(MenuBarSectionController.canAssign(
                item,
                to: .hidden,
                experimentalSystemItemHiding: false
            ), title)
        }
    }

    func testUnknownMenuBarAgentItemIsNotAnchored() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let tag = MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0")

        XCTAssertFalse(tag.isLayoutAnchoredSystemItem)
        XCTAssertTrue(tag.isMovable)
    }

    // MARK: - Can Be Hidden Tests

    func testVisibleControlItemCannotBeHidden() {
        let visible = MenuBarItemTag.visibleControlItem
        XCTAssertFalse(visible.canBeHidden)
    }

    func testAudioVideoModuleCannotBeHidden() {
        let avm = MenuBarItemTag.audioVideoModule
        XCTAssertFalse(avm.canBeHidden)
    }

    func testRegularItemCanBeHidden() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "RegularItem"
        )

        XCTAssertTrue(tag.canBeHidden)
    }

    func testUUIDAudioVideoModuleCannotBeHidden() {
        let tag = MenuBarItemTag(
            namespace: .uuid(UUID()),
            title: "AudioVideoModule"
        )

        XCTAssertFalse(tag.canBeHidden)
    }

    // MARK: - Hiding Denylist Tests

    func testRegularAppIsNotHidingUnsupported() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "Item-0"
        )
        XCTAssertFalse(tag.isHidingUnsupported)
    }

    func testIStatItemIsNotHidingUnsupported() {
        let cpu = MenuBarItemTag(
            namespace: .string("com.bjango.istatmenus.status"),
            title: "CPU #%"
        )
        XCTAssertFalse(cpu.isHidingUnsupported)
    }

    // MARK: - iStat Canonical Identity Tests

    func testIStatItemIsMovableAndHideableOnMacOS27() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 section policy is OS-specific")
        }
        let cpu = MenuBarItemTag(
            namespace: .string("com.bjango.istatmenus.status"),
            title: "CPU #%"
        )
        XCTAssertTrue(cpu.isMovable)
        XCTAssertTrue(cpu.canBeHidden)
        XCTAssertEqual(cpu.sectionManagementPolicy, .hideable)
    }

    func testIStatRemainsHideableWithExperimentalHidingOn() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 section policy is OS-specific")
        }
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus.status", title: "CPU #%"),
            windowID: 1
        )
        XCTAssertTrue(item.canBeHidden(experimentalSystemItemHiding: false))
        XCTAssertTrue(item.canBeHidden(experimentalSystemItemHiding: true))
        XCTAssertTrue(item.isMovable(experimentalSystemItemHiding: true))
    }

    func testIStatUniqueIdentifierCanonicalizesRawMetricValues() {
        let raw = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus.status", title: "CPU 45%"),
            windowID: 1
        )

        XCTAssertEqual(raw.uniqueIdentifier, "com.bjango.istatmenus.status:CPU #%")
    }

    func testIStatTagsMatchIgnoringRawMetricValues() {
        let raw = MenuBarItemTag.appItem(
            bundleID: "com.bjango.istatmenus.status",
            title: "Upload 15.3 KB/s, Download 1.2 MB/s"
        )
        let canonical = MenuBarItemTag.appItem(
            bundleID: "com.bjango.istatmenus.status",
            title: "Upload # B/s, Download # B/s"
        )

        XCTAssertTrue(raw.matchesIgnoringWindowID(canonical))
    }

    func testIStatPersistentIdentifierCanonicalizesRawMetricValues() {
        XCTAssertEqual(
            MenuBarItemTag.canonicalPersistentIdentifier(
                "com.bjango.istatmenus.status:Upload 15.3 KB/s, Download 1.2 MB/s"
            ),
            "com.bjango.istatmenus.status:Upload # B/s, Download # B/s"
        )
    }

    func testMacOS27SectionManagementPolicyCentralizesSystemExceptions() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Assertion-backed section policy is macOS 27-specific")
        }

        let siri = MenuBarItemTag.siri
        let wifi = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi")
        let weather = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.weather")
        let app = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")

        XCTAssertEqual(siri.sectionManagementPolicy, .forcedVisible)
        XCTAssertFalse(siri.canBeHidden)
        XCTAssertTrue(siri.sectionManagementPolicy.isVisibleInLayout)

        XCTAssertEqual(wifi.sectionManagementPolicy, .forcedVisible)
        XCTAssertFalse(wifi.canBeHidden)
        XCTAssertEqual(weather.sectionManagementPolicy, .forcedVisible)
        XCTAssertFalse(weather.canBeHidden)

        XCTAssertEqual(app.sectionManagementPolicy, .hideable)
        XCTAssertTrue(app.canBeHidden)
    }

    // MARK: - Control Item Tests

    func testHiddenControlItemIsControlItem() {
        let hidden = MenuBarItemTag.hiddenControlItem
        XCTAssertTrue(hidden.isControlItem)
    }

    func testAlwaysHiddenControlItemIsControlItem() {
        let alwaysHidden = MenuBarItemTag.alwaysHiddenControlItem
        XCTAssertTrue(alwaysHidden.isControlItem)
    }

    func testVisibleControlItemIsControlItem() {
        let visible = MenuBarItemTag.visibleControlItem
        XCTAssertTrue(visible.isControlItem)
    }

    func testMenuBarHostVisibleControlItemIsControlItemAndMovable() {
        let hostVisible = MenuBarItemTag(
            namespace: .string("\(Constants.bundleIdentifier).MenuBarHost"),
            title: ControlItem.Identifier.visible.rawValue
        )
        XCTAssertTrue(hostVisible.isControlItem)
        XCTAssertTrue(hostVisible.matchesVisibleControlItem)
        XCTAssertTrue(hostVisible.isMovable)
    }

    func testRegularItemIsNotControlItem() {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "RegularItem"
        )

        XCTAssertFalse(tag.isControlItem)
    }

    func testSpacerIsControlItem() {
        let tag = MenuBarItemTag(
            namespace: .thaw,
            title: "Something.Spacer.Item"
        )

        XCTAssertTrue(tag.isControlItem)
    }

    // MARK: - BentoBox Tests

    func testBentoBoxDetection() {
        // The BentoBox is owned by the menu bar hosting process: Control Center
        // on macOS 26, MenuBarAgent on macOS 27+.
        let hostingNamespace: MenuBarItemTag.Namespace = if #available(macOS 27, *) {
            .menuBarAgent
        } else {
            .controlCenter
        }
        let tag = MenuBarItemTag(
            namespace: hostingNamespace,
            title: "BentoBox-0"
        )

        XCTAssertTrue(tag.isBentoBox)
    }

    func testBentoBoxWithoutPrefix() {
        let tag = MenuBarItemTag(
            namespace: .controlCenter,
            title: "NotBentoBox"
        )

        XCTAssertFalse(tag.isBentoBox)
    }

    func testBentoBoxWrongNamespace() {
        let tag = MenuBarItemTag(
            namespace: .string("com.other.app"),
            title: "BentoBox-0"
        )

        XCTAssertFalse(tag.isBentoBox)
    }

    // MARK: - System Clone Tests

    func testIsSystemClone() {
        let tag = MenuBarItemTag(
            namespace: .uuid(UUID()),
            title: "System Status Item Clone"
        )

        XCTAssertTrue(tag.isSystemClone)
    }

    func testIsSystemCloneWithStringNamespace() {
        // Field logs show clones carry a non-UUID namespace: the owning
        // process name (Window Server) when the source PID never resolves,
        // or a real bundle ID when the clone spatially mis-matches a nearby
        // app. The title is the reliable discriminator, so a string
        // namespace with the clone title must still count as a clone.
        let processNamespaceClone = MenuBarItemTag(
            namespace: .string("Window Server"),
            title: "System Status Item Clone"
        )
        let bundleNamespaceClone = MenuBarItemTag(
            namespace: .string("com.google.drivefs"),
            title: "System Status Item Clone"
        )

        XCTAssertTrue(processNamespaceClone.isSystemClone)
        XCTAssertTrue(bundleNamespaceClone.isSystemClone)
    }

    func testIsNotSystemCloneWithDifferentTitle() {
        let tag = MenuBarItemTag(
            namespace: .uuid(UUID()),
            title: "RegularItem"
        )

        XCTAssertFalse(tag.isSystemClone)
    }

    // MARK: - Equality Tests

    func testEqualityBasic() {
        let tag1 = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            instanceIndex: 0
        )
        let tag2 = MenuBarItemTag(
            namespace: .string("com.example.app"),
            title: "TestItem",
            instanceIndex: 0
        )

        XCTAssertEqual(tag1, tag2)
    }

    func testEqualityDifferentNamespace() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app1"), title: "Item")
        let tag2 = MenuBarItemTag(namespace: .string("com.app2"), title: "Item")

        XCTAssertNotEqual(tag1, tag2)
    }

    func testEqualityDifferentTitle() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item1")
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item2")

        XCTAssertNotEqual(tag1, tag2)
    }

    func testEqualityDifferentInstanceIndex() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 0)
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 1)

        XCTAssertNotEqual(tag1, tag2)
    }

    func testEqualitySystemItemIgnoresWindowID() {
        let tag1 = MenuBarItemTag(namespace: .controlCenter, title: "Item", windowID: 100)
        let tag2 = MenuBarItemTag(namespace: .controlCenter, title: "Item", windowID: 200)

        // System items ignore windowID in equality
        XCTAssertEqual(tag1, tag2)
    }

    func testEqualityNonSystemItemUsesWindowID() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 100)
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 200)

        // Non-system items consider windowID in equality
        XCTAssertNotEqual(tag1, tag2)
    }

    // MARK: - Matches Ignoring Window ID Tests

    func testMatchesIgnoringWindowID() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 100)
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 200)

        XCTAssertTrue(tag1.matchesIgnoringWindowID(tag2))
    }

    func testMatchesIgnoringWindowIDDifferentNamespace() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app1"), title: "Item", windowID: 100)
        let tag2 = MenuBarItemTag(namespace: .string("com.app2"), title: "Item", windowID: 100)

        XCTAssertFalse(tag1.matchesIgnoringWindowID(tag2))
    }

    func testMatchesIgnoringWindowIDDifferentInstanceIndex() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 0)
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 1)

        XCTAssertFalse(tag1.matchesIgnoringWindowID(tag2))
    }

    // MARK: - Hashable Tests

    func testHashableInSet() {
        var set = Set<MenuBarItemTag>()
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item1")
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item2")
        let tag3 = MenuBarItemTag(namespace: .string("com.app"), title: "Item1") // duplicate

        set.insert(tag1)
        set.insert(tag2)
        set.insert(tag3)

        XCTAssertEqual(set.count, 2)
    }

    func testHashableAsDictionaryKey() {
        var dict = [MenuBarItemTag: String]()
        let tag = MenuBarItemTag(namespace: .string("com.app"), title: "Item")

        dict[tag] = "value"

        XCTAssertEqual(dict[tag], "value")
    }

    // MARK: - Static Constants Tests

    func testImmovableItemsContainsClock() {
        XCTAssertTrue(MenuBarItemTag.immovableItems.contains { $0.title == "Clock" })
    }

    func testNonHideableItemsContainsVisibleControlItem() {
        XCTAssertTrue(MenuBarItemTag.nonHideableItems.contains { $0 == .visibleControlItem })
    }

    func testControlItemsContainsHiddenControlItem() {
        XCTAssertTrue(MenuBarItemTag.controlItems.contains(.hiddenControlItem))
    }

    func testControlItemsContainsAlwaysHiddenControlItem() {
        XCTAssertTrue(MenuBarItemTag.controlItems.contains(.alwaysHiddenControlItem))
    }
}

// MARK: - macOS 27 Layout Anchor Tests

final class MacOS27LayoutAnchorOrderingTests: XCTestCase {
    @available(macOS 27, *)
    func testIStatIdentityPrefersStableAccessibilityDescription() {
        let namespace = MenuBarItemTag.Namespace.string("com.bjango.istatmenus.status")

        XCTAssertEqual(
            MenuBarItemAXProvider.identityTitle(
                namespace: namespace,
                identifier: nil,
                accessibilityDescription: "CPU",
                displayTitle: "CPU 9%"
            ),
            "CPU"
        )
    }

    @available(macOS 27, *)
    func testParkedOffMenuBarBandDetectsParkingWhenControlAlsoParked() {
        let control = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: -1, y: 1413, width: 35, height: 24)
        )
        let parked = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.bjango.istatmenus.status"), title: "CPU", windowID: 2),
            windowID: 2,
            bounds: CGRect(x: 7, y: 1413, width: 21, height: 24)
        )
        let peers = [control, parked]

        XCTAssertTrue(control.isParkedOffMenuBarBand(among: peers))
        XCTAssertTrue(parked.isParkedOffMenuBarBand(among: peers))
    }

    @available(macOS 27, *)
    func testParkedOffMenuBarBandDetectsAssertionReflowParking() {
        let control = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: 2200, y: 3, width: 35, height: 24)
        )
        let onBar = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.example.app"), title: "Item", windowID: 1),
            windowID: 1,
            bounds: CGRect(x: 2100, y: 3, width: 24, height: 24)
        )
        let parked = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.bjango.istatmenus.status"), title: "CPU", windowID: 2),
            windowID: 2,
            bounds: CGRect(x: 7, y: 1413, width: 21, height: 24)
        )
        let peers = [control, onBar, parked]

        XCTAssertFalse(onBar.isParkedOffMenuBarBand(among: peers))
        XCTAssertTrue(parked.isParkedOffMenuBarBand(among: peers))
    }

    @available(macOS 27, *)
    func testRestrictionReflowCollateralDetectsNeighborOfConcealedItem() {
        let control = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: 2360, y: 3, width: 35, height: 24)
        )
        let proton = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("ch.protonmail.drive"), title: "Proton Drive", windowID: 1),
            windowID: 1,
            bounds: CGRect(x: 1985, y: 3, width: 24, height: 24)
        )
        let istatCPU = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.bjango.istatmenus.status"), title: "CPU", windowID: 2),
            windowID: 2,
            bounds: CGRect(x: 2023, y: 3, width: 21, height: 24)
        )
        let discord = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.hnc.Discord"), title: "Item-0", windowID: 3),
            windowID: 3,
            bounds: CGRect(x: 2153, y: 3, width: 40, height: 24)
        )
        let peers = [control, proton, istatCPU, discord]
        let concealed = Set([proton.uniqueIdentifier])

        XCTAssertTrue(istatCPU.isRestrictionReflowCollateral(among: peers, concealedIdentifiers: concealed))
        XCTAssertFalse(discord.isRestrictionReflowCollateral(among: peers, concealedIdentifiers: concealed))
    }

    @available(macOS 27, *)
    func testIStatIdentityNormalizesChangingMetricValuesWithoutDescription() {
        let namespace = MenuBarItemTag.Namespace.string("com.bjango.istatmenus.status")

        let first = MenuBarItemAXProvider.identityTitle(
            namespace: namespace,
            identifier: nil,
            accessibilityDescription: nil,
            displayTitle: "CPU 10%"
        )
        let second = MenuBarItemAXProvider.identityTitle(
            namespace: namespace,
            identifier: nil,
            accessibilityDescription: nil,
            displayTitle: "CPU 8%"
        )

        XCTAssertEqual(first, second)
    }

    @available(macOS 27, *)
    func testIStatIdentityNormalizesChangingTransferUnitsWithoutDescription() {
        let namespace = MenuBarItemTag.Namespace.string("com.bjango.istatmenus.status")

        let kilobytes = MenuBarItemAXProvider.identityTitle(
            namespace: namespace,
            identifier: nil,
            accessibilityDescription: nil,
            displayTitle: "Upload 154 KB/s, Download 10 KB/s"
        )
        let megabytes = MenuBarItemAXProvider.identityTitle(
            namespace: namespace,
            identifier: nil,
            accessibilityDescription: nil,
            displayTitle: "Upload 95 KB/s, Download 1.2 MB/s"
        )

        XCTAssertEqual(kilobytes, megabytes)
    }

    @available(macOS 27, *)
    func testMenuBarAgentOverflowChevronPlaceholdersAreFiltered() {
        XCTAssertTrue(
            MenuBarItemAXProvider.isNativeOverflowChevronPlaceholder(
                namespace: .menuBarAgent,
                identityTitle: "<<",
                displayTitle: "<<"
            )
        )
        XCTAssertTrue(
            MenuBarItemAXProvider.isNativeOverflowChevronPlaceholder(
                namespace: .menuBarAgent,
                identityTitle: "‹ ‹",
                displayTitle: "‹ ‹"
            )
        )
        XCTAssertTrue(
            MenuBarItemAXProvider.isNativeOverflowChevronPlaceholder(
                namespace: .menuBarAgent,
                identityTitle: "AXOverflowButton",
                displayTitle: ""
            )
        )
    }

    @available(macOS 27, *)
    func testOverflowChevronFilterDoesNotHideRealItems() {
        XCTAssertFalse(
            MenuBarItemAXProvider.isNativeOverflowChevronPlaceholder(
                namespace: .string("com.example.app"),
                identityTitle: "<<",
                displayTitle: "<<"
            )
        )
        XCTAssertFalse(
            MenuBarItemAXProvider.isNativeOverflowChevronPlaceholder(
                namespace: .menuBarAgent,
                identityTitle: "com.apple.menuextra.wifi",
                displayTitle: "Wi-Fi"
            )
        )
    }

    @MainActor
    func testAssignmentFromOrderClampsAlwaysHiddenIntoHiddenWhenDisabled() {
        let order: [MenuBarSection.Name: [String]] = [
            .hidden: ["com.example.hidden:Hidden"],
            .alwaysHidden: ["com.example.always:Always"],
        ]

        let assignment = MenuBarSectionController.assignmentFromOrder(
            order,
            alwaysHiddenEnabled: false
        )

        XCTAssertEqual(
            assignment,
            [
                "com.example.hidden:Hidden": .hidden,
                "com.example.always:Always": .hidden,
            ]
        )
        XCTAssertEqual(order[.alwaysHidden], ["com.example.always:Always"])
    }

    @MainActor
    func testAssignmentFromOrderPreservesIStatIdentifiersWhenHideable() {
        let order: [MenuBarSection.Name: [String]] = [
            .hidden: [
                "com.bjango.istatmenus.status:CPU #%",
                "com.example.hidden:Hidden",
            ],
            .alwaysHidden: [
                "com.bjango.istatmenus.status:Upload # B/s",
            ],
        ]

        let assignment = MenuBarSectionController.assignmentFromOrder(order)

        XCTAssertEqual(
            assignment,
            [
                "com.bjango.istatmenus.status:CPU #%": .hidden,
                "com.example.hidden:Hidden": .hidden,
                "com.bjango.istatmenus.status:Upload # B/s": .alwaysHidden,
            ]
        )
    }

    @MainActor
    func testAssignmentFromOrderPreservesAlwaysHiddenWhenEnabled() {
        let order: [MenuBarSection.Name: [String]] = [
            .hidden: ["com.example.hidden:Hidden"],
            .alwaysHidden: ["com.example.always:Always"],
        ]

        let assignment = MenuBarSectionController.assignmentFromOrder(
            order,
            alwaysHiddenEnabled: true
        )

        XCTAssertEqual(
            assignment,
            [
                "com.example.hidden:Hidden": .hidden,
                "com.example.always:Always": .alwaysHidden,
            ]
        )
    }

    @MainActor
    func testInvalidAssignmentIdentifiersPreservesMissingHiddenItems() {
        let assignment: [String: MenuBarSection.Name] = [
            "com.example.hidden:Hidden": .hidden,
        ]

        let invalid = MenuBarSectionController.invalidAssignmentIdentifiers(
            sectionAssignment: assignment,
            liveItems: [],
            experimentalSystemItemHiding: false
        )

        XCTAssertTrue(invalid.isEmpty)
    }

    @MainActor
    func testInvalidAssignmentIdentifiersRejectsProtectedLiveItems() throws {
        try XCTSkipUnless(isRunningOnMacOS27OrLater)
        let clock = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.systemuiserver", title: "Clock"),
            windowID: 1900
        )
        let assignment: [String: MenuBarSection.Name] = [
            clock.uniqueIdentifier: .hidden,
        ]

        let invalid = MenuBarSectionController.invalidAssignmentIdentifiers(
            sectionAssignment: assignment,
            liveItems: [clock],
            experimentalSystemItemHiding: false
        )

        XCTAssertEqual(invalid, [clock.uniqueIdentifier])
    }

    @MainActor
    func testSanitizedAssignmentRejectsNonGovernableMenuBarAgentModulesWithoutLiveItems() {
        let sound = MenuBarItemTag(namespace: .menuBarAgent, title: "Sound").tagIdentifier
        let displays = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.displays").tagIdentifier
        let wifi = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi").tagIdentifier
        let unknown = MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0").tagIdentifier

        let sanitized = MenuBarSectionController.sanitizedSectionAssignment(
            [
                sound: .hidden,
                displays: .alwaysHidden,
                wifi: .hidden,
                unknown: .hidden,
            ],
            experimentalSystemItemHiding: false
        )

        XCTAssertNil(sanitized[sound])
        XCTAssertNil(sanitized[displays])
        XCTAssertNil(sanitized[wifi])
        XCTAssertNil(sanitized[unknown])
    }

    /// The "hide native macOS items" toggle exists to reach exactly these
    /// modules, so their assignments must survive sanitizing while it is on.
    @MainActor
    func testSanitizedAssignmentKeepsMenuBarAgentModulesUnderExperimentalHiding() {
        let sound = MenuBarItemTag(namespace: .menuBarAgent, title: "Sound").tagIdentifier
        let displays = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.displays").tagIdentifier
        let clock = MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock").tagIdentifier

        let sanitized = MenuBarSectionController.sanitizedSectionAssignment(
            [
                sound: .hidden,
                displays: .alwaysHidden,
                clock: .hidden,
            ],
            experimentalSystemItemHiding: true
        )

        XCTAssertEqual(sanitized[sound], .hidden)
        XCTAssertEqual(sanitized[displays], .alwaysHidden)
        XCTAssertEqual(sanitized[clock], .hidden)
    }

    @MainActor
    func testMergeMigratedSectionOrderFromLegacyOrderOnly() {
        let order = MenuBarSectionController.mergeMigratedSectionOrder(
            sharedOrder: nil,
            legacyOrder: ["hidden": ["a", "b"]],
            legacyAssignment: nil
        )

        XCTAssertEqual(order[.hidden], ["a", "b"])
    }

    @MainActor
    func testMergeMigratedSectionOrderAppendsLegacyOrderWithoutDuplicates() {
        let order = MenuBarSectionController.mergeMigratedSectionOrder(
            sharedOrder: ["hidden": ["a"]],
            legacyOrder: ["hidden": ["a", "b"]],
            legacyAssignment: nil
        )

        XCTAssertEqual(order[.hidden], ["a", "b"])
    }

    @MainActor
    func testMergeMigratedSectionOrderCanonicalizesIStatIdentifiers() {
        let order = MenuBarSectionController.mergeMigratedSectionOrder(
            sharedOrder: [
                "visible": [
                    "com.bjango.istatmenus.status:CPU 45%",
                    "com.bjango.istatmenus.status:CPU #%",
                ],
            ],
            legacyOrder: [
                "visible": [
                    "com.bjango.istatmenus.status:Upload 15.3 KB/s, Download 1.2 MB/s",
                ],
            ],
            legacyAssignment: nil
        )

        XCTAssertEqual(
            order[.visible],
            [
                "com.bjango.istatmenus.status:CPU #%",
                "com.bjango.istatmenus.status:Upload # B/s, Download # B/s",
            ]
        )
    }

    @MainActor
    func testMergeMigratedSectionOrderAppendsLegacyAssignment() {
        let order = MenuBarSectionController.mergeMigratedSectionOrder(
            sharedOrder: ["hidden": ["a"]],
            legacyOrder: nil,
            legacyAssignment: ["c": "hidden"]
        )

        XCTAssertEqual(order[.hidden], ["a", "c"])
    }

    @MainActor
    func testLoadOrderMigratesLegacyKeysIntoSharedOrder() {
        let suiteName = "ThawTests.MenuBarSectionControllerMigration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(["hidden": ["a", "b"]], forKey: "Thaw.simpleSectionOrder")

        let order = MenuBarSectionController.loadOrder(defaults: defaults)

        XCTAssertEqual(order[.hidden], ["a", "b"])
        XCTAssertEqual(
            defaults.dictionary(forKey: "MenuBarItemManager.savedSectionOrder") as? [String: [String]],
            ["hidden": ["a", "b"]]
        )
        XCTAssertNil(defaults.object(forKey: "Thaw.simpleSectionOrder"))
        XCTAssertNil(defaults.object(forKey: "Thaw.simpleSectionAssignment"))
    }

    @MainActor
    func testLoadOrderMigratesLegacyHiddenKeyAndRemovesIt() {
        let suiteName = "ThawTests.MenuBarSectionControllerLegacyHidden.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(
            ["com.example.app::item1", "com.example.app::item2"],
            forKey: "Thaw.simpleHiddenItemIdentifiers"
        )

        let order = MenuBarSectionController.loadOrder(defaults: defaults)

        XCTAssertEqual(order[.hidden]?.count, 2)
        XCTAssertNil(defaults.object(forKey: "Thaw.simpleHiddenItemIdentifiers"))
    }

    @MainActor
    func testMacOS27RelocationUsesAXBoundsForSyntheticWindowID() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 AX bounds are OS-specific")
        }

        let bounds = CGRect(x: 120, y: 0, width: 42, height: 24)
        // Assertion backend (macOS 27): AX bounds are the source of truth.
        XCTAssertEqual(
            RuntimeMenuBarBackend().relocationBounds(
                itemBounds: bounds,
                windowServerBounds: nil
            ),
            bounds
        )
        // Legacy backend trusts the WindowServer geometry, which is nil here.
        XCTAssertNil(
            HostMenuBarBackend().relocationBounds(
                itemBounds: bounds,
                windowServerBounds: nil
            )
        )
    }

    @MainActor
    func testLayoutItemsForPersistenceIncludesVisibleThawControl() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 layout dragging is OS-specific")
        }

        let alpha = item(
            tag: .appItem(bundleID: "com.example.alpha", title: "Alpha", windowID: 1600),
            x: 100,
            windowID: 1600
        )
        let thaw = item(tag: .visibleControlItem, x: 140, windowID: 1601)
        let hiddenDivider = item(tag: .hiddenControlItem, x: 80, windowID: 1602)

        let views: [LayoutBarArrangedView] = [
            TestLayoutArrangedView(item: alpha),
            TestLayoutArrangedView(item: thaw),
            TestLayoutArrangedView(item: hiddenDivider),
        ]

        let ordered = LayoutBarPaddingView.layoutItemsForPersistence(from: views)

        XCTAssertEqual(ordered.map(\.uniqueIdentifier), [alpha.uniqueIdentifier, thaw.uniqueIdentifier])
    }

    @MainActor
    func testLayoutDragAcceptsVisibleThawControlButRejectsDividerControl() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 layout dragging is OS-specific")
        }

        let visibleControl = item(
            tag: .visibleControlItem,
            x: 120,
            windowID: 1500
        )
        let hiddenControl = item(
            tag: .hiddenControlItem,
            x: 80,
            windowID: 1501
        )

        XCTAssertTrue(LayoutBarPaddingView.acceptsLayoutDrag(of: visibleControl))
        XCTAssertFalse(LayoutBarPaddingView.acceptsLayoutDrag(of: hiddenControl))
    }

    @MainActor
    func testMacOS27VisibleThawControlGetsAchievableReorderDestination() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 layout dragging is OS-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 100, windowID: 1520)
        let thaw = item(tag: .visibleControlItem, x: 140, windowID: 1521)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 180, windowID: 1522)

        let destination = RuntimeLayoutCoordinator.achievableDestination(
            items: [alpha, thaw, beta],
            item: thaw,
            desiredOrder: [thaw.uniqueIdentifier, alpha.uniqueIdentifier, beta.uniqueIdentifier]
        )

        guard case let .leftOfItem(target) = destination else {
            return XCTFail("expected Thaw to move left of Alpha")
        }
        XCTAssertEqual(target.uniqueIdentifier, alpha.uniqueIdentifier)
    }

    @MainActor
    func testMacOS27VisibleThawControlRestoreMoveUsesSavedOrder() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("macOS 27 layout dragging is OS-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 100, windowID: 1530)
        let thaw = item(tag: .visibleControlItem, x: 140, windowID: 1531)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 180, windowID: 1532)

        let plannedMove = RuntimeLayoutCoordinator.visibleControlRestoreMove(
            items: [alpha, thaw, beta],
            desiredOrder: [thaw.uniqueIdentifier, alpha.uniqueIdentifier, beta.uniqueIdentifier]
        )

        XCTAssertEqual(plannedMove?.item.uniqueIdentifier, thaw.uniqueIdentifier)
        guard case let .leftOfItem(target) = plannedMove?.destination else {
            return XCTFail("expected Thaw control to move left of Alpha")
        }
        XCTAssertEqual(target.uniqueIdentifier, alpha.uniqueIdentifier)
    }

    @MainActor
    func testStructuralVisibleSegmentInsertsThawControlAtSavedSlot() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 100, windowID: 1630)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 140, windowID: 1631)
        let thaw = item(tag: .visibleControlItem, x: 180, windowID: 1632)

        let segment = MenuBarItemManager.structuralVisibleSegment(
            ordinaryVisibleItems: [alpha, beta],
            visibleControl: thaw,
            savedOrder: [
                thaw.uniqueIdentifier,
                alpha.uniqueIdentifier,
                beta.uniqueIdentifier,
            ]
        )

        XCTAssertEqual(
            segment.map(\.uniqueIdentifier),
            [thaw.uniqueIdentifier, alpha.uniqueIdentifier, beta.uniqueIdentifier]
        )
    }

    @MainActor
    func testStructuralVisibleSegmentKeepsLiveMidXWhenSavedOrderOmitsThawControl() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 100, windowID: 1640)
        let thaw = item(tag: .visibleControlItem, x: 140, windowID: 1642)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 180, windowID: 1641)

        let segment = MenuBarItemManager.structuralVisibleSegment(
            ordinaryVisibleItems: [alpha, beta],
            visibleControl: thaw,
            savedOrder: [alpha.uniqueIdentifier, beta.uniqueIdentifier]
        )

        // Omitted from saved order must not append last — preserve live geometry.
        XCTAssertEqual(
            segment.map(\.uniqueIdentifier),
            [alpha.uniqueIdentifier, thaw.uniqueIdentifier, beta.uniqueIdentifier]
        )
    }

    @MainActor
    func testStructuralVisibleSegmentKeepsLiveMidXWhenSavedOrderIsEmpty() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 100, windowID: 1650)
        let thaw = item(tag: .visibleControlItem, x: 120, windowID: 1651)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 180, windowID: 1652)

        let segment = MenuBarItemManager.structuralVisibleSegment(
            ordinaryVisibleItems: [alpha, beta],
            visibleControl: thaw,
            savedOrder: []
        )

        XCTAssertEqual(
            segment.map(\.uniqueIdentifier),
            [alpha.uniqueIdentifier, thaw.uniqueIdentifier, beta.uniqueIdentifier]
        )
    }

    @MainActor
    func testStructuralVisibleSegmentKeepsLiveOrderForNewForcedVisibleItems() {
        let sound = item(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Sound"),
            x: 100,
            windowID: 1660
        )
        let thaw = item(tag: .visibleControlItem, x: 140, windowID: 1661)
        let display = item(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Display"),
            x: 180,
            windowID: 1662
        )

        let segment = MenuBarItemManager.structuralVisibleSegment(
            ordinaryVisibleItems: [sound, display],
            visibleControl: thaw,
            savedOrder: [thaw.uniqueIdentifier]
        )

        XCTAssertEqual(
            segment.map(\.uniqueIdentifier),
            [sound.uniqueIdentifier, display.uniqueIdentifier, thaw.uniqueIdentifier]
        )
    }

    @available(macOS 27, *)
    @MainActor
    func testMacOS27VisibleThawControlRestoreMoveWhenStrandedAtBlockedPosition() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 100, windowID: 1540)
        let thaw = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 1541,
            bounds: CGRect(x: -1, y: 1413, width: 35, height: 24)
        )
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 180, windowID: 1542)
        let items = [alpha, thaw, beta]
        let desiredOrder = [thaw.uniqueIdentifier, alpha.uniqueIdentifier, beta.uniqueIdentifier]

        XCTAssertTrue(RuntimeLayoutCoordinator.visibleControlIsStranded(thaw, among: items))

        let plannedMove = RuntimeLayoutCoordinator.visibleControlRestoreMove(
            items: items,
            desiredOrder: desiredOrder
        )

        XCTAssertEqual(plannedMove?.item.uniqueIdentifier, thaw.uniqueIdentifier)
        guard case let .leftOfItem(target) = plannedMove?.destination else {
            return XCTFail("expected stranded Thaw control to recover left of Alpha")
        }
        XCTAssertEqual(target.uniqueIdentifier, alpha.uniqueIdentifier)
    }

    @MainActor
    func testAssigningLiveItemToHiddenRetainsImmediateSnapshot() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController snapshots are macOS 27-specific")
        }

        let shottr = appItem(
            bundleID: "cc.ffitch.shottr",
            title: "Item-0",
            x: 120,
            windowID: 1519
        )

        let snapshots = MenuBarSectionController.updatedSnapshots(
            [:],
            afterAssigning: shottr,
            to: .hidden
        )

        XCTAssertEqual(snapshots[shottr.uniqueIdentifier]?.tag, shottr.tag)
        XCTAssertEqual(snapshots[shottr.uniqueIdentifier]?.bounds, shottr.bounds)
    }

    @MainActor
    func testVisibleOrderingUsesLiveOrderForMenuBarAgentItems() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 10)
        let wifi = systemItem(title: "WiFi", x: 24, windowID: 11)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 12)
        let gamma = appItem(bundleID: "com.example.gamma", title: "Gamma", x: 72, windowID: 13)

        let ordered = MenuBarSectionController.orderedItems(
            [alpha, wifi, beta, gamma],
            in: .visible,
            using: [gamma.uniqueIdentifier, beta.uniqueIdentifier, alpha.uniqueIdentifier]
        )

        XCTAssertEqual(
            ordered.map(\.uniqueIdentifier),
            [alpha.uniqueIdentifier, wifi.uniqueIdentifier, beta.uniqueIdentifier, gamma.uniqueIdentifier]
        )
    }

    @MainActor
    func testOverflowAfterVisibleDropKeepsDroppedItemAndEjectsPreviousEdgeItem() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent overflow ordering is macOS 27-specific")
        }

        // MenuBarAgent initially publishes the freshly revealed item at the
        // application-menu edge. The layout editor has already persisted the
        // user's intended order with that item at the Control Center end.
        let dropped = appItem(bundleID: "com.example.dropped", title: "Dropped", x: 0, windowID: 30)
        let previousEdge = appItem(bundleID: "com.example.edge", title: "Edge", x: 24, windowID: 31)
        let keeper = appItem(bundleID: "com.example.keeper", title: "Keeper", x: 48, windowID: 32)
        let intendedOrder = [previousEdge.uniqueIdentifier, keeper.uniqueIdentifier, dropped.uniqueIdentifier]

        let ordered = MenuBarSectionController.overflowOrderedVisibleItems(
            [dropped, previousEdge, keeper],
            using: intendedOrder
        )
        let hiddenControlUID = "thaw:HiddenControlItem"
        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: ordered.map(\.uniqueIdentifier) + [hiddenControlUID],
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: nil, hidden: hiddenControlUID, alwaysHidden: nil),
            sectionMap: Dictionary(uniqueKeysWithValues: ordered.map {
                ($0.uniqueIdentifier, MenuBarSection.Name.visible.rawValue)
            }),
            uidWidths: Dictionary(uniqueKeysWithValues: ordered.map { ($0.uniqueIdentifier, 24) }),
            availableWidth: 48
        )

        XCTAssertEqual(ordered.map(\.uniqueIdentifier), intendedOrder)
        XCTAssertEqual(result.overflowUIDs, [previousEdge.uniqueIdentifier])
        XCTAssertFalse(result.overflowUIDs.contains(dropped.uniqueIdentifier))
    }

    @MainActor
    func testVisibleOrderingKeepsMenuBarAgentItemsInLiveOrderWithoutSavedOrder() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 110)
        let wifi = systemItem(title: "WiFi", x: 24, windowID: 111)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 112)

        let ordered = MenuBarSectionController.orderedItems(
            [alpha, wifi, beta],
            in: .visible,
            using: []
        )

        XCTAssertEqual(
            ordered.map(\.uniqueIdentifier),
            [alpha.uniqueIdentifier, wifi.uniqueIdentifier, beta.uniqueIdentifier]
        )
    }

    @MainActor
    func testVisibleOrderingKeepsMixedAppleAndAppItemsInLiveOrder() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 14)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 24, windowID: 15)
        let wifi = systemItem(title: "WiFi", x: 48, windowID: 16)
        let gamma = appItem(bundleID: "com.example.gamma", title: "Gamma", x: 72, windowID: 17)
        let delta = appItem(bundleID: "com.example.delta", title: "Delta", x: 96, windowID: 18)
        let controlCenter = systemItem(title: "BentoBox-0", x: 120, windowID: 19)
        let unknownModule = systemItem(title: "Item-0", x: 144, windowID: 20)

        let ordered = MenuBarSectionController.orderedItems(
            [alpha, beta, wifi, gamma, delta, controlCenter, unknownModule],
            in: .visible,
            using: [
                delta.uniqueIdentifier,
                gamma.uniqueIdentifier,
                unknownModule.uniqueIdentifier,
                controlCenter.uniqueIdentifier,
                wifi.uniqueIdentifier,
                beta.uniqueIdentifier,
                alpha.uniqueIdentifier,
            ]
        )

        XCTAssertEqual(
            ordered.map(\.uniqueIdentifier),
            [
                alpha.uniqueIdentifier,
                beta.uniqueIdentifier,
                wifi.uniqueIdentifier,
                gamma.uniqueIdentifier,
                delta.uniqueIdentifier,
                controlCenter.uniqueIdentifier,
                unknownModule.uniqueIdentifier,
            ]
        )
    }

    @MainActor
    func testVisibleOrderingIgnoresStaleSystemOrderEntries() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 20)
        let clock = systemItem(title: "Clock", x: 24, windowID: 21)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 22)

        let ordered = MenuBarSectionController.orderedItems(
            [alpha, clock, beta],
            in: .visible,
            using: [clock.uniqueIdentifier, beta.uniqueIdentifier, alpha.uniqueIdentifier]
        )

        XCTAssertEqual(
            ordered.map(\.uniqueIdentifier),
            [alpha.uniqueIdentifier, clock.uniqueIdentifier, beta.uniqueIdentifier]
        )
    }

    @MainActor
    func testHiddenOrderingMovesAnchoredSystemItemsToTrail() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let shottr = appItem(bundleID: "cc.ffitch.shottr", title: "Item-0", x: 0, windowID: 30)
        let raycast = appItem(bundleID: "com.raycast-x.macos", title: "Item-0", x: 24, windowID: 31)
        let controlCenter = systemItem(title: "com.apple.menuextra.controlcenter", x: 48, windowID: 32)
        let siri = systemItem(title: "Siri", x: 72, windowID: 33)
        let codex = appItem(bundleID: "com.steipete.codexbar", title: "CodexBar.StatusItem", x: 96, windowID: 34)
        let clock = systemItem(title: "com.apple.menuextra.clock", x: 120, windowID: 35)
        let proton = appItem(bundleID: "ch.protonmail.drive", title: "Proton Drive", x: 144, windowID: 36)

        // Persisted order intersperses system items with third-party items
        // (as can happen via profile import or cold-start migration).
        let persistedOrder = [
            shottr.uniqueIdentifier,
            raycast.uniqueIdentifier,
            controlCenter.uniqueIdentifier,
            siri.uniqueIdentifier,
            codex.uniqueIdentifier,
            clock.uniqueIdentifier,
            proton.uniqueIdentifier,
        ]

        let ordered = MenuBarSectionController.orderedItems(
            [shottr, raycast, controlCenter, siri, codex, clock, proton],
            in: .hidden,
            using: persistedOrder
        )

        // Third-party items keep their persisted relative order;
        // anchored system items sort to the trailing edge by canonical rank
        // (ControlCenter < Siri < Clock).
        XCTAssertEqual(
            ordered.map(\.uniqueIdentifier),
            [
                shottr.uniqueIdentifier,
                raycast.uniqueIdentifier,
                codex.uniqueIdentifier,
                proton.uniqueIdentifier,
                controlCenter.uniqueIdentifier,
                siri.uniqueIdentifier,
                clock.uniqueIdentifier,
            ]
        )
    }

    @MainActor
    func testHiddenOrderingMovesAnchoredSystemItemsToTrailWithoutSavedOrder() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let shottr = appItem(bundleID: "cc.ffitch.shottr", title: "Item-0", x: 0, windowID: 40)
        let controlCenter = systemItem(title: "com.apple.menuextra.controlcenter", x: 24, windowID: 41)
        let clock = systemItem(title: "com.apple.menuextra.clock", x: 48, windowID: 42)

        // No persisted order — items arrive in AX enumeration order with
        // system items interspersed.
        let ordered = MenuBarSectionController.orderedItems(
            [shottr, controlCenter, clock],
            in: .hidden,
            using: []
        )

        XCTAssertEqual(
            ordered.map(\.uniqueIdentifier),
            [
                shottr.uniqueIdentifier,
                controlCenter.uniqueIdentifier,
                clock.uniqueIdentifier,
            ]
        )
    }

    @MainActor
    func testPersistableVisibleOrderExcludesAnchoredSystemItems() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent anchoring is macOS 27-specific")
        }

        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 30)
        let clock = systemItem(title: "Clock", x: 24, windowID: 31)
        let unknownModule = systemItem(title: "Item-0", x: 36, windowID: 33)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 32)

        let identifiers = MenuBarSectionController.persistableOrderIdentifiers(
            from: [alpha, clock, unknownModule, beta],
            in: .visible
        )

        XCTAssertEqual(identifiers, [alpha.uniqueIdentifier, unknownModule.uniqueIdentifier, beta.uniqueIdentifier])
    }

    @MainActor
    func testTemporaryHiddenRevealKeepsAlwaysHiddenConcealed() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController reveal is macOS 27-specific")
        }

        let assignment: [String: MenuBarSection.Name] = [
            "com.example.hidden:Hidden": .hidden,
            "com.example.always:Always": .alwaysHidden,
        ]

        let effective = MenuBarSectionController.effectiveSectionAssignment(
            assignment,
            revealing: .hidden
        )

        XCTAssertEqual(effective, ["com.example.always:Always": .alwaysHidden])
    }

    @MainActor
    func testTemporarySingleItemRevealExcludesOnlyThatItem() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController reveal is macOS 27-specific")
        }

        let assignment: [String: MenuBarSection.Name] = [
            "com.example.alpha:Alpha": .hidden,
            "com.example.beta:Beta": .hidden,
            "com.example.always:Always": .alwaysHidden,
        ]

        let effective = MenuBarSectionController.effectiveSectionAssignment(
            assignment,
            revealing: nil,
            temporarilyRevealedIDs: ["com.example.alpha:Alpha"]
        )

        XCTAssertEqual(
            effective,
            [
                "com.example.beta:Beta": .hidden,
                "com.example.always:Always": .alwaysHidden,
            ]
        )
    }

    @MainActor
    func testTemporaryAlwaysHiddenRevealAllowsAllAssignedItems() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController reveal is macOS 27-specific")
        }

        let assignment: [String: MenuBarSection.Name] = [
            "com.example.hidden:Hidden": .hidden,
            "com.example.always:Always": .alwaysHidden,
        ]

        let effective = MenuBarSectionController.effectiveSectionAssignment(
            assignment,
            revealing: .alwaysHidden
        )

        XCTAssertTrue(effective.isEmpty)
    }

    @MainActor
    func testEffectiveAssignmentDropsThawOwnedEntries() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController reveal is macOS 27-specific")
        }

        let thawID = "\(Constants.bundleIdentifier):Thaw.ControlItem.Visible"
        let hostThawID = "\(Constants.bundleIdentifier).MenuBarHost:Thaw.ControlItem.Visible"
        let genericThawID = "\(Constants.bundleIdentifier):Item-0"
        let assignment: [String: MenuBarSection.Name] = [
            thawID: .alwaysHidden,
            hostThawID: .hidden,
            genericThawID: .hidden,
            "com.example.hidden:Hidden": .hidden,
        ]

        let effective = MenuBarSectionController.effectiveSectionAssignment(
            assignment,
            revealing: nil
        )

        XCTAssertEqual(effective, ["com.example.hidden:Hidden": .hidden])
    }

    @MainActor
    func testPersistableVisibleOrderIncludesVisibleControlButExcludesOtherThawOwnedItems() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController reveal is macOS 27-specific")
        }

        let thaw = item(
            tag: MenuBarItemTag(namespace: .thaw, title: "Thaw.ControlItem.Visible", windowID: 90),
            x: 0,
            windowID: 90
        )
        let hostThaw = item(
            tag: MenuBarItemTag(namespace: .string("\(Constants.bundleIdentifier).MenuBarHost"), title: "Thaw.ControlItem.Visible", windowID: 91),
            x: 24,
            windowID: 91
        )
        let app = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 48, windowID: 92)

        let identifiers = MenuBarSectionController.persistableOrderIdentifiers(
            from: [thaw, hostThaw, app],
            in: .visible
        )

        XCTAssertEqual(identifiers, [thaw.uniqueIdentifier, app.uniqueIdentifier])

        let hiddenIdentifiers = MenuBarSectionController.persistableOrderIdentifiers(
            from: [thaw, hostThaw, app],
            in: .hidden
        )

        XCTAssertEqual(hiddenIdentifiers, [app.uniqueIdentifier])
    }

    @MainActor
    func testExperimentalSystemItemHidingPersistsHiddenSystemItemOrder() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController order persistence is macOS 27-specific")
        }

        let clock = systemItem(title: "Clock", x: 24, windowID: 93)
        let app = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 48, windowID: 94)

        XCTAssertEqual(
            MenuBarSectionController.persistableOrderIdentifiers(
                from: [clock, app],
                in: .hidden
            ),
            [app.uniqueIdentifier]
        )
        XCTAssertEqual(
            MenuBarSectionController.persistableOrderIdentifiers(
                from: [clock, app],
                in: .hidden,
                experimentalSystemItemHiding: true
            ),
            [clock.uniqueIdentifier, app.uniqueIdentifier]
        )
    }

    @MainActor
    func testGenericThawItemIsProtectedFromAssignmentHiding() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController protection is macOS 27-specific")
        }

        let genericThaw = item(
            tag: MenuBarItemTag(namespace: .thaw, title: "Item-0", windowID: 94),
            x: 0,
            windowID: 94
        )
        let hostThaw = item(
            tag: MenuBarItemTag(namespace: .string("\(Constants.bundleIdentifier).MenuBarHost"), title: "Thaw.ControlItem.Visible", windowID: 95),
            x: 24,
            windowID: 95
        )
        let app = appItem(bundleID: "com.example.alpha", title: "Item-0", x: 48, windowID: 96)

        XCTAssertTrue(MenuBarSectionController.isProtectedAssignmentItem(genericThaw))
        XCTAssertTrue(MenuBarSectionController.isProtectedAssignmentItem(hostThaw))
        XCTAssertFalse(MenuBarSectionController.isProtectedAssignmentItem(app))
    }

    @MainActor
    func testExperimentalSystemItemHidingAllowsForcedVisibleSystemItems() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController protection is macOS 27-specific")
        }

        let clock = systemItem(title: "Clock", x: 24, windowID: 97)
        let siri = item(
            tag: MenuBarItemTag(namespace: .systemUIServer, title: "Siri", windowID: 98),
            x: 48,
            windowID: 98
        )

        XCTAssertFalse(clock.isMovable)
        XCTAssertFalse(clock.canBeHidden)
        XCTAssertTrue(clock.isMovable(experimentalSystemItemHiding: true))
        XCTAssertTrue(clock.isPhysicallyOrderable(experimentalSystemItemHiding: true))
        XCTAssertTrue(siri.isMovable(experimentalSystemItemHiding: true))
        XCTAssertFalse(siri.isPhysicallyOrderable(experimentalSystemItemHiding: true))
        // The experimental toggle is what makes MenuBarAgent children hideable
        // at all — Clock and Control Center are exactly the items the "hide
        // native macOS items" setting exists to reach. With the toggle off they
        // stay pinned to Visible. Legacy SystemUIServer Siri behaves the same.
        XCTAssertFalse(clock.canBeHidden(experimentalSystemItemHiding: false))
        XCTAssertTrue(clock.canBeHidden(experimentalSystemItemHiding: true))
        XCTAssertTrue(siri.canBeHidden(experimentalSystemItemHiding: true))
        XCTAssertFalse(MenuBarSectionController.canAssign(clock, to: .hidden, experimentalSystemItemHiding: false))
        XCTAssertTrue(MenuBarSectionController.canAssign(clock, to: .hidden, experimentalSystemItemHiding: true))
        XCTAssertFalse(MenuBarSectionController.canAssign(siri, to: .hidden, experimentalSystemItemHiding: false))
        XCTAssertTrue(MenuBarSectionController.canAssign(siri, to: .hidden, experimentalSystemItemHiding: true))
        XCTAssertTrue(MenuBarSectionController.isProtectedAssignmentItem(clock, experimentalSystemItemHiding: false))
        XCTAssertFalse(MenuBarSectionController.isProtectedAssignmentItem(clock, experimentalSystemItemHiding: true))

        XCTAssertFalse(
            MenuBarSectionController.isProtectedAssignmentItem(siri, experimentalSystemItemHiding: true),
            siri.logString
        )
        let controlCenter = systemItem(title: "BentoBox-0", x: 72, windowID: 100)
        XCTAssertTrue(MenuBarSectionController.canAssign(controlCenter, to: .hidden, experimentalSystemItemHiding: true))
        XCTAssertFalse(MenuBarSectionController.isProtectedAssignmentItem(controlCenter, experimentalSystemItemHiding: true))

        // With the toggle on, every one of these assignments is valid and must
        // survive cleanup; with it off, all three are stripped from Hidden.
        let assignment = [
            clock.uniqueIdentifier: MenuBarSection.Name.hidden,
            siri.uniqueIdentifier: .hidden,
            controlCenter.uniqueIdentifier: .hidden,
        ]
        XCTAssertEqual(
            MenuBarSectionController.invalidAssignmentIdentifiers(
                sectionAssignment: assignment,
                liveItems: [clock, siri, controlCenter],
                experimentalSystemItemHiding: true
            ),
            []
        )
        XCTAssertEqual(
            MenuBarSectionController.invalidAssignmentIdentifiers(
                sectionAssignment: assignment,
                liveItems: [clock, siri, controlCenter],
                experimentalSystemItemHiding: false
            ),
            Set(assignment.keys)
        )

        let hiddenDivider = item(tag: .hiddenControlItem, x: 0, windowID: 99)
        XCTAssertTrue(hiddenDivider.tag.matchesSectionBoundaryControlItem)
        XCTAssertFalse(hiddenDivider.isPhysicallyOrderable(experimentalSystemItemHiding: false))
        XCTAssertFalse(hiddenDivider.isPhysicallyOrderable(experimentalSystemItemHiding: true))
    }

    @MainActor
    func testAssessmentModeProtectedBundlesIncludeThawOwnedHosts() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Assessment Mode hiding is macOS 27-specific")
        }

        XCTAssertTrue(RuntimeSessionController.protectedBundleIDs.contains(Constants.bundleIdentifier))
        XCTAssertTrue(RuntimeSessionController.protectedBundleIDs.contains("\(Constants.bundleIdentifier).MenuBarHost"))
    }

    @MainActor
    func testAssessmentModeCanBundleConcealsSystemUIServer() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Assessment Mode hiding is macOS 27-specific")
        }

        // systemuiserver is intentionally NOT in the system-host guard set on
        // macOS 27: it only hosts Siri (no MBSystemItemIdentifier entry), so
        // bundle-level concealment is the only available path. The
        // bundlesWithVisibleItem guard prevents collateral if a sibling ever appears.
        XCTAssertFalse(RuntimeSessionController.isSystemHostBundleID("com.apple.systemuiserver"))
        XCTAssertTrue(RuntimeSessionController.isSystemHostBundleID("com.apple.MenuBarAgent"))
        XCTAssertTrue(RuntimeSessionController.isSystemHostBundleID("com.apple.controlcenter"))
    }

    @MainActor
    func testAssessmentModeAllowedSystemItemsAreCoreRange() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Assessment Mode hiding is macOS 27-specific")
        }

        // MBSystemItemIdentifier has exactly 9 cases (raw values 0...8); the
        // restriction must allow exactly those to keep the core system controls.
        XCTAssertEqual(RuntimeSessionController.allowedSystemItems.map(\.intValue), Array(0 ... 8))
    }

    @MainActor
    func testAssessmentModeSystemItemIdentifierMapping() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Assessment Mode hiding is macOS 27-specific")
        }

        XCTAssertEqual(RuntimeSessionController.systemItemIdentifier(for: systemItem(title: "Clock", x: 24, windowID: 99).tag), 2)
        XCTAssertEqual(RuntimeSessionController.systemItemIdentifier(for: systemItem(title: "BentoBox-0", x: 48, windowID: 100).tag), 8)
        XCTAssertNil(RuntimeSessionController.systemItemIdentifier(for: appItem(bundleID: "com.example.alpha", title: "Alpha", x: 72, windowID: 101).tag))
    }

    @MainActor
    func testAXProviderMapsThawOwnedHostsToThawNamespace() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Menu bar AX provider is macOS 27-specific")
        }

        XCTAssertEqual(
            MenuBarItemAXProvider.namespace(forBundleIdentifier: Constants.bundleIdentifier),
            .thaw
        )
        XCTAssertEqual(
            MenuBarItemAXProvider.namespace(forBundleIdentifier: "\(Constants.bundleIdentifier).MenuBarHost"),
            .thaw
        )
    }

    @MainActor
    func testTemporaryRevealHiddenStateMatchesSectionControls() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarSectionController reveal is macOS 27-specific")
        }

        XCTAssertTrue(MenuBarSectionController.isSectionHidden(.visible, revealedSection: nil))
        XCTAssertTrue(MenuBarSectionController.isSectionHidden(.hidden, revealedSection: nil))
        XCTAssertTrue(MenuBarSectionController.isSectionHidden(.alwaysHidden, revealedSection: nil))

        XCTAssertFalse(MenuBarSectionController.isSectionHidden(.visible, revealedSection: .hidden))
        XCTAssertFalse(MenuBarSectionController.isSectionHidden(.hidden, revealedSection: .hidden))
        XCTAssertTrue(MenuBarSectionController.isSectionHidden(.alwaysHidden, revealedSection: .hidden))

        XCTAssertFalse(MenuBarSectionController.isSectionHidden(.visible, revealedSection: .alwaysHidden))
        XCTAssertFalse(MenuBarSectionController.isSectionHidden(.hidden, revealedSection: .alwaysHidden))
        XCTAssertFalse(MenuBarSectionController.isSectionHidden(.alwaysHidden, revealedSection: .alwaysHidden))
    }

    @MainActor
    func testSectionAssignmentSanitizerDropsThawControlItems() {
        let visibleControlID = "\(MenuBarItemTag.Namespace.thaw):\(ControlItem.Identifier.visible.rawValue)"
        let hiddenControlID = "\(MenuBarItemTag.Namespace.thaw):\(ControlItem.Identifier.hidden.rawValue)"
        let hostVisibleControlID = "\(Constants.bundleIdentifier).MenuBarHost:\(ControlItem.Identifier.visible.rawValue)"
        let genericThawID = "\(MenuBarItemTag.Namespace.thaw):Item-0"
        let hostGenericThawID = "\(Constants.bundleIdentifier).MenuBarHost:Item-0"
        let rawVisibleControlID = ControlItem.Identifier.visible.rawValue
        let appID = "com.example.alpha:Alpha"
        let visibleAppID = "com.example.beta:Beta"

        let sanitized = MenuBarSectionController.sanitizedSectionAssignment([
            appID: .hidden,
            hiddenControlID: .alwaysHidden,
            genericThawID: .hidden,
            hostGenericThawID: .hidden,
            hostVisibleControlID: .hidden,
            rawVisibleControlID: .hidden,
            visibleAppID: .visible,
            visibleControlID: .hidden,
        ])

        XCTAssertEqual(sanitized, [appID: .hidden])
    }

    @MainActor
    func testAssignmentFromProfileLayoutUsesSectionMapAndFallsBackToOrder() {
        let hiddenApp = "com.example.alpha:Alpha"
        let visibleApp = "com.example.beta:Beta"
        let alwaysHiddenApp = "com.example.gamma:Gamma"
        let thawControl = "\(MenuBarItemTag.Namespace.thaw):\(ControlItem.Identifier.hidden.rawValue)"

        let fromMap = MenuBarSectionController.assignment(
            from: [
                hiddenApp: "hidden",
                visibleApp: "visible",
                alwaysHiddenApp: "alwaysHidden",
                thawControl: "hidden",
            ],
            itemOrder: [:]
        )
        XCTAssertEqual(fromMap, [
            hiddenApp: .hidden,
            alwaysHiddenApp: .alwaysHidden,
        ])

        let fromOrder = MenuBarSectionController.assignment(
            from: [:],
            itemOrder: [
                "visible": [visibleApp],
                "hidden": [hiddenApp, thawControl],
            ]
        )
        XCTAssertEqual(fromOrder, [hiddenApp: .hidden])
    }

    func testMacOS27LiveOrderRequiresFreshAXAdjacency() {
        let alphaTag = MenuBarItemTag.appItem(bundleID: "com.example.alpha", title: "Alpha", windowID: 40)
        let betaTag = MenuBarItemTag.appItem(bundleID: "com.example.beta", title: "Beta", windowID: 41)
        let gammaTag = MenuBarItemTag.appItem(bundleID: "com.example.gamma", title: "Gamma", windowID: 42)
        let alpha = item(tag: alphaTag, x: 0, windowID: 40)
        let beta = item(tag: betaTag, x: 24, windowID: 41)
        let gamma = item(tag: gammaTag, x: 48, windowID: 42)

        XCTAssertFalse(
            RuntimeLayoutCoordinator.liveOrderSatisfiesDestination(
                items: [alpha, beta, gamma],
                item: alpha,
                destination: .leftOfItem(gamma)
            )
        )

        let movedBeta = item(tag: betaTag, x: 0, windowID: 41)
        let movedAlpha = item(tag: alphaTag, x: 24, windowID: 40)
        let movedGamma = item(tag: gammaTag, x: 48, windowID: 42)
        XCTAssertTrue(
            RuntimeLayoutCoordinator.liveOrderSatisfiesDestination(
                items: [movedBeta, movedAlpha, movedGamma],
                item: alpha,
                destination: .leftOfItem(gamma)
            )
        )
    }

    func testMacOS27SectionBoundaryRequiresHiddenDividerBetweenSections() {
        let hidden = appItem(
            bundleID: "com.example.hidden",
            title: "Hidden",
            x: 0,
            windowID: 50
        )
        let divider = item(tag: .hiddenControlItem, x: 24, windowID: 51)
        let visible = appItem(
            bundleID: "com.example.visible",
            title: "Visible",
            x: 48,
            windowID: 52
        )
        let controls = MenuBarItemManager.ControlItemPair(
            hidden: divider,
            alwaysHidden: nil
        )
        let orderedItems = [hidden, divider, visible]

        XCTAssertEqual(
            RuntimeLayoutCoordinator.sectionBoundaryDestination(
                for: .hidden,
                controlItems: controls
            ),
            .leftOfItem(divider)
        )
        XCTAssertEqual(
            RuntimeLayoutCoordinator.sectionBoundaryDestination(
                for: .visible,
                controlItems: controls
            ),
            .rightOfItem(divider)
        )

        XCTAssertTrue(
            RuntimeLayoutCoordinator.liveOrderSatisfiesSectionBoundary(
                items: orderedItems,
                item: hidden,
                section: .hidden,
                controlItems: controls
            )
        )
        XCTAssertTrue(
            RuntimeLayoutCoordinator.liveOrderSatisfiesSectionBoundary(
                items: orderedItems,
                item: visible,
                section: .visible,
                controlItems: controls
            )
        )
        XCTAssertFalse(
            RuntimeLayoutCoordinator.liveOrderSatisfiesSectionBoundary(
                items: orderedItems,
                item: visible,
                section: .hidden,
                controlItems: controls
            )
        )
        XCTAssertFalse(
            RuntimeLayoutCoordinator.liveOrderSatisfiesSectionBoundary(
                items: orderedItems,
                item: hidden,
                section: .visible,
                controlItems: controls
            )
        )
    }

    func testMacOS27DividerMovesLeftOfLeftmostVisibleItem() {
        let thaw = item(tag: .visibleControlItem, x: 0, windowID: 60)
        let divider = item(tag: .hiddenControlItem, x: 24, windowID: 61)
        let hidden = appItem(
            bundleID: "com.example.hidden",
            title: "Hidden",
            x: 48,
            windowID: 62
        )
        let controls = MenuBarItemManager.ControlItemPair(
            hidden: divider,
            alwaysHidden: nil
        )

        XCTAssertEqual(
            RuntimeLayoutCoordinator.dividerMoveDestination(
                items: [thaw, divider, hidden],
                sectionAssignment: [hidden.uniqueIdentifier: .hidden],
                controlItems: controls
            ),
            .leftOfItem(thaw)
        )

        let correctlyPlacedDivider = item(
            tag: .hiddenControlItem,
            x: -24,
            windowID: 63
        )
        XCTAssertNil(
            RuntimeLayoutCoordinator.dividerMoveDestination(
                items: [correctlyPlacedDivider, thaw, hidden],
                sectionAssignment: [hidden.uniqueIdentifier: .hidden],
                controlItems: .init(
                    hidden: correctlyPlacedDivider,
                    alwaysHidden: nil
                )
            )
        )
    }

    func testMacOS27AchievableOrderDoesNotCrossFixedAnchors() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 70)
        let clock = item(tag: .clock, x: 24, windowID: 71)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 72)
        let gamma = appItem(bundleID: "com.example.gamma", title: "Gamma", x: 72, windowID: 73)

        let segments = RuntimeLayoutCoordinator.achievableOrderSegments(
            items: [alpha, clock, beta, gamma],
            desiredOrder: [gamma.uniqueIdentifier, beta.uniqueIdentifier, alpha.uniqueIdentifier]
        )

        XCTAssertEqual(
            segments.map { $0.map(\.uniqueIdentifier) },
            [[alpha.uniqueIdentifier], [gamma.uniqueIdentifier, beta.uniqueIdentifier]]
        )
    }

    func testExperimentalSystemItemHidingAllowsOrderAcrossFixedAnchors() throws {
        try XCTSkipUnless(isRunningOnMacOS27OrLater)
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 70)
        let clock = item(tag: .clock, x: 24, windowID: 71)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 72)
        let gamma = appItem(bundleID: "com.example.gamma", title: "Gamma", x: 72, windowID: 73)

        let segments = RuntimeLayoutCoordinator.achievableOrderSegments(
            items: [alpha, clock, beta, gamma],
            desiredOrder: [
                gamma.uniqueIdentifier,
                beta.uniqueIdentifier,
                clock.uniqueIdentifier,
                alpha.uniqueIdentifier,
            ],
            experimentalSystemItemHiding: true
        )

        XCTAssertEqual(
            segments.map { $0.map(\.uniqueIdentifier) },
            [[gamma.uniqueIdentifier, beta.uniqueIdentifier, clock.uniqueIdentifier, alpha.uniqueIdentifier]]
        )
    }

    func testExperimentalSystemItemHidingDoesNotOrderAcrossSystemUIServerAnchor() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 74)
        let siri = item(
            tag: MenuBarItemTag(namespace: .systemUIServer, title: "Siri", windowID: 75),
            x: 24,
            windowID: 75
        )
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 48, windowID: 76)

        let segments = RuntimeLayoutCoordinator.achievableOrderSegments(
            items: [alpha, siri, beta],
            desiredOrder: [
                beta.uniqueIdentifier,
                siri.uniqueIdentifier,
                alpha.uniqueIdentifier,
            ],
            experimentalSystemItemHiding: true
        )

        XCTAssertEqual(
            segments.map { $0.map(\.uniqueIdentifier) },
            [[alpha.uniqueIdentifier], [beta.uniqueIdentifier]]
        )
        XCTAssertNil(
            RuntimeLayoutCoordinator.achievableDestination(
                items: [alpha, siri, beta],
                item: beta,
                desiredOrder: [
                    beta.uniqueIdentifier,
                    siri.uniqueIdentifier,
                    alpha.uniqueIdentifier,
                ],
                experimentalSystemItemHiding: true
            )
        )
    }

    func testAssignmentOnlySystemItemsSkipSectionBoundaryRepair() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 77)
        let siri = item(
            tag: MenuBarItemTag(namespace: .systemUIServer, title: "Siri", windowID: 78),
            x: 24,
            windowID: 78
        )
        let divider = item(tag: .hiddenControlItem, x: 48, windowID: 79)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 72, windowID: 80)
        let controls = MenuBarItemManager.ControlItemPair(hidden: divider, alwaysHidden: nil)

        XCTAssertTrue(
            RuntimeLayoutCoordinator.liveOrderSatisfiesSectionBoundary(
                items: [alpha, siri, beta, divider],
                item: siri,
                section: .hidden,
                controlItems: controls,
                experimentalSystemItemHiding: true
            )
        )
    }

    func testMacOS27ConcealedSectionOrderExcludesNonConcealableSystemItems() {
        let sound = systemItem(
            title: "com.apple.menuextra.sound",
            x: 100,
            windowID: 75
        )
        let network = appItem(
            bundleID: "com.bjango.istatmenus.status",
            title: "Upload #, Download #",
            x: 50,
            windowID: 76
        )

        XCTAssertFalse(RuntimeLayoutCoordinator.isEligibleForSectionOrder(sound, section: .hidden))
        XCTAssertTrue(RuntimeLayoutCoordinator.isEligibleForSectionOrder(network, section: .hidden))
        XCTAssertTrue(RuntimeLayoutCoordinator.isEligibleForSectionOrder(sound, section: .visible))
    }

    func testMacOS27DirectDragTargetsNeighborInsideAnchorSegment() {
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 80)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 24, windowID: 81)
        let clock = item(tag: .clock, x: 48, windowID: 82)
        let gamma = appItem(bundleID: "com.example.gamma", title: "Gamma", x: 72, windowID: 83)

        let destination = RuntimeLayoutCoordinator.achievableDestination(
            items: [alpha, beta, clock, gamma],
            item: alpha,
            desiredOrder: [beta.uniqueIdentifier, gamma.uniqueIdentifier, alpha.uniqueIdentifier]
        )

        XCTAssertEqual(destination, .rightOfItem(beta))
    }

    func testExperimentalSystemItemHidingTargetsAnchorNeighbor() throws {
        try XCTSkipUnless(isRunningOnMacOS27OrLater)
        let alpha = appItem(bundleID: "com.example.alpha", title: "Alpha", x: 0, windowID: 80)
        let beta = appItem(bundleID: "com.example.beta", title: "Beta", x: 24, windowID: 81)
        let clock = item(tag: .clock, x: 48, windowID: 82)
        let gamma = appItem(bundleID: "com.example.gamma", title: "Gamma", x: 72, windowID: 83)

        // With experimental system-item hiding, clock (a layout anchor) is
        // physically orderable — all four items land in one segment. Alpha needs
        // to move from position 0 to between clock and gamma; `achievableDestination`
        // picks the first available right-hand neighbour (.leftOfItem(gamma)).
        let destination = RuntimeLayoutCoordinator.achievableDestination(
            items: [alpha, beta, clock, gamma],
            item: alpha,
            desiredOrder: [
                beta.uniqueIdentifier,
                clock.uniqueIdentifier,
                alpha.uniqueIdentifier,
                gamma.uniqueIdentifier,
            ],
            experimentalSystemItemHiding: true
        )

        XCTAssertEqual(destination, .leftOfItem(gamma))
    }

    func testMacOS27DividerDoesNotPlanAcrossFixedAnchor() {
        let divider = item(tag: .hiddenControlItem, x: 0, windowID: 90)
        let clock = item(tag: .clock, x: 24, windowID: 91)
        let visible = appItem(bundleID: "com.example.visible", title: "Visible", x: 48, windowID: 92)

        XCTAssertNil(
            RuntimeLayoutCoordinator.dividerMoveDestination(
                items: [divider, clock, visible],
                sectionAssignment: [:],
                controlItems: .init(hidden: divider, alwaysHidden: nil)
            )
        )
    }

    private func appItem(
        bundleID: String,
        title: String,
        x: CGFloat,
        windowID: CGWindowID
    ) -> MenuBarItem {
        item(
            tag: .appItem(bundleID: bundleID, title: title, windowID: windowID),
            x: x,
            windowID: windowID
        )
    }

    private func systemItem(
        title: String,
        x: CGFloat,
        windowID: CGWindowID
    ) -> MenuBarItem {
        item(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title, windowID: windowID),
            x: x,
            windowID: windowID
        )
    }

    private func item(
        tag: MenuBarItemTag,
        x: CGFloat,
        windowID: CGWindowID
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: tag,
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 20, height: 22)
        )
    }
}

@MainActor
private final class TestLayoutArrangedView: LayoutBarArrangedView {
    private let itemKind: Kind

    override var kind: Kind {
        itemKind
    }

    init(item: MenuBarItem) {
        self.itemKind = .item(item)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
