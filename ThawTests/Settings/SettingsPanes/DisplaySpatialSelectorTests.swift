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
        #expect(!page.elements(role: .button, label: "Identify").isEmpty, "the selector is drawn")
        #expect(page.elements(role: .popUpButton, label: "Not connected").isEmpty)
    }

    @Test("Each connected display is a button that selects it, numbered as Identify numbers it")
    func connectedThumbnails() async throws {
        try requireDisplay()
        let settings = DisplaySettingsManager()
        let connected = settings.connectedDisplays()
        try #require(!connected.isEmpty)
        // Nothing is selected to begin with, so a press that did nothing cannot pass on a Mac with one display.
        let selection = Selection()
        let numbers = DisplayIdentifyOverlay.displayNumbers()
        let page = render(connected + [Self.studio], selection: selection)
        await drawn(page)
        let identify = try #require(page.elements(role: .button, label: "Identify").first)
        #expect(isEnabled(identify))

        for display in connected {
            // Two displays can share a name, so the thumbnail is found by its number too.
            let number = try #require(display.displayID.flatMap { numbers[$0] })
            let button = try #require(page.elements(role: .button, label: display.name).first {
                OffscreenAccessibility.string("accessibilityValue", of: $0)?.hasSuffix("Display \(number)") == true
            }, "\(display.name) says its number")
            let value = OffscreenAccessibility.string("accessibilityValue", of: button) ?? ""
            #expect(value.contains("Notch") == display.hasNotch)

            OffscreenAccessibility.press(button)
            #expect(selection.id == display.id, "pressing a thumbnail selects that display")
        }
    }
}

/// The arrangement's geometry on made-up desks, so it is checked on a Mac with one display or none.
@Suite("Display thumbnail layout")
struct DisplayThumbnailLayoutTests {
    private typealias Placement = DisplayThumbnailLayout.Placement

    /// A wide display with its lower left corner at the origin, and a square one to its right that sits higher.
    private static let desk = [
        (id: "wide", frame: CGRect(x: 0, y: 0, width: 2000, height: 1000)),
        (id: "square", frame: CGRect(x: 2000, y: 500, width: 1000, height: 1000)),
    ]

    @Test("Displays keep their places and relative sizes, with the higher one drawn nearer the top")
    func fitsTheHeight() {
        let layout = DisplayThumbnailLayout.placements(for: Self.desk, canvasHeight: 60, maxWidth: 1000)
        #expect(layout.size == CGSize(width: 120, height: 60))
        #expect(layout.placements == [
            Placement(id: "wide", rect: CGRect(x: 0, y: 20, width: 80, height: 40)),
            Placement(id: "square", rect: CGRect(x: 80, y: 0, width: 40, height: 40)),
        ])
    }

    @Test("A desk too wide for the pane shrinks to its width, and a display left of the main one starts at the edge")
    func fitsTheWidth() {
        let desk = Self.desk.map { (id: $0.id, frame: $0.frame.offsetBy(dx: -2000, dy: 0)) }
        let layout = DisplayThumbnailLayout.placements(for: desk, canvasHeight: 60, maxWidth: 60)
        #expect(layout.size == CGSize(width: 60, height: 30))
        #expect(layout.placements.map(\.rect.minX) == [0, 40])
    }

    @Test("No displays, or displays with no area, draw nothing")
    func emptyDesk() {
        #expect(DisplayThumbnailLayout.placements(for: [], canvasHeight: 60, maxWidth: 60).size == .zero)
        let flat = DisplayThumbnailLayout.placements(for: [(id: "flat", frame: .zero)], canvasHeight: 60, maxWidth: 60)
        #expect(flat.placements.isEmpty && flat.size == .zero)
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
