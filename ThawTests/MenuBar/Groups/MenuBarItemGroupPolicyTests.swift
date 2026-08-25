//
//  MenuBarItemGroupPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar item group policy")
struct MenuBarItemGroupPolicyTests {
    private typealias Policy = MenuBarItemGroupPolicy

    // MARK: GroupSet construction

    @Test("A group needs two members")
    func groupSetDropsDegenerateGroups() {
        let set = Policy.GroupSet(groups: [["a"], ["b", "c"], []])
        #expect(set.groups == [["b", "c"]])
    }

    @Test("An identifier belongs to one group; the earlier group wins")
    func groupSetResolvesContestedIdentifiers() {
        let set = Policy.GroupSet(groups: [["a", "b"], ["b", "c", "d"]])
        #expect(set.groups == [["a", "b"], ["c", "d"]])
        #expect(set.groupIndex(of: "b") == 0)
        #expect(set.groupIndex(of: "c") == 1)
        #expect(set.groupIndex(of: "zz") == nil)
    }

    // MARK: gather — the two safety properties

    /// The structural guarantee that canonicalization can never silently lose
    /// an item, swept across every drop position and group shape below.
    @Test("gather is always a permutation of its input")
    func gatherIsAPermutation() {
        let order = ["a1", "x", "a2", "y", "a3", "z", "b1", "b2"]
        let shapes: [[[String]]] = [
            [["a1", "a2", "a3"]],
            [["a1", "a3"]],
            [["b1", "b2"]],
            [["a1", "a2", "a3"], ["b1", "b2"]],
            [["a3", "y", "b1"]],
        ]
        for shape in shapes {
            let result = Policy.gather(groups: Policy.GroupSet(groups: shape), in: order).order
            #expect(result.sorted() == order.sorted(), "shape \(shape) lost or invented an element")
            #expect(result.count == order.count)
        }
    }

    /// If this failed, running canonicalization every cycle would rewrite state
    /// forever — the `2e38d6c6` reorder-storm failure mode.
    @Test("gather is idempotent")
    func gatherIsIdempotent() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"], ["b1", "b2"]])
        let order = ["a1", "x", "b1", "a2", "y", "b2", "a3"]

        let once = Policy.gather(groups: groups, in: order).order
        let twice = Policy.gather(groups: groups, in: once)

