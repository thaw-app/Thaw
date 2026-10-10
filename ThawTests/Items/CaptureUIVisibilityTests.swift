//
//  CaptureUIVisibilityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Capture UI visibility")
@MainActor
struct CaptureUIVisibilityTests {
    @Test("Opening a capture pane starts capture before the window is visible")
    func settingsOpening() throws {
        let navigation = AppNavigationState()
        navigation.isSimpleModeSettings = false
        navigation.settingsNavigationIdentifier = .menuBarLayout
        let request = try #require(navigation.beginSettingsPresentation())
        #expect(navigation.hasCaptureUI)
        #expect(!navigation.hasVisibleCaptureUI)
        #expect(navigation.beginSettingsPresentation() == nil)
        navigation.isSettingsPresented = false
        #expect(navigation.hasCaptureUI)
        navigation.isSettingsPresented = true
        navigation.finishSettingsPresentation(request)
        #expect(navigation.hasCaptureUI)
        navigation.isSettingsPresented = false
        #expect(!navigation.hasCaptureUI)
    }

    @Test("A pane that draws no captures never starts capture")
    func nonCapturePane() throws {
        let navigation = AppNavigationState()
        navigation.isSimpleModeSettings = false
        navigation.settingsNavigationIdentifier = .general
        let request = try #require(navigation.beginSettingsPresentation())
        #expect(!navigation.hasCaptureUI)
        navigation.isSettingsPresented = true
        #expect(!navigation.hasVisibleCaptureUI)
        // Moving to a pane that does draw captures turns it on without a
        // window toggle, and moving away turns it back off.
        navigation.settingsNavigationIdentifier = .menuBarLayout
        #expect(navigation.hasVisibleCaptureUI)
        navigation.settingsNavigationIdentifier = .general
        #expect(!navigation.hasVisibleCaptureUI)
        navigation.isSettingsPresented = false
        navigation.finishSettingsPresentation(request)
        #expect(!navigation.hasCaptureUI)
    }

    @Test("Simple Mode draws captured glyphs whatever pane the sidebar last showed")
    func simpleModePane() throws {
        let navigation = AppNavigationState()
        // Simple Mode has no sidebar, so the identifier keeps whatever the
        // full window was last on: here, a pane that draws no captures.
        navigation.settingsNavigationIdentifier = .general
        navigation.isSimpleModeSettings = true
        let request = try #require(navigation.beginSettingsPresentation())
        #expect(navigation.hasCaptureUI)
        navigation.isSettingsPresented = true
        #expect(navigation.hasVisibleCaptureUI)
        // Leaving Simple Mode drops back to the pane's own answer.
        navigation.isSimpleModeSettings = false
        #expect(!navigation.hasVisibleCaptureUI)
        navigation.isSettingsPresented = false
        navigation.finishSettingsPresentation(request)
        #expect(!navigation.hasCaptureUI)
    }

    @Test("Expired presentation cannot close a newer capture request")
    func staleOpeningExpiry() throws {
        let navigation = AppNavigationState()
        navigation.isSimpleModeSettings = false
        navigation.settingsNavigationIdentifier = .menuBarLayout
        let oldRequest = try #require(navigation.beginSettingsPresentation())
        navigation.cancelSettingsPresentation()
        #expect(!navigation.hasCaptureUI)
        let currentRequest = try #require(navigation.beginSettingsPresentation())
        navigation.finishSettingsPresentation(oldRequest)
        #expect(navigation.hasCaptureUI)
        navigation.finishSettingsPresentation(currentRequest)
        #expect(!navigation.hasCaptureUI)
    }

    @Test("Frontmost app alone does not require capture")
    func frontmostWithoutUI() {
        let navigation = AppNavigationState()
        navigation.isAppFrontmost = true
        #expect(!navigation.hasVisibleCaptureUI)
    }

    @Test("Capture remains available until the last surface closes")
    func overlappingSurfaces() {
        let navigation = AppNavigationState()
        navigation.isSettingsPresented = true
        navigation.isThawBarPresented = true
        navigation.isSettingsPresented = false
        #expect(navigation.hasVisibleCaptureUI)
        navigation.isSearchPresented = true
        navigation.isThawBarPresented = false
        #expect(navigation.hasVisibleCaptureUI)
        navigation.isLayoutEditorPresented = true
        navigation.isSearchPresented = false
        #expect(navigation.hasVisibleCaptureUI)
        navigation.isLayoutEditorPresented = false
        #expect(!navigation.hasVisibleCaptureUI)
    }
}
