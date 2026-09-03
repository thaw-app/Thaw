//
//  MenuBarItemGroupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar item group store")
struct MenuBarItemGroupTests {
    private func encoded(_ set: MenuBarItemGroupSet) throws -> Data {
        try JSONEncoder().encode(set)
    }

    private func decoded(_ data: Data) throws -> MenuBarItemGroupSet {
        try JSONDecoder().decode(MenuBarItemGroupSet.self, from: data)
    }

    // MARK: Codable

    @Test("Round-trips through JSON")
    func codableRoundTrip() throws {
        var set = MenuBarItemGroupSet()
        let group = set.createGroup(name: "Work", memberIdentifiers: ["com.a:One", "com.b:Two"])
        set.suppressAutomatic(.string("com.c"))

        let restored = try decoded(encoded(set))

        #expect(restored == set)
        #expect(restored.groups.count == 1)
        #expect(restored.groups.first?.id == group?.id)
        #expect(restored.groups.first?.name == "Work")
        #expect(restored.suppressedAutomaticNamespaces == ["com.c"])
    }

    @Test("An empty set encodes and decodes to empty")
    func emptyRoundTrip() throws {
        #expect(try decoded(encoded(.empty)) == .empty)
    }

    @Test("A missing version field defaults to the current version")
    func missingVersionDefaults() throws {
        let json = Data(#"{"groups":[],"suppressedAutomaticNamespaces":[]}"#.utf8)
        #expect(try decoded(json).version == MenuBarItemGroupSet.currentVersion)
    }

    @Test("Unknown fields are ignored rather than failing the decode")
    func unknownFieldsIgnored() throws {
        let json = Data(#"{"version":1,"groups":[],"suppressedAutomaticNamespaces":[],"future":42}"#.utf8)
        #expect(try decoded(json) == .empty)
    }

    // MARK: normalized()

    /// Two distinct rules that are easy to conflate:
    ///
    /// - `createGroup` / `add` are *user intent* — "put this item in that group"
    ///   deliberately steals the identifier from whichever group holds it.
    /// - `normalized()` is a *repair pass* over possibly-corrupt decoded data,
    ///   where the only sane tie-break is deterministic: the earlier group wins.
    @Test("normalized() resolves a contested identifier in favour of the earlier group")
    func normalizationBreaksTiesTowardTheEarlierGroup() {
        // Built directly, bypassing createGroup, so the repair rule is what is
        // under test rather than the stealing rule.
        let set = MenuBarItemGroupSet(
            groups: [
                MenuBarItemGroup(name: "First", memberIdentifiers: ["com.a:One", "com.a:Two"]),
                MenuBarItemGroup(name: "Second", memberIdentifiers: ["com.a:Two", "com.b:Three"]),
            ]
        )

        #expect(set.groups.count == 1)
        #expect(set.groups[0].name == "First")
        #expect(set.groups[0].memberIdentifiers == ["com.a:One", "com.a:Two"])
        // "Second" lost the contested identifier, dropped to one member, and
        // therefore is no longer a group at all.
        #expect(set.group(containing: "com.b:Three") == nil)
    }

    @Test("createGroup steals a contested identifier from an existing group")
    func createGroupStealsContestedIdentifier() {
        var set = MenuBarItemGroupSet()
        set.createGroup(name: "First", memberIdentifiers: ["com.a:One", "com.a:Two"])
        set.createGroup(name: "Second", memberIdentifiers: ["com.a:Two", "com.b:Three"])

        #expect(set.group(containing: "com.a:Two")?.name == "Second")
        // "First" dropped to one member and dissolved.
        #expect(set.groups.count == 1)
    }

    @Test("A group is dropped once it holds fewer than two stored members")
    func degenerateGroupsAreDropped() throws {
        var set = MenuBarItemGroupSet()
        let group = set.createGroup(name: "Pair", memberIdentifiers: ["com.a:One", "com.a:Two"])
        #expect(set.groups.count == 1)

        set.removeMember("com.a:Two")

        #expect(set.groups.isEmpty)
        #expect(try set.group(id: #require(group?.id)) == nil)
    }

    @Test("Creating a group needs two distinct identifiers")
    func createRequiresTwoMembers() {
        var set = MenuBarItemGroupSet()
        #expect(set.createGroup(name: nil, memberIdentifiers: ["com.a:One"]) == nil)
        #expect(set.createGroup(name: nil, memberIdentifiers: ["com.a:One", "com.a:One"]) == nil)
        #expect(set.groups.isEmpty)
    }

    @Test("normalized() is idempotent")
    func normalizationIsIdempotent() {
        var set = MenuBarItemGroupSet()
        set.createGroup(name: "Work", memberIdentifiers: ["com.a:One", "com.b:Two", "com.c:Three"])
        #expect(set.normalized() == set)
        #expect(set.normalized().normalized() == set.normalized())
    }

    /// The sharpest failure mode in the model: group membership must be
    /// canonicalized with the *same* function the persisted section order uses,
    /// or an app whose title churns silently loses its group.
    @Test("Member identifiers are canonicalized the same way persisted order is")
    func membersAreCanonicalized() {
        let bundle = MenuBarItemTag.iStatMenusStatusBundleID
        let raw = ["\(bundle):CPU 42%", "\(bundle):CPU 43%"]
        let canonical = MenuBarItemTag.canonicalPersistentIdentifiers(raw)

        var set = MenuBarItemGroupSet()
        set.createGroup(name: nil, memberIdentifiers: raw)

        // Both raw titles canonicalize to the same identifier, collapsing to a
        // single member — so this was never a two-item group and is dropped.
        #expect(canonical.count == 1)
        #expect(set.groups.isEmpty)
    }

    /// A group whose members canonicalize apart must survive intact — the
    /// dedupe above must not be over-eager.
    @Test("Distinct iStat gauges canonicalize apart and stay grouped")
    func distinctDynamicTitlesStayGrouped() {
        let bundle = MenuBarItemTag.iStatMenusStatusBundleID
        var set = MenuBarItemGroupSet()
        set.createGroup(name: nil, memberIdentifiers: ["\(bundle):CPU 42%", "\(bundle):MEM 51%"])

        #expect(set.groups.count == 1)
        #expect(set.groups.first?.memberIdentifiers.count == 2)
    }

    // MARK: Names

    @Test("Blank names normalize to nil so 'unnamed' has one representation")
    func blankNamesNormalizeToNil() throws {
        var set = MenuBarItemGroupSet()
        let group = set.createGroup(name: "   ", memberIdentifiers: ["com.a:One", "com.b:Two"])
        #expect(group?.name == nil)

        let id = try #require(group?.id)

        set.rename(id: id, to: "  Work  ")
        #expect(set.groups.first?.name == "Work")

        set.rename(id: id, to: "")
        #expect(set.groups.first?.name == nil)
    }

    // MARK: Membership mutation

    @Test("Adding a member steals it from whichever group holds it")
    func addStealsFromOtherGroup() throws {
        var set = MenuBarItemGroupSet()
        let createdFirst = set.createGroup(name: "A", memberIdentifiers: ["com.a:One", "com.a:Two"])
        let createdSecond = set.createGroup(name: "B", memberIdentifiers: ["com.b:One", "com.b:Two"])
        let first = try #require(createdFirst)
        let second = try #require(createdSecond)

        set.add("com.a:Two", to: second.id)

        #expect(set.group(containing: "com.a:Two")?.id == second.id)
        // "A" dropped to one member and dissolved.
        #expect(set.group(id: first.id) == nil)
    }

    @Test("Members can be reordered within a group")
    func moveMemberReorders() throws {
        var set = MenuBarItemGroupSet()
        let created = set.createGroup(
            name: nil,
            memberIdentifiers: ["com.a:One", "com.b:Two", "com.c:Three"]
        )
        let group = try #require(created)

        set.moveMember(in: group.id, from: 0, to: 2)

        #expect(set.groups.first?.memberIdentifiers == ["com.b:Two", "com.c:Three", "com.a:One"])
    }

    @Test("Insert repositions an existing member rather than duplicating it")
    func insertRepositionsExistingMember() {
        var group = MenuBarItemGroup(memberIdentifiers: ["com.a:One", "com.b:Two", "com.c:Three"])
        group.insert("com.c:Three", at: 0)
        #expect(group.memberIdentifiers == ["com.c:Three", "com.a:One", "com.b:Two"])
    }

    @Test("Dissolving removes the group but leaves other groups intact")
    func dissolveRemovesOnlyThatGroup() throws {
        var set = MenuBarItemGroupSet()
        let createdFirst = set.createGroup(name: "A", memberIdentifiers: ["com.a:One", "com.a:Two"])
        let createdSecond = set.createGroup(name: "B", memberIdentifiers: ["com.b:One", "com.b:Two"])
        let first = try #require(createdFirst)
        let second = try #require(createdSecond)

        set.dissolve(id: first.id)

        #expect(set.groups.count == 1)
        #expect(set.groups.first?.id == second.id)
    }

    // MARK: Automatic suppression

    @Test("Suppressing a namespace is recorded by its description")
    func suppressionRecordsNamespaceDescription() {
        var set = MenuBarItemGroupSet()
        set.suppressAutomatic(.string("com.example.app"))

        #expect(set.isSuppressedAutomaticNamespace(.string("com.example.app")))
        #expect(!set.isSuppressedAutomaticNamespace(.string("com.other.app")))

        set.unsuppressAutomatic(.string("com.example.app"))
        #expect(!set.isSuppressedAutomaticNamespace(.string("com.example.app")))
    }

    @Test("Collapse state round-trips")
    func collapseStateRoundTrips() throws {
        var set = MenuBarItemGroupSet()
        let created = set.createGroup(name: nil, memberIdentifiers: ["com.a:One", "com.b:Two"])
        let group = try #require(created)
        set.setCollapsed(true, id: group.id)

        #expect(try decoded(encoded(set)).groups.first?.isCollapsed == true)
    }
}
