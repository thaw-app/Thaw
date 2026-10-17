//
//  SectionedListKeysTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@Suite("Sectioned list keys")
struct SectionedListKeysTests {
    @Test("Return opens the selected row, with or without modifiers")
    func returnOpens() {
        #expect(SectionedListNavigation.command(for: .return, modifiers: []) == .init(step: nil))
        #expect(SectionedListNavigation.command(for: .return, modifiers: .command) == .init(step: nil))
    }

    @Test("Plain arrows step through the rows, keypad and function flags included")
    func plainArrowsStep() {
        #expect(SectionedListNavigation.command(for: .downArrow, modifiers: []) == .init(step: 1))
        #expect(SectionedListNavigation.command(for: .upArrow, modifiers: []) == .init(step: -1))
        #expect(SectionedListNavigation.command(for: .downArrow, modifiers: [.numericPad, .function]) == .init(step: 1))
        #expect(SectionedListNavigation.command(for: .upArrow, modifiers: .capsLock) == .init(step: -1))
    }

    @Test("An arrow with Shift, Command, Option or Control is left to the search field", arguments: [
        EventModifiers.shift, .command, .option, .control, [.shift, .command],
    ])
    func modifiedArrowsAreIgnored(modifiers: EventModifiers) {
        #expect(SectionedListNavigation.command(for: .downArrow, modifiers: modifiers) == nil)
        #expect(SectionedListNavigation.command(for: .upArrow, modifiers: modifiers) == nil)
    }
}
