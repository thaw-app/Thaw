//
//  MenuBarItemTagCodingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - MenuBarItemTag Persistence Key Tests

@Suite("Menu bar item tag persistence keys")
struct MenuBarItemTagCodingTests {
    // MARK: - Round-Trip Tests

    @Test("A string namespace round-trips through its persistence key")
    func roundTripStringNamespace() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 0)

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        #expect(decoded == tag)
    }

    @Test("The null namespace round-trips and stays distinct from the string \"null\"")
    func roundTripNullNamespaceDoesNotMatchStringNull() {
        let tag = MenuBarItemTag(namespace: .null, title: "TestItem")

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        #expect(decoded == tag)
        #expect(decoded?.namespace == .null)

        let stringNullTag = MenuBarItemTag(namespace: .string("null"), title: "TestItem")
        #expect(decoded != stringNullTag)
    }

    @Test("A UUID namespace round-trips and stays distinct from the same string")
    func roundTripUUIDNamespaceDoesNotMatchStringUUID() {
        let uuid = UUID()
        let tag = MenuBarItemTag(namespace: .uuid(uuid), title: "TestItem")

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        #expect(decoded == tag)
        #expect(decoded?.namespace == .uuid(uuid))

        let stringUUIDTag = MenuBarItemTag(namespace: .string(uuid.uuidString), title: "TestItem")
        #expect(decoded != stringUUIDTag)
    }

    @Test("The instance index round-trips")
    func roundTripInstanceIndex() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 3)

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        #expect(decoded == tag)

        let zeroIndexTag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 0)
        #expect(decoded != zeroIndexTag)
    }

    @Test("A title containing colons round-trips intact")
    func roundTripTitleWithColons() {
        let tag = MenuBarItemTag(namespace: .string("com.apple.menuextra"), title: "com.apple.menuextra:Time:Machine")

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        #expect(decoded == tag)
        #expect(decoded?.title == "com.apple.menuextra:Time:Machine")
    }

    // MARK: - Uniqueness Tests

    @Test("Differing instance indexes produce different keys")
    func differingInstanceIndexProducesDifferentKeys() {
        let tag1 = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 0)
        let tag2 = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 1)

        #expect(tag1.persistenceKey != tag2.persistenceKey)
    }

    // MARK: - Invalid Input Tests

    @Test("An invalid persistence key decodes to nil")
    func invalidPersistenceKeyReturnsNil() {
        #expect(MenuBarItemTag(persistenceKey: "garbage") == nil)
        #expect(MenuBarItemTag(persistenceKey: "") == nil)
    }

    /// The three kinds are the stored format. Anything else is from a newer build or
    /// corrupt, and guessing would file the item under the wrong identity.
    @Test(
        "An unknown namespace kind is rejected",
        arguments: ["z:com.example.app:0:Status", "N:com.example.app:0:Status", ":com.example.app:0:Status"]
    )
    func unknownNamespaceKindIsRejected(_ persistenceKey: String) {
        #expect(MenuBarItemTag(persistenceKey: persistenceKey) == nil)
    }

    @Test("A malformed UUID namespace is rejected")
    func malformedUUIDNamespaceIsRejected() {
        #expect(MenuBarItemTag(persistenceKey: "u:not-a-uuid:0:Status") == nil)
    }

    @Test("A non-numeric instance index is rejected")
    func nonNumericInstanceIndexIsRejected() {
        #expect(MenuBarItemTag(persistenceKey: "s:com.example.app:first:Status") == nil)
    }

    // MARK: - WindowID Tests

    @Test("A decoded tag has no window ID")
    func decodedTagHasNilWindowID() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", windowID: 12345)

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        #expect(decoded != nil)
        #expect(decoded?.windowID == nil)
    }
}
