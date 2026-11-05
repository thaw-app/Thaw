//
//  SimpleRehideChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

@Suite("The Hide items again menu")
struct SimpleRehideChoiceTests {
    @Test("Each saved combination reads as one choice")
    func readsSettings() {
        #expect(SimpleRehideChoice(autoRehide: false, strategy: .timed, interval: 10) == .never)
        #expect(SimpleRehideChoice(autoRehide: true, strategy: .smart, interval: 10) == .whenClickingElsewhere)
        #expect(SimpleRehideChoice(autoRehide: true, strategy: .focusedApp, interval: 10) == .whenSwitchingApps)
        #expect(SimpleRehideChoice(autoRehide: true, strategy: .timed, interval: 30) == .after(30))
    }

    @Test("Choosing writes back the three stored settings")
    func writesSettings() {
        #expect(SimpleRehideChoice.never.settings(keepingInterval: 15) == (false, nil, 15))
        #expect(SimpleRehideChoice.whenClickingElsewhere.settings(keepingInterval: 15) == (true, .smart, 15))
        #expect(SimpleRehideChoice.after(60).settings(keepingInterval: 15) == (true, .timed, 60))
    }

    @Test("Turning rehiding off and on again, as the shortcut does, returns to the last other choice")
    func shortcutReturnsToLastChoice() {
        for (strategy, interval, expected) in [
            (RehideStrategy.smart, 15.0, SimpleRehideChoice.whenClickingElsewhere),
            (.focusedApp, 15, .whenSwitchingApps),
            (.timed, 42, .after(42)),
        ] {
            let off = SimpleRehideChoice.never.settings(keepingInterval: interval)
            #expect(SimpleRehideChoice(autoRehide: off.autoRehide, strategy: strategy, interval: off.interval) == .never)
            #expect(SimpleRehideChoice(autoRehide: !off.autoRehide, strategy: strategy, interval: off.interval) == expected)
        }
    }

    @Test("Each choice explains itself in its own words")
    func explanations() {
        let options = SimpleRehideChoice.options(including: .never)
        let delays = SimpleRehideChoice.delays.map(SimpleRehideChoice.after)
        let others = options.filter { !delays.contains($0) }
        #expect(Set(others.map { "\($0.explanation)" }).count == others.count)
        #expect(Set(delays.map { "\($0.explanation)" }).count == 1, "every delay shares one line")
        #expect("\(SimpleRehideChoice.never.explanation)" != "\(SimpleRehideChoice.after(5).explanation)")
    }

    @Test("The shortcut's notification names the menu and the choice now in effect")
    func summaryLines() {
        #expect(SimpleRehideChoice.never.summaryLine == "Hide items again: Never")
        #expect(SimpleRehideChoice.whenClickingElsewhere.summaryLine == "Hide items again: When I click elsewhere")
        #expect(SimpleRehideChoice.whenSwitchingApps.summaryLine == "Hide items again: When I switch apps")
        #expect(SimpleRehideChoice.after(60).summaryLine == "Hide items again: After 1 minute")
        #expect(SimpleRehideChoice.after(15).summaryLine == "Hide items again: After 15 seconds")
    }

    @Test("A delay set through a settings link that isn't listed still shows in the menu")
    func keepsAnUnlistedDelay() {
        let options = SimpleRehideChoice.options(including: .after(42))
        #expect(options.last == .after(42))
        #expect(SimpleRehideChoice.options(including: .after(30)).count == 8)
    }

    @Test("Each choice is its own row and names itself, a minute as a minute")
    func titles() {
        let options = SimpleRehideChoice.options(including: .never)
        #expect(Set(options.map(\.id)).count == options.count)
        #expect(SimpleRehideChoice.never.title == "Never")
        #expect(SimpleRehideChoice.whenClickingElsewhere.title == "When I click elsewhere")
        #expect(SimpleRehideChoice.whenSwitchingApps.title == "When I switch apps")
        #expect(SimpleRehideChoice.after(60).title == "After 1 minute")
        // Equality of interpolated keys compares their arguments, which SwiftUI doesn't do the same
        // way on every release, so the format and the number are read out and checked on their own.
        let delay = Self.parts(of: SimpleRehideChoice.after(15).title)
        #expect(delay.format == "After %lld seconds")
        #expect(delay.arguments.contains("15"))
        #expect(Self.parts(of: SimpleRehideChoice.after(60).title).format == "After 1 minute")
    }

    /// The key's format string and a description of its arguments.
    private static func parts(of key: LocalizedStringKey) -> (format: String?, arguments: String) {
        let children = Mirror(reflecting: key).children
        let format = children.first { $0.label == "key" }?.value as? String
        let arguments = children.first { $0.label == "arguments" }.map { String(describing: $0.value) } ?? ""
        return (format, arguments)
    }
}
