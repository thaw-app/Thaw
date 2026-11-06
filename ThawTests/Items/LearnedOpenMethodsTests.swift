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
        store.record(.revealAndPress, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == .revealAndPress)
        #expect(store.method(for: OpenMethodIdentity(key: identity.key, appVersion: "13")) == nil)
    }

    @Test("a left click that opened nothing forgets the item")
    func leftClickFailureForgets() throws {
        let store = try makeStore()
        store.record(.revealAndPress, for: identity, clickedWith: .left)
        store.record(nil, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == nil)
    }

    @Test("a right click that opened the item keeps what left clicks learned")
    func rightClickKeepsLeftClickMethod() throws {
        let store = try makeStore()
        store.record(.revealAndPress, for: identity, clickedWith: .left)
        store.record(.showMenuInPlace, for: identity, clickedWith: .right)
        #expect(store.method(for: identity) == .revealAndPress)
    }

    @Test("a right click that opened nothing keeps what left clicks learned")
    func rightClickFailureKeepsLeftClickMethod() throws {
        let store = try makeStore()
        store.record(.revealAndPress, for: identity, clickedWith: .left)
        store.record(nil, for: identity, clickedWith: .right)
        #expect(store.method(for: identity) == .revealAndPress)
    }

    // MARK: The real click

    @Test("one real click is not learned, and keeps what was learned before")
    func oneRealClickIsNotLearned() throws {
        let store = try makeStore()
        store.record(.pressInPlace, for: identity, clickedWith: .left)
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == .pressInPlace)

        let fresh = OpenMethodIdentity(key: "com.example.other:Item-0", appVersion: "1")
        store.record(.revealAndClick, for: fresh, clickedWith: .left)
        #expect(store.method(for: fresh) == nil)
    }

    @Test("a real click needed twice in a row is learned, and kept while it keeps working")
    func twoRealClicksInARowAreLearned() throws {
        let store = try makeStore()
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == .revealAndClick)

        store.record(.revealAndClick, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == .revealAndClick)
    }

    @Test("a press that works, or an open that fails, between two real clicks starts the count again")
    func anythingElseResetsTheCount() throws {
        let store = try makeStore()
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        store.record(.revealAndPress, for: identity, clickedWith: .left)
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == .revealAndPress)

        store.record(nil, for: identity, clickedWith: .left)
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == nil)
    }

    @Test("a real click from an older version of the app doesn't count toward the new one")
    func realClickCountIsPerVersion() throws {
        let store = try makeStore()
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        let updated = OpenMethodIdentity(key: identity.key, appVersion: "13")
        store.record(.revealAndClick, for: updated, clickedWith: .left)
        #expect(store.method(for: updated) == nil)
    }

    @Test("right clicks don't count toward the real click")
    func rightClicksDontCount() throws {
        let store = try makeStore()
        store.record(.revealAndClick, for: identity, clickedWith: .right)
        store.record(.revealAndClick, for: identity, clickedWith: .left)
        #expect(store.method(for: identity) == nil)
    }

    @Test("an item learned as reveal in place starts over from the press, real click included")
    func oldRevealInPlaceStartsOver() throws {
        let defaults = try #require(suites.make())
        defaults.set([identity.key: ["method": "revealInPlace", "version": identity.appVersion]], forKey: LearnedOpenMethods.defaultsKey)
        let learned = LearnedOpenMethods(defaults: defaults).method(for: identity)

        #expect(learned == nil)
        #expect(ConcealedItemOpenMethod.openAttempts(for: .left, learned: learned) == [[.pressInPlace], [.revealAndPress, .revealAndClick]])
    }
}
