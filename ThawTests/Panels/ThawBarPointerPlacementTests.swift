//
//  ThawBarPointerPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Thaw Bar pointer placement", .serialized)
struct ThawBarPointerPlacementTests {
    @Test("Resizing retains the opening pointer after it leaves empty menu bar space",
          arguments: [ThawBarLocation.dynamic, .mousePointer], [true, false])
    func resizeRetainsOpeningPointer(location: ThawBarLocation, showsIcon: Bool) throws {
        try withPanel(location: location, showsIcon: showsIcon) { fixture in
            let openingX = try #require(fixture.pointer.location?.x)
            fixture.show()
            fixture.pointer.location = CGPoint(x: fixture.screen.frame.maxX - 20, y: fixture.screen.frame.midY)
            fixture.pointer.inEmptyMenuBarSpace = false

            for width: CGFloat in [160, 320] {
                fixture.resize(width: width)
                #expect(abs(fixture.panel.frame.midX - openingX) < 1)
            }
        }
    }

    @Test("Reopening captures the new pointer rather than retaining the previous open")
    func reopeningCapturesNewPointer() throws {
        try withPanel { fixture in
            fixture.show()
            fixture.panel.close()
            let nextX = fixture.screen.frame.minX + fixture.screen.frame.width * 0.65
            fixture.pointer.location = CGPoint(x: nextX, y: fixture.screen.frame.maxY - 10)
            fixture.show()
            fixture.pointer.location = nil
            fixture.resize(width: 160)

            #expect(abs(fixture.panel.frame.midX - nextX) < 1)
        }
    }

    @Test("Reopening away from empty menu bar space clears the old pointer anchor",
          arguments: [true, false])
    func reopeningClearsPointerAnchor(hasPointer: Bool) throws {
        try withPanel { fixture in
            fixture.show()
            fixture.panel.close()
            fixture.pointer.inEmptyMenuBarSpace = false
            if !hasPointer {
                fixture.pointer.location = nil
            }
            fixture.show()
            fixture.resize(width: 160)

            #expect(abs(fixture.panel.frame.maxX - fixture.screen.frame.maxX) < 1)
        }
    }

    @Test("A non-pointer placement on the next open does not reuse the old anchor",
          arguments: [ThawBarLocation.leftAligned, .rightAligned])
    func changingPlacementClearsPointerAnchor(location: ThawBarLocation) throws {
        try withPanel { fixture in
            fixture.show()
            fixture.panel.close()
            fixture.appState.settings.displaySettings.globalConfiguration = .defaultConfiguration.withThawBarLocation(location)
            fixture.show()
            fixture.resize(width: 160)

            let expectedX = location == .leftAligned
                ? fixture.screen.frame.minX + 24
                : fixture.screen.frame.maxX - 160 - 24
            #expect(abs(fixture.panel.frame.minX - expectedX) < 1)
        }
    }

    @Test("An opening icon takes precedence over a recorded pointer")
    func openingIconOverridesPointer() throws {
        try withPanel { fixture in
            let iconX = fixture.screen.frame.minX + fixture.screen.frame.width * 0.7
            fixture.show(openedFrom: CGRect(x: iconX - 12, y: 0, width: 24, height: 24))
            fixture.pointer.location = nil
            fixture.resize(width: 160)

            #expect(abs(fixture.panel.frame.midX - iconX) < 1)
        }
    }

    @Test("A retained pointer near either edge stays clamped as the panel grows", arguments: [true, false])
    func resizingClampsToScreen(leftEdge: Bool) throws {
        try withPanel { fixture in
            fixture.pointer.location = CGPoint(
                x: leftEdge ? fixture.screen.frame.minX + 2 : fixture.screen.frame.maxX - 2,
                y: fixture.screen.frame.maxY - 10
            )
            fixture.show()
            fixture.pointer.location = nil
            for width: CGFloat in [160, 320] {
                fixture.resize(width: width)
                let expectedX = leftEdge ? fixture.screen.frame.minX : fixture.screen.frame.maxX - width
                #expect(abs(fixture.panel.frame.minX - expectedX) < 1)
            }
        }
    }

    @Test("Hotkey placement still uses the live pointer in both axes")
    func hotkeyOverridesRecordedPointer() throws {
        try withPanel { fixture in
            fixture.appState.settings.general.thawBarLocationOnHotkey = true
            fixture.show(triggeredByHotkey: true)
            let moved = CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY)
            fixture.pointer.location = moved
            fixture.pointer.inEmptyMenuBarSpace = false
            fixture.resize(width: 160)

            #expect(abs(fixture.panel.frame.midX - moved.x) < 1)
            #expect(abs(fixture.panel.frame.midY - moved.y) < 1)
        }
    }

    private func withPanel(
        location: ThawBarLocation = .dynamic,
        showsIcon: Bool = false,
        _ body: (PlacementFixture) throws -> Void
    ) throws {
        let suite = "ThawBarPointerPlacementTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        let previousStore = Defaults.store
        let previousPolicy = NSApp.activationPolicy()
        Defaults.store = store
        defer {
            Defaults.store = previousStore
            store.removePersistentDomain(forName: suite)
            NSApp.setActivationPolicy(previousPolicy)
        }
        let fixture = try PlacementFixture(location: location, showsIcon: showsIcon)
        defer { fixture.panel.close() }
        try body(fixture)
    }
}

@MainActor
private struct PlacementFixture {
    final class Pointer {
        var location: CGPoint?
        var inEmptyMenuBarSpace = true
    }

    final class SizedView: NSView {
        var measuredSize = NSSize.zero

        override var intrinsicContentSize: NSSize {
            measuredSize
        }
    }

    let screen: NSScreen
    let appState: AppState
    let panel: ThawBarPanel
    let pointer = Pointer()

    init(location: ThawBarLocation, showsIcon: Bool) throws {
        screen = try #require(NSScreen.main)
        appState = AppState()
        appState.settings.general.showThawIcon = showsIcon
        appState.settings.general.thawBarLocationOnHotkey = false
        appState.settings.displaySettings.configurations = [:]
        appState.settings.displaySettings.globalConfiguration = .defaultConfiguration.withThawBarLocation(location)
        pointer.location = CGPoint(x: screen.frame.minX + screen.frame.width * 0.35, y: screen.frame.maxY - 10)
        let pointer = pointer
        panel = ThawBarPanel(
            pointerLocation: { pointer.location },
            pointerInEmptyMenuBarSpace: { _, _ in pointer.inEmptyMenuBarSpace }
        )
        panel.performSetup(with: appState)
    }

    func show(triggeredByHotkey: Bool = false, openedFrom iconFrame: CGRect? = nil) {
        // Companion presentation avoids section capture and global dismissal monitors.
        panel.show(
            section: .hidden, on: screen, triggeredByHotkey: triggeredByHotkey,
            presentation: .alongsideReveal, openedFrom: iconFrame
        )
    }

    func resize(width: CGFloat) {
        let view = SizedView()
        view.measuredSize = NSSize(width: width, height: 40)
        panel.contentView = view
        panel.resizeToContent(on: screen)
    }
}
