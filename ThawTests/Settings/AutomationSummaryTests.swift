//
//  AutomationSummaryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Automation summaries")
struct AutomationSummaryTests {
    private let english = Locale(identifier: "en_US")

    @Test("Profile switching names each profile and where it switches")
    func profileSwitching() {
        #expect(AutomationSummary.profileSwitching([], locale: english) == "No display or Space switches profiles yet.")
        let assignments = [
            AutomationSummary.Assignment(profile: "Work", place: "Built-in Display"),
            AutomationSummary.Assignment(profile: "Home", place: "Desktop 2"),
        ]
        #expect(AutomationSummary.profileSwitching(assignments, locale: english) == "Work on Built-in Display and Home on Desktop 2.")
    }

    @Test("Long lists end in a count")
    func longListIsCounted() {
        let assignments = ["A", "B", "C", "D", "E"].map { AutomationSummary.Assignment(profile: $0, place: "X") }
        #expect(AutomationSummary.profileSwitching(assignments, locale: english) == "A on X, B on X, and 3 more.")
    }

    @Test("A script path shortens the home folder")
    func scriptPath() {
        let home = NSHomeDirectory()
        #expect(AutomationSummary.script(path: nil) == "None")
        #expect(AutomationSummary.script(path: "") == "None")
        #expect(AutomationSummary.script(path: home + "/bin/a.sh") == "~/bin/a.sh")
        #expect(AutomationSummary.script(path: home + "g/a.sh") == home + "g/a.sh")
        #expect(AutomationSummary.script(path: "/opt/a.sh") == "/opt/a.sh")
    }

    private func profile(_ name: String, display: String? = nil, space: String? = nil) -> ProfileMetadata {
        ProfileMetadata(
            id: UUID(), name: name, createdAt: .now, modifiedAt: .now,
            associatedDisplayUUID: display.map { _ in UUID().uuidString }, associatedDisplayName: display,
            associatedSpaceKey: space.map { _ in UUID().uuidString }, associatedSpaceName: space
        )
    }

    @Test("Each profile's displays and Spaces become the summary under the list")
    func assignmentsOfProfiles() {
        let assignments = AutomationSummary.assignments(of: [
            profile("Work", display: "Studio Display", space: "Desktop 2"),
            profile("Travel"),
        ])
        #expect(assignments == [
            .init(profile: "Work", place: "Studio Display"),
            .init(profile: "Work", place: "Desktop 2"),
        ])
    }

    @Test("A row says what switches to its profile, or that only you do")
    func rowSummary() {
        #expect(AutomationSummary.switches(of: profile("Work", display: "Studio Display", space: "Desktop 2")) == "Studio Display · Desktop 2")
        #expect(AutomationSummary.switches(of: profile("Home", display: "Built-in")) == "Built-in")
        #expect(AutomationSummary.switches(of: profile("Travel")) == "Manually or by shortcut")
    }

    @Test("A display or Space saved without a name still counts")
    func unnamedPlaces() {
        var unnamed = profile("Desk")
        unnamed.associatedDisplayUUID = UUID().uuidString
        unnamed.associatedSpaceKey = "space-1"
        #expect(AutomationSummary.switches(of: unnamed) == "a display · a Space")
        #expect(AutomationSummary.assignments(of: [unnamed]).map(\.place) == ["a display", "a Space"])
    }
}
