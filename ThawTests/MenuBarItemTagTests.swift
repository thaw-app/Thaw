//
//  MenuBarItemTagTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar item tags")
struct MenuBarItemTagTests {
    // MARK: - MenuBarItemTag.Namespace Tests

    @Suite("Namespace")
    struct NamespaceTests {
        // MARK: - Initialization Tests

        @Test("The null namespace reports only isNull")
        func nullNamespace() {
            let namespace = MenuBarItemTag.Namespace.null

            #expect(namespace.isNull)
            #expect(!namespace.isString)
            #expect(!namespace.isUUID)
            #expect(namespace.description == "null")
        }

        @Test("A string namespace reports only isString")
        func stringNamespace() {
            let namespace = MenuBarItemTag.Namespace.string("com.example.app")

            #expect(!namespace.isNull)
            #expect(namespace.isString)
            #expect(!namespace.isUUID)
            #expect(namespace.description == "com.example.app")
        }

        @Test("A UUID namespace reports only isUUID")
        func uuidNamespace() {
            let uuid = UUID()
            let namespace = MenuBarItemTag.Namespace.uuid(uuid)

            #expect(!namespace.isNull)
            #expect(!namespace.isString)
            #expect(namespace.isUUID)
            #expect(namespace.description == uuid.uuidString)
        }

        @Test("optional(_:) with a value builds a string namespace")
        func optionalWithValue() {
            let namespace = MenuBarItemTag.Namespace.optional("com.test.app")

            #expect(namespace.isString)
            #expect(namespace.description == "com.test.app")
        }

        @Test("optional(nil) builds the null namespace")
        func optionalWithNil() {
            let namespace = MenuBarItemTag.Namespace.optional(nil)

            #expect(namespace.isNull)
        }

        // MARK: - Equality Tests

        @Test("String namespaces compare by their string")
        func namespaceEquality() {
            let ns1 = MenuBarItemTag.Namespace.string("com.example.app")
            let ns2 = MenuBarItemTag.Namespace.string("com.example.app")
            let ns3 = MenuBarItemTag.Namespace.string("com.other.app")

            #expect(ns1 == ns2)
            #expect(ns1 != ns3)
        }

        @Test("Null namespaces are equal to each other")
        func nullNamespaceEquality() {
            let ns1 = MenuBarItemTag.Namespace.null
            let ns2 = MenuBarItemTag.Namespace.null

            #expect(ns1 == ns2)
        }

        @Test("UUID namespaces compare by their UUID")
        func uuidNamespaceEquality() {
            let uuid = UUID()
            let ns1 = MenuBarItemTag.Namespace.uuid(uuid)
            let ns2 = MenuBarItemTag.Namespace.uuid(uuid)
            let ns3 = MenuBarItemTag.Namespace.uuid(UUID())

            #expect(ns1 == ns2)
            #expect(ns1 != ns3)
        }

        @Test("Namespaces of different kinds are never equal")
        func differentTypesNotEqual() {
            let stringNs = MenuBarItemTag.Namespace.string("test")
            let nullNs = MenuBarItemTag.Namespace.null

            #expect(stringNs != nullNs)
        }

        // MARK: - Hashable Tests

        @Test("Equal namespaces hash equally")
        func namespaceHashable() {
            let ns1 = MenuBarItemTag.Namespace.string("com.example.app")
            let ns2 = MenuBarItemTag.Namespace.string("com.example.app")

            #expect(ns1.hashValue == ns2.hashValue)
        }

        @Test("A set collapses duplicate namespaces")
        func namespaceInSet() {
            var set = Set<MenuBarItemTag.Namespace>()
            set.insert(.string("com.example.app"))
            set.insert(.string("com.example.app")) // duplicate
            set.insert(.null)

            #expect(set.count == 2)
        }

        // MARK: - Static Constants Tests

        @Test("The Thaw namespace is Thaw's bundle identifier")
        func thawNamespace() {
            let thaw = MenuBarItemTag.Namespace.thaw
            #expect(thaw.isString)
            #expect(thaw.description == Constants.bundleIdentifier)
        }

        @Test("The Control Center namespace is its bundle identifier")
        func controlCenterNamespace() {
            let cc = MenuBarItemTag.Namespace.controlCenter
            #expect(cc.isString)
            #expect(cc.description == "com.apple.controlcenter")
        }

