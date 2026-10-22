//
//  SectionDividerStyleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Section divider styles")
struct SectionDividerStyleTests {
    @Test("A revealed section draws its style's mark, and None draws nothing", arguments: SectionDividerStyle.allCases)
    func revealedSectionDrawsTheStyle(style: SectionDividerStyle) {
        let presentation = ControlItem.sectionDividerPresentation(state: .showSection, style: style)
        if let image = style.image {
            #expect(presentation == .shown(image))
        } else if style == .custom {
            #expect(presentation == .shown(.chevronSmall), "a Custom divider without an image shows the chevron")
        } else {
            #expect(style == .noDivider)
            #expect(presentation == .hidden)
        }
    }

    @Test("A hidden section never draws a divider", arguments: SectionDividerStyle.allCases)
    func hiddenSectionDrawsNothing(style: SectionDividerStyle) {
        #expect(ControlItem.sectionDividerPresentation(state: .hideSection, style: style) == .hidden)
    }

    @Test("Saved styles keep their numbers, so a saved choice survives an update")
    func rawValuesAreStable() {
        #expect(SectionDividerStyle.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(Set(SectionDividerStyle.allCases.compactMap(\.image)).count == 4, "each mark is its own image")
    }

    @Test("A Custom divider draws its chosen image while its section is open")
    func customDividerDrawsItsImage() {
        let mark = SectionDividerCustomMark(data: Data([1, 2, 3]), isTemplate: false)
        #expect(ControlItem.sectionDividerPresentation(state: .showSection, style: .custom, customMark: mark) == .custom(mark))
        #expect(ControlItem.sectionDividerPresentation(state: .hideSection, style: .custom, customMark: mark) == .hidden)
        #expect(ControlItem.sectionDividerPresentation(state: .showSection, style: .dot, customMark: mark) == .shown(.dividerDot),
                "an image chosen earlier doesn't override another style")
    }

    @MainActor
    @Test("The custom image and its appearance switch are saved")
    func customImageIsSaved() throws {
        try ScratchDefaults.withStore(named: "SectionDividerStyleTests") { store in
            let settings = AdvancedSettings()
            #expect(settings.customSectionDividerIsTemplate, "it matches the menu bar by default")
            settings.customSectionDividerImage = Data([9, 8, 7])
            settings.customSectionDividerIsTemplate = false
            #expect(store.data(forKey: "CustomSectionDividerImage") == Data([9, 8, 7]))
            settings.customSectionDividerImage = nil
            #expect(store.object(forKey: "CustomSectionDividerImage") == nil)
        }
    }
}

@Suite("A divider keeps its drag sliver only while a section is revealed")
struct DragSliverTests {
    @Test func keepsItWhenTheDragRevealedASection() {
        #expect(ControlItem.keepsDragSliver(showAllSectionsOnUserDrag: true, isDragging: true, revealedSection: .alwaysHidden))
    }

    /// 2026-10-22: with Native hiding the drag opens nothing, and both slivers
    /// showed at the left end of the visible icons.
    @Test func dropsItWhenTheDragRevealedNothing() {
        #expect(!ControlItem.keepsDragSliver(showAllSectionsOnUserDrag: true, isDragging: true, revealedSection: nil))
    }

    @Test func dropsItWithoutADrag() {
        #expect(ControlItem.keepsDragSliver(showAllSectionsOnUserDrag: true, isDragging: false, revealedSection: .hidden) == false)
    }

    @Test func dropsItWhenDragRevealIsOff() {
        #expect(ControlItem.keepsDragSliver(showAllSectionsOnUserDrag: false, isDragging: true, revealedSection: .hidden) == false)
    }
}
