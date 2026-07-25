//
//  MenuBarItemTagCodingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - MenuBarItemTag Persistence Key Tests

final class MenuBarItemTagCodingTests: XCTestCase {
    // MARK: - Round-Trip Tests

    func testRoundTripStringNamespace() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 0)

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        XCTAssertEqual(decoded, tag)
    }

    func testRoundTripNullNamespaceDoesNotMatchStringNull() {
        let tag = MenuBarItemTag(namespace: .null, title: "TestItem")

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        XCTAssertEqual(decoded, tag)
        XCTAssertEqual(decoded?.namespace, .null)

        let stringNullTag = MenuBarItemTag(namespace: .string("null"), title: "TestItem")
        XCTAssertNotEqual(decoded, stringNullTag)
    }

    func testRoundTripUUIDNamespaceDoesNotMatchStringUUID() {
        let uuid = UUID()
        let tag = MenuBarItemTag(namespace: .uuid(uuid), title: "TestItem")

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        XCTAssertEqual(decoded, tag)
        XCTAssertEqual(decoded?.namespace, .uuid(uuid))

        let stringUUIDTag = MenuBarItemTag(namespace: .string(uuid.uuidString), title: "TestItem")
        XCTAssertNotEqual(decoded, stringUUIDTag)
    }

    func testRoundTripInstanceIndex() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 3)

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        XCTAssertEqual(decoded, tag)

        let zeroIndexTag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 0)
        XCTAssertNotEqual(decoded, zeroIndexTag)
    }

    func testRoundTripTitleWithColons() {
        let tag = MenuBarItemTag(namespace: .string("com.apple.menuextra"), title: "com.apple.menuextra:Time:Machine")

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        XCTAssertEqual(decoded, tag)
        XCTAssertEqual(decoded?.title, "com.apple.menuextra:Time:Machine")
    }

    // MARK: - Uniqueness Tests

    func testDifferingInstanceIndexProducesDifferentKeys() {
        let tag1 = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 0)
        let tag2 = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", instanceIndex: 1)

        XCTAssertNotEqual(tag1.persistenceKey, tag2.persistenceKey)
    }

    // MARK: - Invalid Input Tests

    func testInvalidPersistenceKeyReturnsNil() {
        XCTAssertNil(MenuBarItemTag(persistenceKey: "garbage"))
        XCTAssertNil(MenuBarItemTag(persistenceKey: ""))
    }

    // MARK: - WindowID Tests

    func testDecodedTagHasNilWindowID() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "TestItem", windowID: 12345)

        let decoded = MenuBarItemTag(persistenceKey: tag.persistenceKey)

        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.windowID)
    }
}
