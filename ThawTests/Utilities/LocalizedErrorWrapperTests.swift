//
//  LocalizedErrorWrapperTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``LocalizedErrorWrapper``, which flattens an arbitrary error into a
/// value SwiftUI's alert presentation can read.
///
/// The type has exactly one decision in it, and it is the interesting one: an
/// error that already conforms to `LocalizedError` has its four fields copied
/// verbatim, while anything else — an `NSError` bridged from a framework, a
/// bare `enum` thrown by app code — contributes only `localizedDescription`
/// and leaves the other three nil. Getting that branch backwards would either
/// drop a hand-written recovery suggestion or surface Swift's generated
/// "The operation couldn't be completed" text where a real message existed, and
/// neither failure is visible without an alert on screen.
@Suite("Localized error wrapper")
struct LocalizedErrorWrapperTests {
    /// An error that fills in every `LocalizedError` field.
    private struct FullyDescribedError: LocalizedError {
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

    /// A `LocalizedError` that supplies nothing, which is the default
    /// conformance every protocol extension provides.
    private struct EmptyLocalizedError: LocalizedError {}

    /// An error that does not conform to `LocalizedError`.
    private enum PlainError: Error {
        case failed
    }

    // MARK: - Localized Errors

    @Test("A localized error passes all four fields through")
    func localizedErrorPassesEveryFieldThrough() {
        let wrapper = LocalizedErrorWrapper(FullyDescribedError())

        #expect(wrapper.errorDescription == "description")
        #expect(wrapper.failureReason == "reason")
        #expect(wrapper.helpAnchor == "anchor")
        #expect(wrapper.recoverySuggestion == "suggestion")
    }

    /// The default `LocalizedError` conformance returns nil for everything, and
    /// the wrapper must not substitute `localizedDescription` for the missing
    /// values — that is the other branch's job.
    @Test("A localized error with no values wraps to all nil")
    func emptyLocalizedErrorWrapsToAllNil() {
        let wrapper = LocalizedErrorWrapper(EmptyLocalizedError())

        #expect(wrapper.errorDescription == nil)
        #expect(wrapper.failureReason == nil)
        #expect(wrapper.helpAnchor == nil)
        #expect(wrapper.recoverySuggestion == nil)
    }

    /// Wrapping is idempotent, since the wrapper is itself a `LocalizedError`.
    @Test("Wrapping a wrapper preserves the fields")
    func wrappingAWrapperPreservesTheFields() {
        let inner = LocalizedErrorWrapper(FullyDescribedError())
        let outer = LocalizedErrorWrapper(inner)

        #expect(outer.errorDescription == inner.errorDescription)
        #expect(outer.failureReason == inner.failureReason)
        #expect(outer.helpAnchor == inner.helpAnchor)
        #expect(outer.recoverySuggestion == inner.recoverySuggestion)
    }

    // MARK: - Non-Localized Errors

    @Test("A plain error contributes only its localized description")
    func plainErrorContributesOnlyItsDescription() {
        let error = PlainError.failed
        let wrapper = LocalizedErrorWrapper(error)

        #expect(wrapper.errorDescription == error.localizedDescription)
        #expect(wrapper.failureReason == nil)
        #expect(wrapper.helpAnchor == nil)
        #expect(wrapper.recoverySuggestion == nil)
    }

    /// `NSError` does not conform to `LocalizedError`, so it takes the
    /// non-localized branch and its `NSLocalizedDescriptionKey` value arrives
    /// through `localizedDescription`.
    @Test("An NSError's localized description survives the non-localized branch")
    func nsErrorDescriptionSurvives() {
        let error = NSError(
            domain: "com.stonerl.ThawTests",
            code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: "something went wrong",
                NSLocalizedRecoverySuggestionErrorKey: "try again",
            ]
        )

        let wrapper = LocalizedErrorWrapper(error)

        #expect(wrapper.errorDescription == "something went wrong")
        #expect(wrapper.recoverySuggestion == nil)
    }

    // MARK: - LocalizedError Conformance

    /// `localizedDescription` on a `LocalizedError` is derived from
    /// `errorDescription`, which is what an alert title ends up showing.
    @Test("The wrapper's localized description comes from the wrapped error")
    func localizedDescriptionComesFromTheWrappedError() {
        let wrapper = LocalizedErrorWrapper(FullyDescribedError())

        #expect(wrapper.localizedDescription == "description")
    }

    @Test("The wrapper can be thrown and caught as a LocalizedError")
    func wrapperCanBeThrownAsALocalizedError() {
        func failing() throws {
            throw LocalizedErrorWrapper(FullyDescribedError())
        }

        #expect(throws: LocalizedErrorWrapper.self) {
            try failing()
        }
    }
}
