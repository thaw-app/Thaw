//
//  SettingsSmallViewsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// Small Settings views, drawn off screen and measured, with settings in a throwaway suite.
@Suite("Small Settings views", .serialized, .scratchDefaults)
@MainActor
final class SettingsSmallViewsTests {
    private let previousCenter = SettingsURIHandler.settingsChangeNotificationCenter

    init() {
        SettingsURIHandler.settingsChangeNotificationCenter = NotificationCenter()
    }

    isolated deinit {
        SettingsURIHandler.settingsChangeNotificationCenter = previousCenter
    }

    /// The height the view asks for at a fixed width, after one layout pass.
    private func height(of view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: 320))
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("A row's detail shows under the title unless descriptions are hidden")
    func rowLabelDetail() {
        let shown = height(of: ThawRowLabel("Title", detail: "A line of detail"))
        let hidden = height(of: ThawRowLabel("Title", detail: "A line of detail")
            .environment(\.settingsDescriptionsVisible, false))
        let verbatim = height(of: ThawRowLabel("Title", verbatimDetail: "build 114"))
        let titleOnly = height(of: ThawRowLabel("Title"))
        #expect(shown > hidden)
        #expect(verbatim > titleOnly)
        #expect(hidden == titleOnly)
    }

    @Test("Every pane has a title and a subtitle")
    func paneTitles() {
        for pane in SettingsNavigationIdentifier.allCases {
            _ = pane.localized
            _ = pane.subtitle
        }
        #expect(SettingsNavigationIdentifier.displays.localized == "Displays")
        #expect(SettingsNavigationIdentifier.automation.subtitle == "Triggers and scripts")
        #expect(SettingsNavigationIdentifier.scripts.localized == "Scripts")
        #expect(SettingsNavigationIdentifier.scripts.subtitle == "Run scripts before and after a profile switches")
    }
}
