//
//  NotchOverflowGroupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
import ThawLayout

@Suite("Notch overflow keeps scattered groups whole")
struct NotchOverflowGroupTests {
    private static var controls: ControlUIDs {
        ControlUIDs(visible: "chevron", hidden: "H", alwaysHidden: "AH")
    }

    private static func plan(
        lane: [String],
        groups: [[String]],
        availableWidth: CGFloat
    ) -> LayoutSolver.NotchOverflowResult {
        var widths = Dictionary(uniqueKeysWithValues: lane.map { ($0, CGFloat(10)) })
        widths["chevron"] = 10
        return LayoutSolver.planNotchOverflow(
            desiredFiltered: lane + ["chevron", "H", "AH"],
            unmanagedUIDs: [],
            controlUIDs: controls,
            sectionMap: [:],
            uidWidths: widths,
            availableWidth: availableWidth,
            groups: MenuBarItemGroupPolicy.GroupSet(groups: groups)
        )
    }

    @Test("A group split by a singleton overflows whole, members in lane order")
    func scatteredGroupOverflowsWhole() {
        // Room for the chevron and two items: the trailing singleton and the
        // ungrouped item fit, the group anchored at the far left does not.
        let result = Self.plan(
            lane: ["a", "x", "b", "y", "c"],
            groups: [["a", "b", "c"]],
            availableWidth: 30
        )

        #expect(result.overflowUIDs == ["a", "b", "c"])
        #expect(result.groupsOverflowedWhole == [["a", "b", "c"]])
        #expect(result.updatedDesiredFiltered == ["x", "y", "chevron", "H", "a", "b", "c", "AH"])
    }

    @Test("A large lane of scattered groups plans in linear time with the same result", .timeLimit(.minutes(1)))
    func largeLaneOfScatteredGroups() {
        let groupCount = 20000
        let firsts = (0 ..< groupCount).map { "g\($0)-a" }
        let seconds = (0 ..< groupCount).map { "g\($0)-b" }
        let groups = (0 ..< groupCount).map { [firsts[$0], seconds[$0]] }
        let fittingGroups = 5

        let result = Self.plan(
            lane: firsts + seconds,
            groups: groups,
            availableWidth: 10 + CGFloat(fittingGroups * 20)
        )

        let overflowCount = groupCount - fittingGroups
        #expect(result.groupsOverflowedWhole == Array(groups.prefix(overflowCount)))
        #expect(result.overflowUIDs == Array(firsts.prefix(overflowCount)) + Array(seconds.prefix(overflowCount)))
        #expect(result.oversizedGroups.isEmpty)
    }
}