        @Test("The SystemUIServer namespace is its bundle identifier")
        func systemUIServerNamespace() {
            let sys = MenuBarItemTag.Namespace.systemUIServer
            #expect(sys.isString)
            #expect(sys.description == "com.apple.systemuiserver")
        }
    }

    // MARK: - MenuBarItemTag Tests

    @Suite("Tag")
    struct TagTests {
        // MARK: - Initialization Tests

        @Test("A tag keeps its namespace and title and defaults the rest")
        func basicInit() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem"
            )

            #expect(tag.namespace == .string("com.example.app"))
            #expect(tag.title == "TestItem")
            #expect(tag.windowID == nil)
            #expect(tag.instanceIndex == 0)
        }

        @Test("A tag keeps the window ID it was built with")
        func initWithWindowID() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem",
                windowID: 12345
            )

            #expect(tag.windowID == 12345)
        }

        @Test("A tag keeps the instance index it was built with")
        func initWithInstanceIndex() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem",
                instanceIndex: 3
            )

            #expect(tag.instanceIndex == 3)
        }

        // MARK: - Description Tests

        @Test("The description joins namespace and title")
        func descriptionBasic() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem"
            )

            #expect(tag.description == "com.example.app:TestItem")
        }

        @Test("The description carries a non-zero instance index")
        func descriptionWithInstanceIndex() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem",
                instanceIndex: 2
            )

            #expect(tag.description.contains(":2"))
        }

        @Test("An empty title leaves the description as the namespace alone")
        func descriptionWithEmptyTitle() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: ""
            )

            #expect(tag.description == "com.example.app")
        }

        // MARK: - Tag Identifier Tests

        @Test("The tag identifier joins namespace and title")
        func tagIdentifierBasic() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem"
            )

            #expect(tag.tagIdentifier == "com.example.app:TestItem")
        }

        @Test("The tag identifier appends a non-zero instance index")
        func tagIdentifierWithInstanceIndex() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem",
                instanceIndex: 5
            )

            #expect(tag.tagIdentifier == "com.example.app:TestItem:5")
        }

        @Test("The tag identifier omits a zero instance index")
        func tagIdentifierZeroInstanceIndexOmitted() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "TestItem",
                instanceIndex: 0
            )

            #expect(tag.tagIdentifier == "com.example.app:TestItem")
            #expect(!tag.tagIdentifier.hasSuffix(":0"))
        }

        // MARK: - System Item Tests

        @Test("A Control Center item is a system item")
        func isSystemItemForControlCenter() {
            let tag = MenuBarItemTag(
                namespace: .controlCenter,
                title: "SomeItem"
            )

            #expect(tag.isSystemItem)
        }

        @Test("A SystemUIServer item is a system item")
        func isSystemItemForSystemUIServer() {
            let tag = MenuBarItemTag(
                namespace: .systemUIServer,
                title: "SomeItem"
            )

            #expect(tag.isSystemItem)
        }

        @Test("A Thaw item is a system item")
        func isSystemItemForThaw() {
            let tag = MenuBarItemTag(
                namespace: .thaw,
                title: "SomeItem"
            )

            #expect(tag.isSystemItem)
        }

        @Test("A third-party app item is not a system item")
        func isNotSystemItemForThirdPartyApp() {
            let tag = MenuBarItemTag(
                namespace: .string("com.thirdparty.app"),
                title: "SomeItem"
            )

            #expect(!tag.isSystemItem)
        }

        @Test("A UUID-namespaced item is not a system item")
        func isNotSystemItemForUUID() {
            let tag = MenuBarItemTag(
                namespace: .uuid(UUID()),
                title: "SomeItem"
            )

            #expect(!tag.isSystemItem)
        }

        // MARK: - Movable Tests

        @Test("The clock is not movable")
        func clockIsNotMovable() {
            let clock = MenuBarItemTag.clock
            #expect(!clock.isMovable)
        }

        @Test("Control Center is not movable")
        func controlCenterIsNotMovable() {
            let cc = MenuBarItemTag.controlCenter
            #expect(!cc.isMovable)
        }

        @Test("A regular item is movable")
        func regularItemIsMovable() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "RegularItem"
            )

            #expect(tag.isMovable)
        }

        @Test("An unresolved generic Control Center item is not movable")
        func unresolvedGenericControlCenterItemIsNotMovable() {
            let item = MenuBarItem.fixture(
                tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-13"),
                windowID: 13,
                sourcePID: nil
            )

            #expect(!item.isMovable)
        }

        @Test("A resolved generic Control Center item keeps its tag's movability")
        func resolvedGenericControlCenterItemKeepsItsTagMovability() {
            let item = MenuBarItem.fixture(
                tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-13"),
                windowID: 13,
                sourcePID: 1234
            )

            #expect(item.isMovable)
        }

        // MARK: - Can Be Hidden Tests

        @Test("The visible control item cannot be hidden")
        func visibleControlItemCannotBeHidden() {
            let visible = MenuBarItemTag.visibleControlItem
            #expect(!visible.canBeHidden)
        }

        @Test("The audio-video module cannot be hidden")
        func audioVideoModuleCannotBeHidden() {
            let avm = MenuBarItemTag.audioVideoModule
            #expect(!avm.canBeHidden)
        }

        @Test("A regular item can be hidden")
        func regularItemCanBeHidden() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "RegularItem"
            )

            #expect(tag.canBeHidden)
        }

        @Test("A UUID-namespaced audio-video module cannot be hidden")
        func uuidAudioVideoModuleCannotBeHidden() {
            let tag = MenuBarItemTag(
                namespace: .uuid(UUID()),
                title: "AudioVideoModule"
            )

            #expect(!tag.canBeHidden)
        }

        // MARK: - Control Item Tests

        @Test("The hidden control item is a control item")
        func hiddenControlItemIsControlItem() {
            let hidden = MenuBarItemTag.hiddenControlItem
            #expect(hidden.isControlItem)
        }

        @Test("The always-hidden control item is a control item")
        func alwaysHiddenControlItemIsControlItem() {
            let alwaysHidden = MenuBarItemTag.alwaysHiddenControlItem
            #expect(alwaysHidden.isControlItem)
        }

        @Test("The visible control item is a control item")
        func visibleControlItemIsControlItem() {
            let visible = MenuBarItemTag.visibleControlItem
            #expect(visible.isControlItem)
        }

        @Test("A regular item is not a control item")
        func regularItemIsNotControlItem() {
            let tag = MenuBarItemTag(
                namespace: .string("com.example.app"),
                title: "RegularItem"
            )

            #expect(!tag.isControlItem)
        }

        @Test("A spacer is a control item")
        func spacerIsControlItem() {
            let tag = MenuBarItemTag(
                namespace: .thaw,
                title: "Something.Spacer.Item"
            )

            #expect(tag.isControlItem)
        }

        // MARK: - BentoBox Tests

        @Test("A Control Center BentoBox title is detected")
        func bentoBoxDetection() {
            let tag = MenuBarItemTag(
                namespace: .controlCenter,
                title: "BentoBox-0"
            )

            #expect(tag.isBentoBox)
        }

        @Test("A title without the BentoBox prefix is not a BentoBox")
        func bentoBoxWithoutPrefix() {
            let tag = MenuBarItemTag(
                namespace: .controlCenter,
                title: "NotBentoBox"
            )

            #expect(!tag.isBentoBox)
        }

        @Test("A BentoBox title in another namespace is not a BentoBox")
        func bentoBoxWrongNamespace() {
            let tag = MenuBarItemTag(
                namespace: .string("com.other.app"),
                title: "BentoBox-0"
            )

            #expect(!tag.isBentoBox)
        }

        // MARK: - System Clone Tests

        @Test("The clone title marks a UUID-namespaced item as a system clone")
        func isSystemClone() {
            let tag = MenuBarItemTag(
                namespace: .uuid(UUID()),
                title: "System Status Item Clone"
            )

            #expect(tag.isSystemClone)
        }

        @Test("The clone title marks a string-namespaced item as a system clone")
        func isSystemCloneWithStringNamespace() {
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

            #expect(processNamespaceClone.isSystemClone)
            #expect(bundleNamespaceClone.isSystemClone)
        }

        @Test("Another title is not a system clone")
        func isNotSystemCloneWithDifferentTitle() {
            let tag = MenuBarItemTag(
                namespace: .uuid(UUID()),
                title: "RegularItem"
            )

            #expect(!tag.isSystemClone)
        }

        // MARK: - Equality Tests

        @Test("Identical tags are equal")
        func equalityBasic() {
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

            #expect(tag1 == tag2)
        }

        @Test("A different namespace breaks equality")
        func equalityDifferentNamespace() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app1"), title: "Item")
            let tag2 = MenuBarItemTag(namespace: .string("com.app2"), title: "Item")

            #expect(tag1 != tag2)
        }

        @Test("A different title breaks equality")
        func equalityDifferentTitle() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item1")
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item2")

            #expect(tag1 != tag2)
        }

        @Test("A different instance index breaks equality")
        func equalityDifferentInstanceIndex() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 0)
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 1)

            #expect(tag1 != tag2)
        }

        @Test("System items ignore the window ID when comparing")
        func equalitySystemItemIgnoresWindowID() {
            let tag1 = MenuBarItemTag(namespace: .controlCenter, title: "Item", windowID: 100)
            let tag2 = MenuBarItemTag(namespace: .controlCenter, title: "Item", windowID: 200)

            // System items ignore windowID in equality
            #expect(tag1 == tag2)
        }

        @Test("Non-system items compare the window ID")
        func equalityNonSystemItemUsesWindowID() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 100)
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 200)

            // Non-system items consider windowID in equality
            #expect(tag1 != tag2)
        }

        // MARK: - Matches Ignoring Window ID Tests

        @Test("Tags that differ only by window ID match")
        func matchesIgnoringWindowID() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 100)
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", windowID: 200)

            #expect(tag1.matchesIgnoringWindowID(tag2))
        }

        @Test("A different namespace does not match")
        func matchesIgnoringWindowIDDifferentNamespace() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app1"), title: "Item", windowID: 100)
            let tag2 = MenuBarItemTag(namespace: .string("com.app2"), title: "Item", windowID: 100)

            #expect(!tag1.matchesIgnoringWindowID(tag2))
        }

        @Test("A different instance index does not match")
        func matchesIgnoringWindowIDDifferentInstanceIndex() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 0)
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item", instanceIndex: 1)

            #expect(!tag1.matchesIgnoringWindowID(tag2))
        }

        // MARK: - Hashable Tests

        @Test("Equal tags hash equally")
        func hashableConsistency() {
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item")
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item")

            #expect(tag1.hashValue == tag2.hashValue)
        }

        @Test("A set collapses duplicate tags")
        func hashableInSet() {
            var set = Set<MenuBarItemTag>()
            let tag1 = MenuBarItemTag(namespace: .string("com.app"), title: "Item1")
            let tag2 = MenuBarItemTag(namespace: .string("com.app"), title: "Item2")
            let tag3 = MenuBarItemTag(namespace: .string("com.app"), title: "Item1") // duplicate

            set.insert(tag1)
            set.insert(tag2)
            set.insert(tag3)

            #expect(set.count == 2)
        }

        @Test("A tag works as a dictionary key")
        func hashableAsDictionaryKey() {
            var dict = [MenuBarItemTag: String]()
            let tag = MenuBarItemTag(namespace: .string("com.app"), title: "Item")

            dict[tag] = "value"

            #expect(dict[tag] == "value")
        }

        // MARK: - Static Constants Tests

        @Test("The immovable items include the clock")
        func immovableItemsContainsClock() {
            #expect(MenuBarItemTag.immovableItems.contains { $0.title == "Clock" })
        }

        @Test("The non-hideable items include the visible control item")
        func nonHideableItemsContainsVisibleControlItem() {
            #expect(MenuBarItemTag.nonHideableItems.contains { $0 == .visibleControlItem })
        }

        @Test("The control items include the hidden control item")
        func controlItemsContainsHiddenControlItem() {
            #expect(MenuBarItemTag.controlItems.contains(.hiddenControlItem))
        }

        @Test("The control items include the always-hidden control item")
        func controlItemsContainsAlwaysHiddenControlItem() {
            #expect(MenuBarItemTag.controlItems.contains(.alwaysHiddenControlItem))
        }
    }
}
