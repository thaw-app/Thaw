//
//  ControlCommandDispatchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// What a Control Center command runs once its Darwin notification arrives. The action and the HUD are
/// recorders and the app state is a fresh one, so nothing on the live menu bar changes.
@MainActor
@Suite("Control command dispatch", .scratchDefaults)
struct ControlCommandDispatchTests {
    private final class Recorder {
        var actions: [HotkeyAction] = []
        var symbols: [String] = []
    }

    private func dispatch(_ name: String, appState: AppState?, recorder: Recorder) {
        ControlCommandObserver.dispatch(
            name,
            appState: appState,
            perform: { action, _ in recorder.actions.append(action) },
            showHUD: { symbol, _ in recorder.symbols.append(symbol) }
        )
    }

    @Test("A name that isn't one of the commands runs nothing")
    func unknownNameIsDropped() {
        let recorder = Recorder()
        dispatch("com.example.unrelated", appState: AppState(), recorder: recorder)
        #expect(recorder.actions.isEmpty)
        #expect(recorder.symbols.isEmpty)
    }

    @Test("A command that arrives before the app state exists runs nothing")
    func commandWithoutAppStateIsDropped() {
        let recorder = Recorder()
        dispatch(ControlCommandObserver.Command.toggleHidden.rawValue, appState: nil, recorder: recorder)
        #expect(recorder.actions.isEmpty)
    }

    @Test("The hidden-section toggle runs its action and confirms from the state it moves away from")
    func toggleHiddenConfirms() throws {
        let appState = AppState()
        let section = try #require(appState.menuBarManager.section(withName: .hidden))
        let recorder = Recorder()

        dispatch(ControlCommandObserver.Command.toggleHidden.rawValue, appState: appState, recorder: recorder)

        #expect(recorder.actions == [.toggleHiddenSection])
        #expect(recorder.symbols == [section.isHidden ? "eye" : "eye.slash"])
    }

    @Test("The zen toggle runs its action and leaves the confirmation to it")
    func toggleZenHasNoExtraHUD() {
        let recorder = Recorder()
        dispatch(ControlCommandObserver.Command.toggleZen.rawValue, appState: AppState(), recorder: recorder)
        #expect(recorder.actions == [.toggleZenMode])
        #expect(recorder.symbols.isEmpty)
    }
}
