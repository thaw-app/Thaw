//
//  LayoutResetErrorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class LayoutResetErrorTests: XCTestCase {
    // MARK: - Error Cases

    func testMissingAppStateError() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        XCTAssertNotNil(error)
    }

    func testMissingControlItemsError() {
        let error = MenuBarItemManager.LayoutResetError.missingControlItems
        XCTAssertNotNil(error)
    }

    // MARK: - Error Description

    func testMissingAppStateErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        XCTAssertEqual(error.errorDescription, "Unable to access app state")
    }

    func testMissingControlItemsErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.missingControlItems
        XCTAssertEqual(error.errorDescription, "Couldn't find section dividers in the menu bar")
    }

    // MARK: - Recovery Suggestion

    func testMissingAppStateRecoverySuggestion() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        XCTAssertEqual(error.recoverySuggestion, "Make sure \(Constants.displayName) is running and try again.")
    }

    func testMissingControlItemsRecoverySuggestion() {
        let error = MenuBarItemManager.LayoutResetError.missingControlItems
        XCTAssertEqual(error.recoverySuggestion, "Make sure \(Constants.displayName) is running and try again.")
    }

    func testRecoverySuggestionContainsAppName() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        let suggestion = error.recoverySuggestion ?? ""

        XCTAssertTrue(suggestion.contains(Constants.displayName))
    }

    // MARK: - LocalizedError Conformance

    func testConformsToLocalizedError() {
        let error: LocalizedError = MenuBarItemManager.LayoutResetError.missingAppState
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testLocalizedDescriptionMatchesErrorDescription() {
        let error = MenuBarItemManager.LayoutResetError.missingAppState
        let localizedError = error as LocalizedError

        // localizedDescription should use errorDescription for LocalizedError
        XCTAssertEqual(error.localizedDescription, localizedError.errorDescription)
    }

    // MARK: - Equality

    func testSameErrorsAreEqual() {
        let error1 = MenuBarItemManager.LayoutResetError.missingAppState
        let error2 = MenuBarItemManager.LayoutResetError.missingAppState

        // Enums without associated values should be equatable
        XCTAssertTrue(errorsAreEqual(error1, error2))
    }

    func testDifferentErrorsAreNotEqual() {
        let error1 = MenuBarItemManager.LayoutResetError.missingAppState
        let error2 = MenuBarItemManager.LayoutResetError.missingControlItems

        XCTAssertFalse(errorsAreEqual(error1, error2))
    }

    // MARK: - All Cases

    func testAllCasesHaveDescriptions() throws {
        let allCases: [MenuBarItemManager.LayoutResetError] = [
            .missingAppState,
            .missingControlItems,
        ]

        for error in allCases {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty), "Error \(error) description should not be empty")
        }
    }

    func testAllCasesHaveRecoverySuggestions() throws {
        let allCases: [MenuBarItemManager.LayoutResetError] = [
            .missingAppState,
            .missingControlItems,
        ]

        for error in allCases {
            XCTAssertNotNil(error.recoverySuggestion, "Error \(error) should have a recovery suggestion")
            XCTAssertFalse(try XCTUnwrap(error.recoverySuggestion?.isEmpty), "Error \(error) recovery suggestion should not be empty")
        }
    }

    // MARK: - Helper

    private func errorsAreEqual(_ lhs: MenuBarItemManager.LayoutResetError, _ rhs: MenuBarItemManager.LayoutResetError) -> Bool {
        switch (lhs, rhs) {
        case (.missingAppState, .missingAppState):
            return true
        case (.missingControlItems, .missingControlItems):
            return true
        default:
            return false
        }
    }
}
