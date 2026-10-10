//
//  SecondsLabelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Seconds label")
struct SecondsLabelTests {
    @Test("A seconds label's text depends on its value")
    func textTracksItsValue() {
        #expect(SecondsLabel(value: 1.5).body == SecondsLabel(value: 1.5).body)
        #expect(SecondsLabel(value: 1.5).body != SecondsLabel(value: 2.5).body)
    }
}
