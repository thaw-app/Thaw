//
//  PersistentIdentifierPartsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Persistent identifier parts")
struct PersistentIdentifierPartsTests {
    @Test("The first colon separates the namespace; the title keeps the rest")
    func splitsAtFirstColon() throws {
        let parts = try #require(MenuBarItemTag.persistentIdentifierParts("com.example.app:Status:2"))
        #expect(parts.namespace == "com.example.app")
        #expect(parts.title == "Status:2")
    }

    @Test("An identifier without a colon has no parts")
    func noColon() {
        #expect(MenuBarItemTag.persistentIdentifierParts("com.example.app") == nil)
    }

    @Test("An empty title or namespace is kept as empty")
    func emptyParts() throws {
        let trailing = try #require(MenuBarItemTag.persistentIdentifierParts("com.example.app:"))
        #expect(trailing.namespace == "com.example.app" && trailing.title.isEmpty)
        let leading = try #require(MenuBarItemTag.persistentIdentifierParts(":Title"))
        #expect(leading.namespace.isEmpty && leading.title == "Title")
    }

    @Test("A trailing :<number> after a title is an instance suffix")
    func instanceSuffix() {
        #expect(MenuBarItemTag.hasInstanceSuffix("Status:2"))
        #expect(!MenuBarItemTag.hasInstanceSuffix("Status"))
        #expect(!MenuBarItemTag.hasInstanceSuffix(":2"))
        #expect(!MenuBarItemTag.hasInstanceSuffix("Status:two"))
    }
}
