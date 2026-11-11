//
//  EngineConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The engine reads its settings through MenuBarEngineConfiguration, which must follow the settings models.
@MainActor
@Suite("Menu bar engine configuration", .serialized, .scratchDefaults)
struct EngineConfigurationTests {
    @Test("Reveal and rehide settings come from Visibility, the icon from General")
    func generalSettings() {
        let settings = AppSettings()
        let configuration: any MenuBarEngineConfiguration = settings
        settings.visibility.showOnClick = false
        settings.visibility.showOnHover = true
        settings.visibility.showOnScroll = false
        settings.visibility.autoRehide = false
        settings.visibility.rehideStrategy = .timed
        settings.visibility.rehideInterval = 42
        settings.visibility.tempShowInterval = 7
        settings.general.showThawIcon = false
        settings.general.simpleMode = true
        #expect(!configuration.showOnClick)
        #expect(configuration.showOnHover)
        #expect(!configuration.showOnScroll)
        #expect(!configuration.autoRehide)
        #expect(configuration.rehideStrategy == .timed)
        #expect(configuration.rehideInterval == 42)
        #expect(configuration.tempShowInterval == 7)
        #expect(!configuration.showThawIcon)
        #expect(configuration.simpleMode)
        #expect(configuration.thawIcon == settings.general.thawIcon)
        #expect(configuration.customThawIconIsTemplate == settings.general.customThawIconIsTemplate)
    }

    @Test("Item handling and presentation settings come from their pages' models")
    func pageSettings() {
        let settings = AppSettings()
        let configuration: any MenuBarEngineConfiguration = settings
        let layout = settings.layout
        let visibility = settings.visibility
        let general = settings.general
        visibility.showOnHoverDelay = 0.75
        visibility.tooltipDelay = 1.25
        layout.iconRefreshInterval = 3
        layout.menuBarOrderFulfillmentTimeout = 9
        general.hideApplicationMenus = !general.hideApplicationMenus
        visibility.showMenuBarTooltips = !visibility.showMenuBarTooltips
        general.enableSecondaryContextMenu = !general.enableSecondaryContextMenu
        layout.enableMenuBarItemOverflow = !layout.enableMenuBarItemOverflow
        layout.alwaysUseAppIconForMenuBarItems = !layout.alwaysUseAppIconForMenuBarItems
        layout.showAllSectionsOnUserDrag = !layout.showAllSectionsOnUserDrag
        visibility.swapOnThawIconClick = !visibility.swapOnThawIconClick
        #expect(configuration.showOnHoverDelay == 0.75)
        #expect(configuration.tooltipDelay == 1.25)
        #expect(configuration.iconRefreshInterval == 3)
        #expect(configuration.menuBarOrderFulfillmentTimeout == 9)
        #expect(configuration.hideApplicationMenus == general.hideApplicationMenus)
        #expect(configuration.showMenuBarTooltips == visibility.showMenuBarTooltips)
        #expect(configuration.enableSecondaryContextMenu == general.enableSecondaryContextMenu)
        #expect(configuration.enableMenuBarItemOverflow == layout.enableMenuBarItemOverflow)
        #expect(configuration.alwaysUseAppIconForMenuBarItems == layout.alwaysUseAppIconForMenuBarItems)
        #expect(configuration.showAllSectionsOnUserDrag == layout.showAllSectionsOnUserDrag)
        #expect(configuration.swapOnThawIconClick == visibility.swapOnThawIconClick)
        #expect(configuration.isAlwaysHiddenSectionEnabled == layout.isAlwaysHiddenSectionEnabled)
        #expect(configuration.enableExperimentalSystemItemHiding == layout.enableExperimentalSystemItemHiding)
        #expect(configuration.enableExperimentalOverflowPrevention == layout.enableExperimentalOverflowPrevention)
        #expect(configuration.sectionDividerStyle == layout.sectionDividerStyle)
    }

    @Test("A custom divider mark carries the chosen image and its template flag")
    func customDividerMark() {
        let settings = AppSettings()
        settings.layout.customSectionDividerImage = nil
        #expect(settings.customSectionDividerMark == nil)
        let data = Data([1, 2, 3])
        settings.layout.customSectionDividerImage = data
        settings.layout.customSectionDividerIsTemplate = true
        #expect(settings.customSectionDividerMark == SectionDividerCustomMark(data: data, isTemplate: true))
    }
}

/// The stand-in controller used before setup answers every question with "nothing under control".
@MainActor
@Suite("Inert section controller")
struct InertSectionControllerTests {
    @Test("Nothing is operational, revealed or assigned")
    func quietAnswers() {
        let controller = InertSectionController()
        #expect(!controller.isOperational)
        #expect(!controller.isHidingAvailable)
        #expect(!controller.isRestrictionApplied)
        #expect(controller.revealedSection == nil)
        #expect(controller.sectionAssignment.isEmpty)
        #expect(controller.section(for: "com.example.item") == .visible)
        #expect(controller.authoredSection(for: "com.example.item") == .visible)
        #expect(controller.snapshot(for: "com.example.item") == nil)
        #expect(controller.sectionItemOrder.isEmpty)
        #expect(controller.assignedSnapshotTags.isEmpty)
        #expect(controller.effectivelyConcealedIdentifiers.isEmpty)
        #expect(controller.overflowHiddenIdentifiers.isEmpty)
        #expect(!controller.shouldBridgeClockActivation)
        #expect(controller.repairGroupInvariantIfNeeded() == nil)
    }

    @Test("Every managed section reads as hidden, with no native overflow")
    func sectionsReadHidden() {
        let controller = InertSectionController()
        for name in MenuBarSectionName.allCases {
            #expect(controller.isSectionHidden(name))
        }
        #expect(!controller.isNativeOverflowActive(on: 1))
        #expect(controller.nativeOverflowControlBounds(on: 1).isEmpty)
    }

    @Test("Requests that need an engine are refused or ignored")
    func requestsRefused() {
        let controller = InertSectionController()
        #expect(!controller.beginClockActivationBridge(scope: .clockOnly))
        #expect(!controller.setOverflowHiddenIdentifiers(["a"]))
        #expect(!controller.setOverflowHiddenItems([]))
        #expect(!controller.pulseRestrictionAfterReflow(liveItems: []))
        #expect(!controller.refreshHidingAvailability())
        #expect(controller.displayOrdered([], in: .hidden).isEmpty)
        #expect(controller.ordered([], in: .hidden).isEmpty)
        controller.endClockActivationBridge()
        controller.resetAssignment(to: ["a": .hidden])
        controller.applyProfileLayout(itemSectionMap: ["a": "hidden"], itemOrder: [:])
        controller.show(.hidden, reconcileBoundary: true, synchronizeOrder: true)
        controller.hideRevealedSections()
        controller.revealItemTemporarily("a")
        controller.scheduleTemporaryItemConceal("a")
        controller.setSectionOrder(["a"], for: .hidden)
        controller.setSectionOrder(from: [], for: .hidden)
        controller.setSection(.hidden, identifier: "a")
        controller.concealTemporarilyRevealedItem("a")
        controller.concealItemTemporarily("a")
        controller.revealTransientlyConcealedItem("a")
        controller.regatherGroups()
        controller.notePreferredPositionsSelfWrite()
        controller.refresh(forceRestrictionPulse: true, forceReapply: true)
        // None of the requests above may leave anything assigned.
        #expect(controller.sectionAssignment.isEmpty)
        #expect(controller.revealedSection == nil)
    }
}
