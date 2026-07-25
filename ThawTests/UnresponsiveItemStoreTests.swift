//
//  UnresponsiveItemStoreTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Covers the store's contract: a record survives a relaunch, a success
/// clears it, and an item with no stable identity is never recorded.
///
/// The store writes through to `UserDefaults.standard`, so every test
/// saves and restores the key it touches rather than leaving the running
/// user's domain modified.
@MainActor
final class UnresponsiveItemStoreTests: XCTestCase {
    private var savedValue: Any?

    override func setUp() {
        super.setUp()
        savedValue = Defaults.object(forKey: .unresponsiveMenuBarItems)
        Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
    }

    override func tearDown() {
        if let savedValue {
            Defaults.set(savedValue, forKey: .unresponsiveMenuBarItems)
        } else {
            Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
        }
        savedValue = nil
        super.tearDown()
    }

    private func tag(_ namespace: String, _ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(namespace), title: title)
    }

    func testUnknownItemIsNotUnresponsive() {
        let store = UnresponsiveItemStore()
        XCTAssertFalse(store.isUnresponsive(tag("at.obdev.littlesnitch", "Item-0")))
    }

    func testASingleFailureDoesNotMarkAnItem() {
        let item = tag("at.obdev.littlesnitch", "Item-0")
        let store = UnresponsiveItemStore()
        store.recordFailure(for: item)

        XCTAssertFalse(store.isUnresponsive(item))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }

    func testASecondFailureMarksTheItem() {
        let item = tag("at.obdev.littlesnitch", "Item-0")
        let store = UnresponsiveItemStore()
        store.recordFailure(for: item)
        store.recordFailure(for: item)

        XCTAssertTrue(store.isUnresponsive(item))
    }

    func testASuccessResetsTheProvisionalFailure() {
        // Two failures separated by a success are two unrelated blips, not
        // an owner that never answers.
        let item = tag("at.obdev.littlesnitch", "Item-0")
        let store = UnresponsiveItemStore()
        store.recordFailure(for: item)
        store.recordSuccess(for: item)
        store.recordFailure(for: item)

        XCTAssertFalse(store.isUnresponsive(item))
    }

    func testMarkSurvivesANewStore() {
        let item = tag("at.obdev.littlesnitch", "Item-0")
        let first = UnresponsiveItemStore()
        first.recordFailure(for: item)
        first.recordFailure(for: item)

        // A second instance reads only what was persisted, which is what a
        // relaunch does.
        XCTAssertTrue(UnresponsiveItemStore().isUnresponsive(item))
    }

    func testSuccessClearsTheRecordForGood() {
        let item = tag("at.obdev.littlesnitch", "Item-0")
        let store = UnresponsiveItemStore()
        store.recordFailure(for: item)
        store.recordFailure(for: item)
        store.recordSuccess(for: item)

        XCTAssertFalse(store.isUnresponsive(item))
        XCTAssertFalse(UnresponsiveItemStore().isUnresponsive(item))
    }

    func testRecordsAreScopedToTheExactItem() {
        let store = UnresponsiveItemStore()
        store.recordFailure(for: tag("at.obdev.littlesnitch", "Item-0"))
        store.recordFailure(for: tag("at.obdev.littlesnitch", "Item-0"))

        XCTAssertFalse(store.isUnresponsive(tag("at.obdev.littlesnitch", "Item-1")))
        XCTAssertFalse(store.isUnresponsive(tag("com.example.other", "Item-0")))
    }

    func testItemsWithoutAStableNamespaceAreNotRecorded() {
        // A UUID namespace is reassigned every session, so recording one
        // would persist a key that can never match again.
        let ephemeral = MenuBarItemTag(namespace: .uuid(UUID()), title: "Item-0")
        let store = UnresponsiveItemStore()
        store.recordFailure(for: ephemeral)
        store.recordFailure(for: ephemeral)

        XCTAssertFalse(store.isUnresponsive(ephemeral))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }

    func testRemoveAllForgetsEverything() {
        let item = tag("at.obdev.littlesnitch", "Item-0")
        let store = UnresponsiveItemStore()
        store.recordFailure(for: item)
        store.recordFailure(for: item)
        store.removeAll()

        XCTAssertFalse(store.isUnresponsive(item))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }
}
