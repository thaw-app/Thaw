//
//  MenuBarSectionGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

// MARK: - Table Rows

/// One row of the ``MenuBarSection/usableInlineWidth(from:screenFrameMinX:screenVisibleMaxX:notchFrame:)``
/// table.
private struct UsableWidthCase: Sendable, CustomStringConvertible {
    let name: String
    let appMenuRightEdge: CGFloat?
    let screenFrameMinX: CGFloat
    let screenVisibleMaxX: CGFloat
    let notchFrame: CGRect?
    let expected: CGFloat

    var description: String {
        name
    }

    var measured: CGFloat {
        MenuBarSection.usableInlineWidth(
            from: appMenuRightEdge,
            screenFrameMinX: screenFrameMinX,
            screenVisibleMaxX: screenVisibleMaxX,
            notchFrame: notchFrame
        )
    }
}

/// One row of the presentation-mode table.
private struct PresentationCase: Sendable, CustomStringConvertible {
    let name: String
    let totalItemsWidth: CGFloat
    let appMenuRightEdge: CGFloat?
    let screenFrameMinX: CGFloat
    let screenVisibleMaxX: CGFloat
    let notchFrame: CGRect?
    let allowHidingApplicationMenus: Bool
    let expected: MenuBarSection.PresentationMode

    var description: String {
        name
    }

    var measured: MenuBarSection.PresentationMode {
        MenuBarSection.presentationMode(
            totalItemsWidth: totalItemsWidth,
            appMenuRightEdge: appMenuRightEdge,
            screenFrameMinX: screenFrameMinX,
            screenVisibleMaxX: screenVisibleMaxX,
            notchFrame: notchFrame,
            allowHidingApplicationMenus: allowHidingApplicationMenus
        )
    }
}

// MARK: - Geometry Constants

/// A plain 1200-point screen whose application menus end at 300. Usable inline
/// width is 900; hiding the menus recovers the full 1200.
private enum PlainScreen {
    static let minX: CGFloat = 0
    static let maxX: CGFloat = 1200
    static let appMenuRightEdge: CGFloat = 300
}

/// A notched 1512-point screen with a 200-point notch centred at 656. Status
/// items have 632 contiguous points right of the notch; hiding application
/// menus cannot make macOS place them on the left side.
private enum NotchedScreen {
    static let minX: CGFloat = 0
    static let maxX: CGFloat = 1512
    static let appMenuRightEdge: CGFloat = 300
    static var notch: CGRect {
        CGRect(x: 656, y: 0, width: 200, height: 32)
    }
}

/// Orders the presentation modes from roomiest to most constrained.
private func constraintRank(of mode: MenuBarSection.PresentationMode) -> Int {
    switch mode {
    case .inline: 0
    case .inlineHidingApplicationMenus: 1
    case .iceBar: 2
    }
}

// MARK: - Tables

private let usableWidthCases: [UsableWidthCase] = [
    UsableWidthCase(
        name: "menus end mid-bar",
        appMenuRightEdge: 300,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1200,
        notchFrame: nil,
        expected: 900
    ),
    UsableWidthCase(
        name: "no application menus at all",
        appMenuRightEdge: nil,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1440,
        notchFrame: nil,
        expected: 1440
    ),
    UsableWidthCase(
        name: "no application menus on a screen to the right of the origin",
        appMenuRightEdge: nil,
        screenFrameMinX: 1440,
        screenVisibleMaxX: 2880,
        notchFrame: nil,
        expected: 1440
    ),
    UsableWidthCase(
        name: "menus reported left of the screen are clamped to its edge",
        appMenuRightEdge: -500,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1200,
        notchFrame: nil,
        expected: 1200
    ),
    UsableWidthCase(
        name: "menus reported left of an offset screen are clamped to its edge",
        appMenuRightEdge: -300,
        screenFrameMinX: 1000,
        screenVisibleMaxX: 2000,
        notchFrame: nil,
        expected: 1000
    ),
    UsableWidthCase(
        name: "menus running past the visible edge leave nothing",
        appMenuRightEdge: 1300,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1200,
        notchFrame: nil,
        expected: 0
    ),
    UsableWidthCase(
        name: "a notch leaves only its contiguous right side",
        appMenuRightEdge: 300,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1512,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        expected: 632
    ),
    UsableWidthCase(
        name: "menus that reach the notch's left gap leave only the right side",
        appMenuRightEdge: 700,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1512,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        expected: 632
    ),
    UsableWidthCase(
        name: "menus ending exactly at the notch's left gap leave only the right side",
        appMenuRightEdge: 632,
        screenFrameMinX: 0,
        screenVisibleMaxX: 1512,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        expected: 632
    ),
    UsableWidthCase(
        name: "a notch wider than the bar leaves nothing on either side",
        appMenuRightEdge: nil,
        screenFrameMinX: 0,
        screenVisibleMaxX: 900,
        notchFrame: CGRect(x: 0, y: 0, width: 900, height: 32),
        expected: 0
    ),
    UsableWidthCase(
        name: "a notch on a screen to the right of the origin",
        appMenuRightEdge: nil,
        screenFrameMinX: 1000,
        screenVisibleMaxX: 2000,
        notchFrame: CGRect(x: 1400, y: 0, width: 200, height: 32),
        expected: 376
    ),
]