        #expect(twice.order == once)
        #expect(!twice.report.didChange)
    }

    @Test("An already-canonical order reports no change and is returned as-is")
    func canonicalOrderIsUntouched() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let order = ["x", "a1", "a2", "y"]

        let result = Policy.gather(groups: groups, in: order)

        #expect(result.order == order)
        #expect(!result.report.didChange)
        #expect(result.report.movedIdentifiers.isEmpty)
    }

    // MARK: gather — behaviour

    @Test("A scattered group gathers at its leftmost member")
    func gatherAnchorsAtLeftmostMember() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let result = Policy.gather(groups: groups, in: ["x", "a1", "y", "a2", "z", "a3"])

        #expect(result.order == ["x", "a1", "a2", "a3", "y", "z"])
        #expect(result.report.gatheredGroups == [0])
        #expect(result.report.didChange)
    }

    @Test("Non-members keep their relative order")
    func nonMembersKeepRelativeOrder() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let result = Policy.gather(groups: groups, in: ["a1", "x", "y", "z", "a2"])

        #expect(result.order == ["a1", "a2", "x", "y", "z"])
    }

    /// A group's internal order is the user's; gathering must relocate the
    /// block without reshuffling what is inside it.
    @Test("Members keep their current relative order, not the stored order")
    func membersKeepCurrentRelativeOrder() {
        // Stored order is a1,a2,a3 but the bar currently shows a3,a1,a2.
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let result = Policy.gather(groups: groups, in: ["a3", "x", "a1", "a2"])

        #expect(result.order == ["a3", "a1", "a2", "x"])
    }

    @Test("Two groups gather independently")
    func twoGroupsGatherIndependently() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"], ["b1", "b2"]])
        let result = Policy.gather(groups: groups, in: ["a1", "b1", "a2", "b2"])

        #expect(result.order == ["a1", "a2", "b1", "b2"])
    }

    @Test("Members absent from the order are ignored; the rest still gathers")
    func absentMembersAreIgnored() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let result = Policy.gather(groups: groups, in: ["a1", "x", "a3"])

        #expect(result.order == ["a1", "a3", "x"])
    }

    @Test("A group with only one member present is left alone")
    func singleLiveMemberIsLeftAlone() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let order = ["x", "a1", "y"]

        let result = Policy.gather(groups: groups, in: order)

        #expect(result.order == order)
        #expect(!result.report.didChange)
    }

    @Test("An empty group set is the identity")
    func emptyGroupSetIsIdentity() {
        let order = ["a", "b", "c"]
        let result = Policy.gather(groups: .empty, in: order)

        #expect(result.order == order)
        #expect(!result.report.didChange)
    }

    // MARK: scattered

    @Test("scattered names exactly the non-contiguous groups")
    func scatteredNamesNonContiguousGroups() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"], ["b1", "b2"]])

        #expect(Policy.scattered(groups: groups, in: ["a1", "a2", "b1", "b2"]).isEmpty)
        #expect(Policy.scattered(groups: groups, in: ["a1", "b1", "a2", "b2"]) == [0, 1])
        #expect(Policy.scattered(groups: groups, in: ["a1", "x", "a2", "b1", "b2"]) == [0])
    }

    // MARK: Section repair

    @Test("split names groups whose members straddle sections")
    func splitNamesStraddlingGroups() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"], ["b1", "b2"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "b1", "b2"],
            .hidden: ["a2"],
        ]

        #expect(Policy.split(groups: groups, inSections: sections) == [0])
    }

    @Test("A split group consolidates into the section holding the most members")
    func repairPrefersTheMajoritySection() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["x", "a1"],
            .hidden: ["a2", "a3", "y"],
        ]

        let result = Policy.gather(groups: groups, inSections: sections)

        #expect(result.sections[.visible] == ["x"])
        #expect(result.sections[.hidden] == ["a2", "a3", "a1", "y"])
        #expect(Policy.split(groups: groups, inSections: result.sections).isEmpty)
        #expect(result.report.repairedGroups.first?.to == .hidden)
    }

    /// Repairing toward visibility can never make an item unreachable;
    /// repairing toward always-hidden could conceal something silently.
    @Test("An even split breaks toward the more visible section")
    func repairBreaksTiesTowardVisibility() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .hidden: ["a1"],
            .alwaysHidden: ["a2"],
        ]

        let result = Policy.gather(groups: groups, inSections: sections)

        #expect(result.sections[.hidden] == ["a1", "a2"])
        #expect(result.sections[.alwaysHidden] == nil)
        #expect(result.report.repairedGroups.first?.to == .hidden)
    }

    @Test("Feasibility overrides the majority when only one section is allowed")
    func feasibilityOverridesMajority() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1"],
            .hidden: ["a2", "a3"],
        ]

        // A member cannot be hidden, so the whole group has to stay visible
        // even though Hidden holds more of it.
        let result = Policy.gather(groups: groups, inSections: sections) { _, section in
            section == .visible
        }

        #expect(result.sections[.visible] == ["a1", "a2", "a3"])
        #expect(result.sections[.hidden] == nil)
        #expect(result.report.repairedGroups.first?.to == .visible)
    }

    @Test("Healthy sections are returned untouched with no report")
    func healthySectionsAreUntouched() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "a2", "x"],
            .hidden: ["y"],
        ]

        let result = Policy.gather(groups: groups, inSections: sections)

        #expect(result.sections == sections)
        #expect(!result.report.didChange)
    }

    @Test("Section repair also gathers within the winning section")
    func repairAlsoGathersWithinTheWinner() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "x", "a2"],
            .hidden: ["a3"],
        ]

        let result = Policy.gather(groups: groups, inSections: sections)

        #expect(result.sections[.visible] == ["a1", "a2", "a3", "x"])
        #expect(Policy.scattered(groups: groups, in: result.sections[.visible] ?? []).isEmpty)
    }

    /// On macOS 27 the visible order mirrors live AX geometry, so membership may
    /// be repaired *into* Visible but its ordering must not be rewritten from
    /// persisted state.
    @Test("An excluded section has its membership repaired but its order left alone")
    func excludedSectionKeepsItsOrder() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "x", "a2"],
            .hidden: ["y"],
        ]

        let excluded = Policy.gather(
            groups: groups,
            inSections: sections,
            gatheringWithin: [.hidden, .alwaysHidden]
        )
        #expect(excluded.sections[.visible] == ["a1", "x", "a2"])
        #expect(!excluded.report.didChange)

        // The default gathers every section, so this is the contrast that shows
        // the parameter is doing the work.
        let included = Policy.gather(groups: groups, inSections: sections)
        #expect(included.sections[.visible] == ["a1", "a2", "x"])
    }

    @Test("A split group is still consolidated into an excluded section")
    func excludedSectionStillReceivesRepairedMembers() {
        let groups = Policy.GroupSet(groups: [["a1", "a2"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "x"],
            .hidden: ["a2"],
        ]

        let result = Policy.gather(
            groups: groups,
            inSections: sections,
            gatheringWithin: [.hidden, .alwaysHidden]
        )

        // Tie on member count breaks toward the more visible section.
        #expect(result.sections[.visible] == ["a1", "a2", "x"])
        #expect(result.sections[.hidden] == nil)
        #expect(Policy.split(groups: groups, inSections: result.sections).isEmpty)
    }

    @Test("Section repair is idempotent")
    func sectionRepairIsIdempotent() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "x"],
            .hidden: ["a2", "y", "a3"],
        ]

        let once = Policy.gather(groups: groups, inSections: sections)
        let twice = Policy.gather(groups: groups, inSections: once.sections)

        #expect(twice.sections == once.sections)
        #expect(!twice.report.didChange)
    }

    @Test("Section repair never loses an identifier")
    func sectionRepairIsAPermutation() {
        let groups = Policy.GroupSet(groups: [["a1", "a2", "a3"], ["b1", "b2"]])
        let sections: [MenuBarSection.Name: [String]] = [
            .visible: ["a1", "x", "b1"],
            .hidden: ["a2", "b2", "y"],
            .alwaysHidden: ["a3", "z"],
        ]

        let result = Policy.gather(groups: groups, inSections: sections)

        #expect(result.sections.values.flatMap(\.self).sorted() == sections.values.flatMap(\.self).sorted())
    }
}
