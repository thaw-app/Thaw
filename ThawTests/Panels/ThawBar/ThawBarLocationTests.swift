//
//  ThawBarLocationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

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