private let presentationCases: [PresentationCase] = [
    PresentationCase(
        name: "items well inside the usable width",
        totalItemsWidth: 500,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: true,
        expected: .inline
    ),
    PresentationCase(
        name: "items exactly filling the usable width",
        totalItemsWidth: 900,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: true,
        expected: .inline
    ),
    PresentationCase(
        name: "items one point too wide",
        totalItemsWidth: 901,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: true,
        expected: .inlineHidingApplicationMenus
    ),
    PresentationCase(
        name: "items one point too wide with menu hiding disabled",
        totalItemsWidth: 901,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: false,
        expected: .iceBar
    ),
    PresentationCase(
        name: "items exactly filling the bar once the menus are gone",
        totalItemsWidth: 1200,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: true,
        expected: .inlineHidingApplicationMenus
    ),
    PresentationCase(
        name: "items one point wider than the whole bar",
        totalItemsWidth: 1201,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: true,
        expected: .iceBar
    ),
    PresentationCase(
        name: "items that would have fit without the menus, which may not be hidden",
        totalItemsWidth: 1200,
        appMenuRightEdge: PlainScreen.appMenuRightEdge,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: false,
        expected: .iceBar
    ),
    PresentationCase(
        name: "no application menus to hide, and the items overflow anyway",
        totalItemsWidth: 1201,
        appMenuRightEdge: nil,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: true,
        expected: .iceBar
    ),
    PresentationCase(
        name: "menus reported left of the screen still leave the full bar",
        totalItemsWidth: 1200,
        appMenuRightEdge: -300,
        screenFrameMinX: PlainScreen.minX,
        screenVisibleMaxX: PlainScreen.maxX,
        notchFrame: nil,
        allowHidingApplicationMenus: false,
        expected: .inline
    ),
    PresentationCase(
        name: "notched screen exactly filling the right side",
        totalItemsWidth: 632,
        appMenuRightEdge: NotchedScreen.appMenuRightEdge,
        screenFrameMinX: NotchedScreen.minX,
        screenVisibleMaxX: NotchedScreen.maxX,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        allowHidingApplicationMenus: true,
        expected: .inline
    ),
    PresentationCase(
        name: "notched screen cannot recover left-side space by hiding menus",
        totalItemsWidth: 633,
        appMenuRightEdge: NotchedScreen.appMenuRightEdge,
        screenFrameMinX: NotchedScreen.minX,
        screenVisibleMaxX: NotchedScreen.maxX,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        allowHidingApplicationMenus: true,
        expected: .iceBar
    ),
    PresentationCase(
        name: "notched screen filled exactly once the menus are gone",
        totalItemsWidth: 1264,
        appMenuRightEdge: NotchedScreen.appMenuRightEdge,
        screenFrameMinX: NotchedScreen.minX,
        screenVisibleMaxX: NotchedScreen.maxX,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        allowHidingApplicationMenus: true,
        expected: .iceBar
    ),
    PresentationCase(
        name: "notched screen overflowing even without the menus",
        totalItemsWidth: 1265,
        appMenuRightEdge: NotchedScreen.appMenuRightEdge,
        screenFrameMinX: NotchedScreen.minX,
        screenVisibleMaxX: NotchedScreen.maxX,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        allowHidingApplicationMenus: true,
        expected: .iceBar
    ),
    PresentationCase(
        name: "notched screen overflowing with menu hiding disabled",
        totalItemsWidth: 965,
        appMenuRightEdge: NotchedScreen.appMenuRightEdge,
        screenFrameMinX: NotchedScreen.minX,
        screenVisibleMaxX: NotchedScreen.maxX,
        notchFrame: CGRect(x: 656, y: 0, width: 200, height: 32),
        allowHidingApplicationMenus: false,
        expected: .iceBar
    ),
    PresentationCase(
        name: "a notch that swallows the bar, with nothing to show",
        totalItemsWidth: 0,
        appMenuRightEdge: nil,
        screenFrameMinX: 0,
        screenVisibleMaxX: 900,
        notchFrame: CGRect(x: 0, y: 0, width: 900, height: 32),
        allowHidingApplicationMenus: true,
        expected: .inline
    ),
    PresentationCase(
        name: "a notch that swallows the bar, with a single point to show",
        totalItemsWidth: 1,
        appMenuRightEdge: nil,
        screenFrameMinX: 0,
        screenVisibleMaxX: 900,
        notchFrame: CGRect(x: 0, y: 0, width: 900, height: 32),
        allowHidingApplicationMenus: true,
        expected: .iceBar
    ),
]

