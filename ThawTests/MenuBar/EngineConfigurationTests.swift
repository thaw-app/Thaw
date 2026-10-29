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
    @Test("Reveal and rehide settings come from General")
    func generalSettings() {
        let settings = AppSettings()
        let configuration: any MenuBarEngineConfiguration = settings
        settings.general.showOnClick = false
        settings.general.showOnHover = true
        settings.general.showOnScroll = false
        settings.general.autoRehide = false
        settings.general.rehideStrategy = .timed
        settings.general.rehideInterval = 42
        settings.general.tempShowInterval = 7
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

    @Test("Item handling and presentation settings come from Advanced")
    func advancedSettings() {
        let settings = AppSettings()
        let configuration: any MenuBarEngineConfiguration = settings
        let advanced = settings.advanced
        advanced.showOnHoverDelay = 0.75
        advanced.tooltipDelay = 1.25
        advanced.iconRefreshInterval = 3
        advanced.menuBarOrderFulfillmentTimeout = 9
        advanced.hideApplicationMenus = !advanced.hideApplicationMenus
        advanced.showMenuBarTooltips = !advanced.showMenuBarTooltips
        advanced.enableSecondaryContextMenu = !advanced.enableSecondaryContextMenu
        advanced.enableMenuBarItemOverflow = !advanced.enableMenuBarItemOverflow
        advanced.alwaysUseAppIconForMenuBarItems = !advanced.alwaysUseAppIconForMenuBarItems
        advanced.showAllSectionsOnUserDrag = !advanced.showAllSectionsOnUserDrag
        advanced.swapOnThawIconClick = !advanced.swapOnThawIconClick
        #expect(configuration.showOnHoverDelay == 0.75)
        #expect(configuration.tooltipDelay == 1.25)
        #expect(configuration.iconRefreshInterval == 3)
        #expect(configuration.menuBarOrderFulfillmentTimeout == 9)
        #expect(configuration.hideApplicationMenus == advanced.hideApplicationMenus)
        #expect(configuration.showMenuBarTooltips == advanced.showMenuBarTooltips)
        #expect(configuration.enableSecondaryContextMenu == advanced.enableSecondaryContextMenu)
        #expect(configuration.enableMenuBarItemOverflow == advanced.enableMenuBarItemOverflow)
        #expect(configuration.alwaysUseAppIconForMenuBarItems == advanced.alwaysUseAppIconForMenuBarItems)
        #expect(configuration.showAllSectionsOnUserDrag == advanced.showAllSectionsOnUserDrag)
        #expect(configuration.swapOnThawIconClick == advanced.swapOnThawIconClick)
        #expect(configuration.isAlwaysHiddenSectionEnabled == advanced.isAlwaysHiddenSectionEnabled)
        #expect(configuration.enableExperimentalSystemItemHiding == advanced.enableExperimentalSystemItemHiding)
        #expect(configuration.enableExperimentalOverflowPrevention == advanced.enableExperimentalOverflowPrevention)
        #expect(configuration.sectionDividerStyle == advanced.sectionDividerStyle)
    }

    @Test("A custom divider mark carries the chosen image and its template flag")
    func customDividerMark() {
        let settings = AppSettings()
        settings.advanced.customSectionDividerImage = nil
        #expect(settings.customSectionDividerMark == nil)
        let data = Data([1, 2, 3])
        settings.advanced.customSectionDividerImage = data
        settings.advanced.customSectionDividerIsTemplate = true
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
