//
//  UpdateConsentSheetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Update consent sheet")
struct UpdateConsentSheetTests {
    private static let strings = UpdateConsentStrings(
        title: "Stay current?",
        message: "Checks happen in the background.",
        downloadAutomatically: "Fetch by itself",
        checkManually: "Not now",
        checkAutomatically: "Yes",
        checkboxOn: "Ticked",
        checkboxOff: "Unticked"
    )

    private func sheet() -> UpdateConsentSheet {
        UpdateConsentSheet(strings: Self.strings) { _ in
            Issue.record("Nothing presses a button here")
        } onDisable: {
            Issue.record("Nothing presses a button here")
        }
    }

    @Test("The sheet shows the text it is given")
    func suppliedText() {
        let view = sheet()
        #expect(view.strings.title == "Stay current?")
        #expect(view.strings.message == "Checks happen in the background.")
        #expect(view.strings.downloadAutomatically == "Fetch by itself")
        #expect(view.strings.checkManually == "Not now")
        #expect(view.strings.checkAutomatically == "Yes")
        #expect(view.strings.checkboxOn == "Ticked")
        #expect(view.strings.checkboxOff == "Unticked")
    }

    @Test("A minimum width, not a fixed one, so longer translations still fit")
    func minimumWidth() {
        #expect(NSHostingView(rootView: sheet()).fittingSize.width >= 380)
    }

    @Test("The presenting modifier draws the view it wraps")
    func modifierKeepsContent() {
        let view = Text("Page").updateConsentSheet(
            isPresented: .constant(false),
            strings: Self.strings,
            onEnable: { _ in
                Issue.record("The sheet is not up")
            },
            onDisable: {
                Issue.record("The sheet is not up")
            }
        )
        #expect(NSHostingView(rootView: view).fittingSize.width > 0)
    }
}
