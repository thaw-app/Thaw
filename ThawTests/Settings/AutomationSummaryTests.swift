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
}
