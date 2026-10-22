//
//  ThawPillPickerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

@MainActor
@Suite("Pill picker")
struct ThawPillPickerTests {
    @Test("A labelled pill picker keeps its label and offers one pill per value, in order")
    func labelledValues() {
        let picker = ThawPillPicker("Mode", selection: .constant(2), values: [1, 2, 3]) { _ in "Option" }
        #expect(picker.label != nil)
        #expect(picker.options.map(\.value) == [1, 2, 3])
    }

    @Test("A picker made without a label draws no row label")
    func unlabelled() {
        let picker = ThawPillPicker(selection: .constant(1), options: [.init(1, title: "One")])
        #expect(picker.label == nil)
    }
}
