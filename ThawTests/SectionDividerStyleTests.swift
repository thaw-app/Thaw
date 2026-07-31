//
//  SectionDividerStyleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Section divider style")
struct SectionDividerStyleTests {
    // MARK: - Raw Value Tests

    @Test("noDivider has raw value 0")
    func noDividerRawValue() {
        #expect(SectionDividerStyle.noDivider.rawValue == 0)
    }

    @Test("chevron has raw value 1")
    func chevronRawValue() {
        #expect(SectionDividerStyle.chevron.rawValue == 1)
    }

    // MARK: - Init from Raw Value Tests

    @Test("Raw value 0 initializes noDivider")
    func initFromRawValueZero() {
        #expect(SectionDividerStyle(rawValue: 0) == .noDivider)
    }

    @Test("Raw value 1 initializes chevron")
    func initFromRawValueOne() {
        #expect(SectionDividerStyle(rawValue: 1) == .chevron)
    }

    @Test("An out-of-range raw value initializes nothing")
    func initFromInvalidRawValue() {
        #expect(SectionDividerStyle(rawValue: 2) == nil)
        #expect(SectionDividerStyle(rawValue: -1) == nil)
    }

    // MARK: - Identifiable Tests

    @Test("Every style's identifier is its raw value")
    func idMatchesRawValue() {
        for style in SectionDividerStyle.allCases {
            #expect(style.id == style.rawValue)
        }
    }

    // MARK: - CaseIterable Tests

    @Test("There are two styles")
    func allCasesCount() {
        #expect(SectionDividerStyle.allCases.count == 2)
    }

    @Test("allCases lists every style")
    func allCasesContainsAllStyles() {
        #expect(SectionDividerStyle.allCases.contains(.noDivider))
        #expect(SectionDividerStyle.allCases.contains(.chevron))
    }
}
