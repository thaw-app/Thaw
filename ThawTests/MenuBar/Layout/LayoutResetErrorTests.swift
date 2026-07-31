//
//  LayoutResetErrorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Layout reset errors")
struct LayoutResetErrorTests {
    // MARK: - Error Description

    @Test("Missing app state describes itself as an app state failure")
    func missingAppStateErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        #expect(error.errorDescription == "Unable to access app state")
    }

    @Test("Missing control items describes itself as missing section dividers")
    func missingControlItemsErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.missingControlItems
        #expect(error.errorDescription == "Couldn't find section dividers in the menu bar")
    }

    @Test("Already in progress describes itself as a reset already running")
    func alreadyInProgressErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.alreadyInProgress
        #expect(error.errorDescription == "A layout reset is already in progress")
    }

    // MARK: - Recovery Suggestion

    @Test("Missing app state suggests making sure the app is running")
    func missingAppStateRecoverySuggestion() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        #expect(error.recoverySuggestion == "Make sure \(Constants.displayName) is running and try again.")
    }

    @Test("Missing control items suggests making sure the app is running")
    func missingControlItemsRecoverySuggestion() {
        let error = MenuBarItemManager.LayoutResetError.missingControlItems
        #expect(error.recoverySuggestion == "Make sure \(Constants.displayName) is running and try again.")
    }

    @Test("A recovery suggestion names the app")
    func recoverySuggestionContainsAppName() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        let suggestion = error.recoverySuggestion ?? ""

        #expect(suggestion.contains(Constants.displayName))
    }

    // MARK: - LocalizedError Conformance

    @Test("The error conforms to LocalizedError with both strings populated")
    func conformsToLocalizedError() {
        let error: LocalizedError = MenuBarItemManager.LayoutResetError.missingAppState
        #expect(error.errorDescription != nil)
        #expect(error.recoverySuggestion != nil)
    }

    @Test("localizedDescription matches errorDescription")
    func localizedDescriptionMatchesErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        let localizedError = error as LocalizedError

        // localizedDescription should use errorDescription for LocalizedError
        #expect(error.localizedDescription == localizedError.errorDescription)
    }

    // MARK: - Equality

    @Test("Two missing-app-state errors are equal")
    func sameErrorsAreEqual() {
        let error1 = MenuBarItemManager.LayoutResetError.missingAppState
        let error2 = MenuBarItemManager.LayoutResetError.missingAppState

        // Enums without associated values should be equatable
        #expect(errorsAreEqual(error1, error2))
    }

    @Test("Different error cases are not equal")
    func differentErrorsAreNotEqual() {
        let error1 = MenuBarItemManager.LayoutResetError.missingAppState
        let error2 = MenuBarItemManager.LayoutResetError.missingControlItems

        #expect(!errorsAreEqual(error1, error2))
    }

    @Test("Two already-in-progress errors are equal")
    func alreadyInProgressErrorsAreEqual() {
        let error1 = MenuBarItemManager.LayoutResetError.alreadyInProgress
        let error2 = MenuBarItemManager.LayoutResetError.alreadyInProgress

        #expect(errorsAreEqual(error1, error2))
    }

    @Test("Already in progress is not equal to the other cases")
    func alreadyInProgressIsNotEqualToOtherErrors() {
        let error1 = MenuBarItemManager.LayoutResetError.alreadyInProgress
        let error2 = MenuBarItemManager.LayoutResetError.missingAppState

        #expect(!errorsAreEqual(error1, error2))
    }

    // MARK: - All Cases

    @Test("Every case carries a non-empty description")
    func allCasesHaveDescriptions() throws {
        let allCases: [MenuBarItemManager.LayoutResetError] = [
            .missingAppState,
            .missingControlItems,
            .alreadyInProgress,
        ]

        for error in allCases {
            #expect(error.errorDescription != nil, "Error \(error) should have a description")
            let isEmpty = try #require(error.errorDescription?.isEmpty)
            #expect(!isEmpty, "Error \(error) description should not be empty")
        }
    }

    @Test("Every case carries a non-empty recovery suggestion")
    func allCasesHaveRecoverySuggestions() throws {
        let allCases: [MenuBarItemManager.LayoutResetError] = [
            .missingAppState,
            .missingControlItems,
            .alreadyInProgress,
        ]

        for error in allCases {
            #expect(error.recoverySuggestion != nil, "Error \(error) should have a recovery suggestion")
            let isEmpty = try #require(error.recoverySuggestion?.isEmpty)
            #expect(!isEmpty, "Error \(error) recovery suggestion should not be empty")
        }
    }

    // MARK: - Helper

    private func errorsAreEqual(_ lhs: MenuBarItemManager.LayoutResetError, _ rhs: MenuBarItemManager.LayoutResetError) -> Bool {
        switch (lhs, rhs) {
        case (.missingAppState, .missingAppState):
            return true
        case (.missingControlItems, .missingControlItems):
            return true
        case (.alreadyInProgress, .alreadyInProgress):
            return true
        default:
            return false
        }
    }
}
