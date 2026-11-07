//
//  FocusStandInNoticeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// macOS hides Focus while items are hidden, and the stand-in that brings it back was off by default.
@MainActor
@Suite("Focus stand-in notice", .serialized, .scratchDefaults)
struct FocusStandInNoticeTests {
    @Test("The notice shows only when Control Center shows Focus and Thaw doesn't replace it")
    func showsWhenFocusIsMissing() {
        #expect(FocusStandInNotice.shows(focusShownInControlCenter: true, focusReplaced: false))
        #expect(!FocusStandInNotice.shows(focusShownInControlCenter: true, focusReplaced: true))
        #expect(!FocusStandInNotice.shows(focusShownInControlCenter: false, focusReplaced: false))
    }

    @Test("Turning it on replaces Focus alone and keeps the other modules as they were")
    func turnsOnFocusOnly() {
        var off = ControlCenterReplacements(modules: false, timeMachine: true, textInput: false)
        FocusStandInNotice.replaceFocus(in: &off)
        #expect(off.isReplaced(.focus))
        #expect(!off.isReplaced(.airDrop) && !off.isReplaced(.nowPlaying) && !off.isReplaced(.userSwitcher))
        #expect(off.timeMachine, "Time Machine stays as it was")

        var someOn = ControlCenterReplacements(modules: true, timeMachine: false, textInput: false, skipped: [.focus, .userSwitcher])
        FocusStandInNotice.replaceFocus(in: &someOn)
        #expect(someOn.isReplaced(.focus) && someOn.isReplaced(.airDrop) && !someOn.isReplaced(.userSwitcher))
    }

    @Test("Draws when Focus is missing, nothing otherwise, and its button turns the stand-in on")
    func drawsAndActs() async throws {
        let appState = AppState()
        let settings = appState.settings.advanced
        settings.controlCenterReplacements = ControlCenterReplacements(modules: false, timeMachine: false, textInput: false)
        let size = CGSize(width: 480, height: 80)
        let shown = OffscreenRender(FocusStandInNotice(settings: settings, focusShownInControlCenter: true).frame(width: size.width), size: size)
        let hidden = OffscreenRender(FocusStandInNotice(settings: settings, focusShownInControlCenter: false).frame(width: size.width), size: size)
        let hiddenPixels = try hidden.pixels()
        await shown.settle { (try? shown.pixels()) != hiddenPixels }
        #expect(try shown.pixels() != hiddenPixels)
        #expect(!hiddenPixels.contains { $0 != 0 }, "no Focus preference, no notice")

        FocusStandInNotice.replaceFocus(in: &settings.controlCenterReplacements)
        #expect(settings.controlCenterReplacements.isReplaced(.focus))
        var asked: String?
        #expect(FocusStandInNotice.focusShownInControlCenter { asked = $0; return true })
        #expect(asked?.contains("focusmode") == true)
        #expect(!FocusStandInNotice.focusShownInControlCenter { _ in false })
    }
}
