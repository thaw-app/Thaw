//
//  DisplaySpatialSelectorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Observation
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// Stops a test that needs a display when this Mac has none, as a headless runner does.
@MainActor
func requireDisplay() throws {
    guard !NSScreen.managedScreens.isEmpty else {
        try Test.cancel("This Mac has no display")
    }
}

/// The display arrangement drawn off screen. Identify is looked for and never pressed, since it
/// flashes a panel on every connected display.
@MainActor
@Suite("Display selector", .serialized, .scratchDefaults)
struct DisplaySpatialSelectorTests {
    @Observable
    final class Selection {
        var id: String?
        init(_ id: String? = nil) {
            self.id = id
        }
    }

    private typealias Page = OffscreenRender<AnyView>
    private static let size = CGSize(width: 520, height: 240)

    private static let studio = DisplaySettingsManager.DisplayInfo(
        id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", displayID: nil, name: "Studio", hasNotch: true, isConnected: false
    )
    private static let office = DisplaySettingsManager.DisplayInfo(
        id: "11111111-2222-3333-4444-555555555555", displayID: nil, name: "Office", hasNotch: false, isConnected: false
    )

    private func render(_ displays: [DisplaySettingsManager.DisplayInfo], selection: Selection) -> Page {
        let view = DisplaySpatialSelector(
            displays: displays,
            selectedDisplayID: Binding(get: { selection.id }, set: { selection.id = $0 })
        )
        .frame(width: Self.size.width, height: Self.size.height)
        return OffscreenRender(AnyView(view), size: Self.size)
    }

    private func drawn(_ page: Page) async {
        await page.settle { (try? page.pixels())?.contains { $0 != 0 } == true }
    }

    private func isEnabled(_ element: NSObject) -> Bool {
        (element.value(forKey: "accessibilityEnabled") as? Bool) == true
    }

    @Test("Saved displays that are not connected sit in the picker, which shows the one chosen")
    func disconnectedPicker() async throws {
        let selection = Selection()
        let page = render([Self.studio, Self.office], selection: selection)
        await drawn(page)
        func pickerValue() -> String? {
            page.elements(role: .popUpButton, label: "Not connected").first.flatMap {
                OffscreenAccessibility.string("accessibilityValue", of: $0)
            }
        }
        #expect(pickerValue() == "None")
        let identify = try #require(page.elements(role: .button, label: "Identify").first)
        #expect(!isEnabled(identify), "with nothing connected there is nothing to flash")

        selection.id = Self.office.id
        await page.settle { pickerValue() == "Office" }
        #expect(pickerValue() == "Office", "the chosen saved display is the one shown")

        selection.id = "unknown"
        await page.settle { pickerValue() == "None" }
        #expect(pickerValue() == "None", "a choice that is not a saved display shows None")
    }

    @Test("With every display connected there is no picker for saved ones")
    func noPickerWithoutSavedDisplays() async throws {
        let page = render([], selection: Selection())
        await drawn(page)
        #expect(page.elements(role: .popUpButton, label: "Not connected").isEmpty)
    }

    @Test("Each connected display is a button that selects it, numbered as Identify numbers it")
    func connectedThumbnails() async throws {
        try requireDisplay()
        let settings = DisplaySettingsManager()
        let connected = settings.connectedDisplays()
        try #require(!connected.isEmpty)
        let selection = Selection(connected[0].id)
        let numbers = DisplayIdentifyOverlay.displayNumbers()
        let page = render(connected + [Self.studio], selection: selection)
        await drawn(page)

        for display in connected {
            let button = try #require(page.elements(role: .button, label: display.name).first)
            let value = OffscreenAccessibility.string("accessibilityValue", of: button) ?? ""
            let number = try #require(display.displayID.flatMap { numbers[$0] })
            #expect(value.contains("Display \(number)"), "\(display.name) says its number")
            #expect(value.contains("Notch") == display.hasNotch)
        }
        let identify = try #require(page.elements(role: .button, label: "Identify").first)
        #expect(isEnabled(identify))

        let last = try #require(connected.last)
        try page.press(last.name)
        #expect(selection.id == last.id, "pressing a thumbnail selects that display")
    }
}

@MainActor
@Suite("Display identify overlay")
struct DisplayIdentifyOverlayTests {
    @Test("Connected displays are numbered from the left, one number each")
    func numbersRunLeftToRight() throws {
        try requireDisplay()
        let screens = NSScreen.managedScreens
        let numbers = DisplayIdentifyOverlay.displayNumbers()
        #expect(Set(numbers.values) == Set(1 ... screens.count))
        for left in screens {
            for right in screens where left.frame.minX < right.frame.minX {
                #expect(numbers[left.displayID] ?? 0 < numbers[right.displayID] ?? 0, "a display further left has the lower number")
            }
        }
    }
}