// MARK: - MenuBarSection Geometry Tests

/// Covers the two pure geometry statics on ``MenuBarSection``:
/// `usableInlineWidth(from:screenFrameMinX:screenVisibleMaxX:notchFrame:)` and
/// `presentationMode(totalItemsWidth:appMenuRightEdge:screenFrameMinX:screenVisibleMaxX:notchFrame:allowHidingApplicationMenus:)`.
///
/// Both take plain numbers, so every case here is a fixed screen description
/// rather than whatever displays this machine happens to have. The instance
/// half of `MenuBarSection` -- `show`, `hide`, `toggle`,
/// `updateControlItemState`, and the rehide task and monitor -- is out of reach
/// without a live `ControlItem`/`NSStatusItem` and an `NSScreen`.
///
/// `Name`, `notchGap`, and the coarse presentation-mode cases live in
/// `MenuBarSectionNameTests`; `forcesIceBarForNotchOverflow` lives in
/// `NotchOverflowRevealTests`.
@Suite("Menu bar section geometry")
struct MenuBarSectionGeometryTests {
    // MARK: - Usable Inline Width

    @Suite("Usable inline width")
    struct UsableInlineWidthTests {
        @Test("The usable inline width is measured as described", arguments: usableWidthCases)
        fileprivate func usableWidth(testCase: UsableWidthCase) {
            #expect(testCase.measured == testCase.expected)
        }

        @Test("The usable inline width is never negative", arguments: usableWidthCases)
        fileprivate func usableWidthIsNeverNegative(testCase: UsableWidthCase) {
            // Both subtractions can go negative on a real display -- the menus
            // can overhang the visible frame, and the notch's left gap can
            // start left of the screen -- and a negative side would read as
            // extra room once it was summed with the other side.
            #expect(testCase.measured >= 0)
        }

        @Test("A notch exposes only the contiguous region on its right")
        func aNotchUsesOnlyItsRightSide() {
            let withNotch = MenuBarSection.usableInlineWidth(
                from: NotchedScreen.appMenuRightEdge,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch
            )

            #expect(
                withNotch
                    == NotchedScreen.maxX - NotchedScreen.notch.maxX - MenuBarSection.notchGap
            )
        }

        @Test("Hiding the application menus can only ever add space")
        func droppingTheApplicationMenusNeverCosts() {
            // `presentationMode` re-measures with the menus collapsed onto the
            // screen's left edge and assumes the second number is the larger
            // one. If it were not, an item set that already fit could be
            // pushed into the Thaw Bar.
            for testCase in usableWidthCases {
                let withoutMenus = MenuBarSection.usableInlineWidth(
                    from: testCase.screenFrameMinX,
                    screenFrameMinX: testCase.screenFrameMinX,
                    screenVisibleMaxX: testCase.screenVisibleMaxX,
                    notchFrame: testCase.notchFrame
                )

                #expect(withoutMenus >= testCase.measured, "\(testCase.name)")
            }
        }

