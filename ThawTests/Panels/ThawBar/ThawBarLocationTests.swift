//
//  ThawBarLocationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Thaw Bar pointer placement", .serialized, .scratchDefaults)
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
            fixture.appState.settings.thawBar.thawBarLocationOnHotkey = true
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
        let previousPolicy = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(previousPolicy) }
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
        appState.settings.thawBar.thawBarLocationOnHotkey = false
        appState.settings.displaySettings.configurations = [:]
        appState.settings.displaySettings.globalConfiguration = .defaultConfiguration.withThawBarLocation(location)
        pointer.location = CGPoint(x: screen.frame.minX + screen.frame.width * 0.35, y: screen.frame.maxY - 10)
        let pointer = pointer
        panel = ThawBarPanel(
            pointerLocation: { pointer.location },
            pointerInEmptyMenuBarSpace: { _, _ in pointer.inEmptyMenuBarSpace }
        )
        panel.performSetup(
            with: appState,
            displayInvalidations: Empty<Void, Never>(completeImmediately: false),
            displaySettlements: Empty<EnvironmentChange, Never>(completeImmediately: false)
        )
    }

    func show(triggeredByHotkey: Bool = false, openedFrom iconFrame: CGRect? = nil) {
        // Folder presentation avoids section capture.
        panel.show(
            section: .hidden,
            on: screen,
            triggeredByHotkey: triggeredByHotkey,
            presentation: .folder,
            openedFrom: iconFrame
        )
    }

    func resize(width: CGFloat) {
        let view = SizedView()
        view.measuredSize = NSSize(width: width, height: 40)
        panel.contentView = view
        panel.resizeToContent(on: screen)
    }
}

@Suite("Thaw Bar location")
struct ThawBarLocationTests {
    // MARK: - Stored values

    @Test(
        "Saved location numbers keep the placement they had before the labels changed",
        arguments: [
            (0, ThawBarLocation.dynamic),
            (1, .mousePointer),
            (2, .thawIcon),
            (3, .leftAligned),
            (4, .rightAligned),
        ]
    )
    func storedRawValues(raw: Int, location: ThawBarLocation) {
        #expect(ThawBarLocation(rawValue: raw) == location)
        #expect(location.rawValue == raw)
    }

    @Test("A saved display configuration decodes to the same location", arguments: ThawBarLocation.allCases)
    func savedConfigurationDecodes(location: ThawBarLocation) throws {
        let json = """
        {"useIceBar": true, "iceBarLocation": \(location.rawValue), "alwaysShowHiddenItems": false}
        """
        let decoded = try JSONDecoder().decode(DisplayThawBarConfiguration.self, from: Data(json.utf8))
        #expect(decoded.thawBarLocation == location)
    }

    @Test("Link values written for the old labels still choose the same location")
    func oldLinkValues() {
        #expect(ThawBarLocation.fromString("dynamic") == .dynamic)
        #expect(ThawBarLocation.fromString("mousePointer") == .mousePointer)
        #expect(ThawBarLocation.fromString("thawIcon") == .thawIcon)
        #expect(ThawBarLocation.fromString("iceIcon") == .thawIcon)
        #expect(ThawBarLocation.fromString("leftAligned") == .leftAligned)
        #expect(ThawBarLocation.fromString("rightAligned") == .rightAligned)
    }

    @Test("The default for new installs is still Pointer or Thaw icon")
    func defaultUnchanged() {
        #expect(Defaults.DefaultValue.thawBarLocation == .dynamic)
        #expect(DisplayThawBarConfiguration.defaultConfiguration.thawBarLocation == .dynamic)
    }

    // MARK: - Shortcut placement

    @Test("The shortcut choice reads and writes the saved switch unchanged", arguments: [false, true])
    func shortcutPlacementRoundTrip(opensAtPointer: Bool) {
        let placement = ThawBarShortcutPlacement(opensAtPointer: opensAtPointer)
        #expect(placement.opensAtPointer == opensAtPointer)
    }

    @Test("A saved switch that was on opens at the pointer; off follows Location")
    func shortcutPlacementMeaning() {
        #expect(ThawBarShortcutPlacement(opensAtPointer: true) == .pointer)
        #expect(ThawBarShortcutPlacement(opensAtPointer: false) == .location)
        #expect(Defaults.DefaultValue.thawBarLocationOnHotkey == false)
    }

    @Test("Each location and shortcut choice has its own label")
    func labelsAreDistinct() {
        #expect(Set(ThawBarLocation.allCases.map { "\($0.localized)" }).count == ThawBarLocation.allCases.count)
        #expect(Set(ThawBarShortcutPlacement.allCases.map { "\($0.localized)" }).count == ThawBarShortcutPlacement.allCases.count)
    }

    // MARK: - Resolution

    @Test("Pointer or Thaw icon opens under the pointer only when it is on empty menu bar space")
    func dynamicResolution() {
        #expect(ThawBarPanel.concreteLocation(
            for: .dynamic, pointerInEmptyMenuBarSpace: true, hasPointerLocation: true, showsThawIcon: true
        ) == .mousePointer)
        #expect(ThawBarPanel.concreteLocation(
            for: .dynamic, pointerInEmptyMenuBarSpace: false, hasPointerLocation: true, showsThawIcon: true
        ) == .thawIcon)
        #expect(ThawBarPanel.concreteLocation(
            for: .dynamic, pointerInEmptyMenuBarSpace: false, hasPointerLocation: true, showsThawIcon: false
        ) == nil, "a hidden icon sends the bar to the right edge")
    }

    @Test("Under the pointer stays under the pointer wherever it is, and uses the icon only without a pointer")
    func pointerResolution() {
        #expect(ThawBarPanel.concreteLocation(
            for: .mousePointer, pointerInEmptyMenuBarSpace: false, hasPointerLocation: true, showsThawIcon: true
        ) == .mousePointer)
        #expect(ThawBarPanel.concreteLocation(
            for: .mousePointer, pointerInEmptyMenuBarSpace: false, hasPointerLocation: false, showsThawIcon: true
        ) == .thawIcon)
    }

    @Test("Under the Thaw icon falls back to the right edge when the icon is hidden")
    func iconResolution() {
        #expect(ThawBarPanel.concreteLocation(
            for: .thawIcon, pointerInEmptyMenuBarSpace: true, hasPointerLocation: true, showsThawIcon: true
        ) == .thawIcon)
        #expect(ThawBarPanel.concreteLocation(
            for: .thawIcon, pointerInEmptyMenuBarSpace: true, hasPointerLocation: true, showsThawIcon: false
        ) == nil)
    }

    @Test("The edges ignore the pointer and the icon", arguments: [ThawBarLocation.leftAligned, .rightAligned])
    func edgeResolution(location: ThawBarLocation) {
        for inEmptySpace in [true, false] {
            for showsIcon in [true, false] {
                #expect(ThawBarPanel.concreteLocation(
                    for: location, pointerInEmptyMenuBarSpace: inEmptySpace, hasPointerLocation: true, showsThawIcon: showsIcon
                ) == location)
            }
        }
    }
}
