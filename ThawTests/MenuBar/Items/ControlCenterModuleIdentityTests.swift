//
//  ControlCenterModuleIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers the misattributed-Control-Center-module identity: the predicate
/// that recognizes a module title under a foreign namespace, the detector
/// the prune runs on it, and the saved-order repair that drops such entries
/// at load.
///
/// A multi-display spatial skew can match Control Center's Battery window to
/// another app's PID, persisting `com.techsmith.snagit.capturehelper:Battery`
/// (#1027). Every other guard passes, so only the title says who owns the window.
@Suite("Misattributed Control Center module identity")
struct ControlCenterModuleIdentityTests {
    private func tag(namespace: String, title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(namespace), title: title)
    }

    // MARK: - isControlCenterModuleTitle

    /// Every module macOS itself titles, in the spelling it titles them.
    @Test("Every catalogued module title is recognized")
    func cataloguedTitlesAreRecognized() {
        let titles = [
            "Accessibility",
            "AudioVideoModule",
            "Battery",
            "Bluetooth",
            "BentoBox",
            "Clock",
            "Display",
            "FaceTime",
            "FocusModes",
            "Hearing",
            "KeyboardBrightness",
            "MusicRecognition",
            "NowPlaying",
            "ScreenMirroring",
            "Sound",
            "WiFi",
        ]
        for title in titles {
            #expect(
                MenuBarItemTag.isControlCenterModuleTitle(title),
                "\(title) is a Control Center module title and must be recognized"
            )
        }
    }

    /// BentoBox modules carry an instance suffix, so membership is a prefix test.
    @Test("BentoBox instance suffixes are recognized")
    func bentoBoxSuffixesAreRecognized() {
        #expect(MenuBarItemTag.isControlCenterModuleTitle("BentoBox-0"))
        #expect(MenuBarItemTag.isControlCenterModuleTitle("BentoBox-12"))
    }

    /// Generic slots and third-party titles are not Control Center modules.
    /// Snagit's own item really is `com.techsmith.snagit.capturehelper:Item-0`.
    @Test("Generic and app titles are not module titles")
    func genericTitlesAreNotModuleTitles() {
        #expect(!MenuBarItemTag.isControlCenterModuleTitle("Item-0"))
        #expect(!MenuBarItemTag.isControlCenterModuleTitle("battery"))
        #expect(!MenuBarItemTag.isControlCenterModuleTitle("Wi-Fi"))
        #expect(!MenuBarItemTag.isControlCenterModuleTitle(""))
        #expect(!MenuBarItemTag.isControlCenterModuleTitle("CPU_bar_chart"))
    }

    // MARK: - isMisattributedControlCenterModule

    /// The field case: Battery resolved to Snagit's helper PID, so the
    /// namespace names Snagit while the title names Apple's module.
    @Test("A module title under a third-party namespace is misattributed")
    func moduleUnderThirdPartyNamespaceIsMisattributed() {
        #expect(tag(namespace: "com.techsmith.snagit.capturehelper", title: "Battery")
            .isMisattributedControlCenterModule)
        #expect(tag(namespace: "eu.exelban.Stats", title: "WiFi")
            .isMisattributedControlCenterModule)
    }

    /// Control Center's own modules resolve to its PID and namespace and must
    /// stay manageable.
    @Test("A module under Control Center's namespace is not misattributed")
    func moduleUnderControlCenterNamespaceIsNotMisattributed() {
        #expect(!MenuBarItemTag(namespace: .controlCenter, title: "Battery")
            .isMisattributedControlCenterModule)
        #expect(!MenuBarItemTag(namespace: .controlCenter, title: "WiFi")
            .isMisattributedControlCenterModule)
    }

    /// A third-party app's generic slot is indistinguishable from a
    /// misattributed one by title alone; the predicate must not claim it.
    @Test("A generic slot under a third-party namespace is not misattributed")
    func genericSlotUnderThirdPartyNamespaceIsNotMisattributed() {
        #expect(!tag(namespace: "com.techsmith.snagit.capturehelper", title: "Item-0")
            .isMisattributedControlCenterModule)
        #expect(!tag(namespace: "com.tunabellysoftware.tgpro", title: "Item-0")
            .isMisattributedControlCenterModule)
    }

    /// Thaw's control items and spacers never carry a module title.
    @Test("Control items and spacers are not misattributed")
    func controlItemsAndSpacersAreNotMisattributed() {
        #expect(!MenuBarItemTag.visibleControlItem.isMisattributedControlCenterModule)
        #expect(!MenuBarItemTag.hiddenControlItem.isMisattributedControlCenterModule)
        #expect(!MenuBarItemTag.alwaysHiddenControlItem.isMisattributedControlCenterModule)
        #expect(!tag(namespace: "com.stonerl.Thaw", title: "Spacer.1234.autosaveName")
            .isMisattributedControlCenterModule)
    }

    // MARK: - canonicalControlCenterModuleIdentifier

    /// The rewrite moves only the namespace and keeps the title verbatim.
    @Test("The field entry heals to Control Center's namespace")
    func fieldEntryHeals() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.techsmith.snagit.capturehelper:Battery"
            ) == "com.apple.controlcenter:Battery"
        )
    }

    /// Two BentoBox modules keep their distinct spellings.
    @Test("Instance indexes survive the rewrite")
    func instanceIndexSurvivesRewrite() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.electron.dockerdesktop:BentoBox-1:2"
            ) == "com.apple.controlcenter:BentoBox-1:2"
        )
    }

    /// An en-GB machine writes `Control Centre:Battery` beside the canonical
    /// spelling (#949); the rewrite merges it instead of leaving it for the prune.
    @Test("A display-name namespace heals to the canonical spelling")
    func displayNameNamespaceHeals() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "Control Centre:Battery"
            ) == "com.apple.controlcenter:Battery"
        )
    }

    /// Control Center's own entries, generic slots, app-titled items, and
    /// untitled identifiers pass through unchanged.
    @Test("Everything else passes through untouched")
    func everythingElsePassesThrough() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.apple.controlcenter:WiFi"
            ) == "com.apple.controlcenter:WiFi"
        )
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.techsmith.snagit.capturehelper:Item-0"
            ) == "com.techsmith.snagit.capturehelper:Item-0"
        )
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "eu.exelban.Stats:CPU_bar_chart"
            ) == "eu.exelban.Stats:CPU_bar_chart"
        )
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.apple.controlcenter"
            ) == "com.apple.controlcenter"
        )
    }

    // MARK: - Load-time repair seams

    /// ``LayoutSolver/canonicalIdentifier(_:)`` runs over saved orders at load
    /// and must leave the ghost to the prune; renaming it would duplicate the entry.
    @Test("canonicalIdentifier leaves the ghost for the prune")
    func canonicalIdentifierLeavesGhostAlone() {
        #expect(
            LayoutSolver.canonicalIdentifier("com.techsmith.snagit.capturehelper:Battery")
                == "com.techsmith.snagit.capturehelper:Battery"
        )
    }

    /// The prune recognizes the ghost by title alone. The live module often
    /// resolves nil, so the genuine `com.apple.controlcenter:Battery` may never
    /// have been saved for the twin rule to find.
    @Test("prunedSectionOrder drops the ghost with no twin present")
    func prunedSectionOrderDropsGhostWithoutTwin() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "alwaysHidden": [
                "com.nextcloud.desktopclient:Item-0",
                "com.techsmith.snagit.capturehelper:Battery",
                "ru.yandex.desktop.disk2:Item-0",
            ],
        ])
        #expect(pruned["alwaysHidden"] == [
            "com.nextcloud.desktopclient:Item-0",
            "ru.yandex.desktop.disk2:Item-0",
        ])
    }

    /// The genuine spelling survives wherever the ghost sits. The ghost must
    /// not count as owner of "Battery", or the provisional-duplicate rule
    /// would delete the genuine entry instead.
    @Test("The genuine module entry survives its misattributed twin")
    func genuineEntrySurvivesMisattributedTwin() {
        let genuine = "com.apple.controlcenter:Battery"
        let ghost = "com.techsmith.snagit.capturehelper:Battery"

        let together = LayoutSolver.prunedSectionOrder(["visible": [ghost, genuine]])
        #expect(together["visible"] == [genuine])

        let acrossSections = LayoutSolver.prunedSectionOrder([
            "hidden": [ghost],
            "alwaysHidden": [genuine],
        ])
        #expect(acrossSections["hidden"] == [])
        #expect(acrossSections["alwaysHidden"] == [genuine])
    }

    /// Snagit's own item really is `com.techsmith.snagit.capturehelper:Item-0`,
    /// and the prune must not orphan it.
    @Test("A generic slot under a foreign namespace survives the prune")
    func genericSlotSurvivesPrune() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "hidden": ["com.techsmith.snagit.capturehelper:Item-0"],
        ])
        #expect(pruned["hidden"] == ["com.techsmith.snagit.capturehelper:Item-0"])
    }
}