        @Test("Hiding application menus adds no inline status-item space around a notch")
        func droppingMenusDoesNotAddNotchCapacity() {
            let withMenus = MenuBarSection.usableInlineWidth(
                from: NotchedScreen.appMenuRightEdge,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch
            )
            let withoutMenus = MenuBarSection.usableInlineWidth(
                from: NotchedScreen.minX,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch
            )

            #expect(withMenus == withoutMenus)
        }

        @Test("An absent application menu frame is measured like one at the screen's left edge")
        func absentMenuFrameMatchesTheScreenEdge() {
            // `presentationMode` relies on this equivalence when it re-measures
            // with the menus hidden: it passes `screenFrameMinX` where the
            // first measurement passed `nil`.
            let absent = MenuBarSection.usableInlineWidth(
                from: nil,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch
            )
            let atEdge = MenuBarSection.usableInlineWidth(
                from: NotchedScreen.minX,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch
            )

            #expect(absent == atEdge)
        }
    }

    // MARK: - Presentation Mode

    @Suite("Presentation mode")
    struct PresentationModeTests {
        @Test("The presentation mode is chosen as described", arguments: presentationCases)
        fileprivate func presentationMode(testCase: PresentationCase) {
            #expect(testCase.measured == testCase.expected)
        }

        @Test("A width equal to the usable width still counts as fitting")
        func equalityFitsInline() {
            // The comparison is `<=`. An item set measured at exactly the
            // usable width is already laid out on the bar, so treating it as
            // an overflow would flap between inline and the Thaw Bar on every
            // measurement.
            let usable = MenuBarSection.usableInlineWidth(
                from: NotchedScreen.appMenuRightEdge,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch
            )

            let atWidth = MenuBarSection.presentationMode(
                totalItemsWidth: usable,
                appMenuRightEdge: NotchedScreen.appMenuRightEdge,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch,
                allowHidingApplicationMenus: true
            )
            let justOver = MenuBarSection.presentationMode(
                totalItemsWidth: usable.nextUp,
                appMenuRightEdge: NotchedScreen.appMenuRightEdge,
                screenFrameMinX: NotchedScreen.minX,
                screenVisibleMaxX: NotchedScreen.maxX,
                notchFrame: NotchedScreen.notch,
                allowHidingApplicationMenus: true
            )

            #expect(atWidth == .inline)
            #expect(justOver != .inline)
        }

        @Test("Hiding the application menus is never proposed when the setting is off")
        func hidingIsNeverProposedWhenDisabled() {
            // The guard sits between the two measurements, so a "no" has to
            // reach `.iceBar` without the wider bar ever being considered.
            for width in stride(from: CGFloat(0), through: 2000, by: 125) {
                let mode = MenuBarSection.presentationMode(
                    totalItemsWidth: width,
                    appMenuRightEdge: PlainScreen.appMenuRightEdge,
                    screenFrameMinX: PlainScreen.minX,
                    screenVisibleMaxX: PlainScreen.maxX,
                    notchFrame: nil,
                    allowHidingApplicationMenus: false
                )

                #expect(mode != .inlineHidingApplicationMenus, "width: \(width)")
            }
        }

        @Test("Widening the item set never recovers a roomier mode")
        func modeDegradesMonotonically() {
            // Everything downstream assumes the decision is monotonic in the
            // item width. A non-monotonic rule would let one more item pull the
            // section back out of the Thaw Bar.
            var previousRank = 0
            for width in stride(from: CGFloat(0), through: 1600, by: 25) {
                let mode = MenuBarSection.presentationMode(
                    totalItemsWidth: width,
                    appMenuRightEdge: NotchedScreen.appMenuRightEdge,
                    screenFrameMinX: NotchedScreen.minX,
                    screenVisibleMaxX: NotchedScreen.maxX,
                    notchFrame: NotchedScreen.notch,
                    allowHidingApplicationMenus: true
                )
                let rank = constraintRank(of: mode)

                #expect(rank >= previousRank, "width: \(width)")
                previousRank = rank
            }
        }
    }
}
