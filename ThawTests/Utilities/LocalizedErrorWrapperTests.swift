//
//  LocalizedErrorWrapperTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Localized error wrapper")
struct LocalizedErrorWrapperTests {
    private struct Described: LocalizedError {
        var errorDescription: String? {
            "description"
        }

        var failureReason: String? {
            "reason"
        }

        var helpAnchor: String? {
            "anchor"
        }

        var recoverySuggestion: String? {
            "suggestion"
        }
    }

    private struct Plain: Error {}

    @Test("A localized error passes every field through")
    func localizedErrorPassesThrough() {
        let wrapper = LocalizedErrorWrapper(Described())
        #expect(wrapper.errorDescription == "description")
        #expect(wrapper.failureReason == "reason")
        #expect(wrapper.helpAnchor == "anchor")
        #expect(wrapper.recoverySuggestion == "suggestion")
    }

    @Test("Any other error keeps only its localized description")
    func plainErrorKeepsDescription() {
        let error = Plain()
        let wrapper = LocalizedErrorWrapper(error)
        #expect(wrapper.errorDescription == error.localizedDescription)
        #expect(wrapper.failureReason == nil)
        #expect(wrapper.helpAnchor == nil)
        #expect(wrapper.recoverySuggestion == nil)
    }
}
