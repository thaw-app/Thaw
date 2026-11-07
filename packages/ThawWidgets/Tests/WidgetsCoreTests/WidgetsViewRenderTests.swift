//
//  WidgetsViewRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
import ThawModuleTestSupport
@testable import WidgetsCore

/// The icon builder draws in both reading modes, offscreen, against scratch settings.
@MainActor
@Suite("Widgets builder rendering")
struct WidgetsViewRenderTests {
    private let suites = ScratchSuites(prefix: "WidgetsViewRenderTests")

    private func draw(live: Bool) throws {
        let defaults = try #require(suites.make())
        defaults.set(live, forKey: WidgetKeys.live)
        let host = NSHostingView(rootView: WidgetsView().defaultAppStorage(defaults))
        host.frame = CGRect(x: 0, y: 0, width: 520, height: 1400)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
    }

    @Test("The builder draws with live readings and with sample readings")
    func drawsBothModes() throws {
        try draw(live: true)
        try draw(live: false)
    }
}
