//
//  LayoutRefusalNoticeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The line about macOS keeping system items showed above every refusal, including an unresponsive app.
@MainActor
@Suite("Layout refusal notice", .serialized, .scratchDefaults)
struct LayoutRefusalNoticeTests {
    private func height(for refusal: LayoutBarFeedbackCenter.Refusal?, appState: AppState) -> CGFloat {
        appState.layoutFeedback.clear()
        if let refusal {
            appState.layoutFeedback.post(refusal)
        }
        let host = NSHostingView(rootView: LayoutRefusalNotice().environment(appState).frame(width: 480))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The system-items line shows only for refusals about system items")
    func systemLineOnlyWhenItApplies() {
        let appState = AppState()
        let system = height(for: LayoutBarFeedbackCenter.itemCannotMove(itemName: "Clock", section: .hidden), appState: appState)
        let other = height(for: LayoutBarFeedbackCenter.ownerUnresponsive(itemName: "Stuck"), appState: appState)
        let none = height(for: nil, appState: appState)
        #expect(system > other, "the extra line")
        #expect(other > none)
        appState.layoutFeedback.clear()
    }
}
