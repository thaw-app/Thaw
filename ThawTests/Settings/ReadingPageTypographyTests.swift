//
//  ReadingPageTypographyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Reading page typography")
struct ReadingPageTypographyTests {
    @Test("Release notes and credits use the same text styles as settings")
    func usesSharedTypography() {
        #expect(ReadingPageType.body == ThawType.body)
        #expect(ReadingPageType.heading == ThawType.heading)
    }
}
