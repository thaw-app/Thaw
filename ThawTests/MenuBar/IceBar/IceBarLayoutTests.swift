//
//  IceBarLayoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Ice bar layout")
struct IceBarLayoutTests {
    @Test("Every layout's identifier is its raw value")
    func idMatchesRawValue() {
        for layout in IceBarLayout.allCases {
            #expect(layout.id == layout.rawValue)
        }
    }

    @Test("Every layout has its own label")
    func localizedLabels() {
        #expect(IceBarLayout.horizontal.localized == LocalizedStringKey("Horizontal"))
        #expect(IceBarLayout.vertical.localized == LocalizedStringKey("Vertical"))
        #expect(IceBarLayout.grid.localized == LocalizedStringKey("Grid"))
    }

    @Test("No two layouts share a label")
    func localizedLabelsAreDistinct() {
        // `LocalizedStringKey` is Equatable but not Hashable, so this
        // cannot go through a Set.
        let labels = IceBarLayout.allCases.map(\.localized)
        for (offset, label) in labels.enumerated() {
            for other in labels[(offset + 1)...] {
                #expect(label != other)
            }
        }
    }

    /// `fromString` backs `thaw://set?key=iceBarLayout&value=…`, so both
    /// spellings are an external contract.
    @Test(
        "Both the case name and the raw value parse to the same layout",
        arguments: zip(["horizontal", "vertical", "grid"], [IceBarLayout.horizontal, .vertical, .grid])
    )
    func fromStringAcceptsNameAndRawValue(_ name: String, _ expected: IceBarLayout) {
        #expect(IceBarLayout.fromString(name) == expected)
        #expect(IceBarLayout.fromString(String(expected.rawValue)) == expected)
    }

    @Test(
        "An unknown spelling is rejected rather than defaulted",
        arguments: ["", "Horizontal", "HORIZONTAL", "3", "-1", "column", " grid"]
    )
    func fromStringRejectsUnknownSpellings(_ candidate: String) {
        #expect(IceBarLayout.fromString(candidate) == nil)
    }
}
