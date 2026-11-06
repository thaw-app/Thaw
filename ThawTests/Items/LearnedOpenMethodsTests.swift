//
//  LearnedOpenMethodsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct LearnedOpenMethodsTests {
    private let suites = ScratchSuites(prefix: "LearnedOpenMethodsTests")
    private let identity = OpenMethodIdentity(key: "com.example.app:Item-0", appVersion: "12")

    private func makeStore() throws -> LearnedOpenMethods {
        try LearnedOpenMethods(defaults: #require(suites.make()))
    }

    @Test("a left click that opened the item is remembered for that app version")
    func remembersLeftClickMethod() throws {
        let store = try makeStore()
        store.record(.revealInPlace, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == .revealInPlace)
        #expect(store.method(for: OpenMethodIdentity(key: identity.key, appVersion: "13")) == nil)
    }

    @Test("a left click that opened nothing forgets the item")
    func leftClickFailureForgets() throws {
        let store = try makeStore()
        store.record(.revealInPlace, for: identity, clickedWith: .left)
        store.record(nil, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == nil)
    }

    @Test("a right click that opened the item keeps what left clicks learned")
    func rightClickKeepsLeftClickMethod() throws {
        let store = try makeStore()
        store.record(.revealInPlace, for: identity, clickedWith: .left)
        store.record(.showMenuInPlace, for: identity, clickedWith: .right)
        #expect(store.method(for: identity) == .revealInPlace)
    }

    @Test("a right click that opened nothing keeps what left clicks learned")
    func rightClickFailureKeepsLeftClickMethod() throws {
        let store = try makeStore()
        store.record(.revealInPlace, for: identity, clickedWith: .left)
        store.record(nil, for: identity, clickedWith: .right)
        #expect(store.method(for: identity) == .revealInPlace)
    }
}
