//
//  MenuBarItemTagTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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

    func testNamespaceHashable() {
        let ns1 = MenuBarItemTag.Namespace.string("com.example.app")
        let ns2 = MenuBarItemTag.Namespace.string("com.example.app")

        XCTAssertEqual(ns1.hashValue, ns2.hashValue)
    }

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
        let tag = MenuBarItemTag(
            namespace: .controlCenter,
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

    func testHashableConsistency() {
        let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item")
        let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item")

        XCTAssertEqual(tag1.hashValue, tag2.hashValue)
    }

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
