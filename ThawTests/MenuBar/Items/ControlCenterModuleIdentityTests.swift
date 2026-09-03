//
//  ControlCenterModuleIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers the misattributed-Control-Center-module identity: the predicate
/// that recognizes a module title under a foreign namespace, the detector
/// the prune runs on it, and the saved-order repair that drops such entries
/// at load.
///
/// #1027's reporter carried `com.techsmith.snagit.capturehelper:Battery` in
/// their profile. A multi-display spatial skew in the source-PID resolution
/// matched Control Center's Battery window to Snagit's helper; the resolved
/// PID named the namespace, and the identifier persisted — every existing
/// guard passed, because the PID did resolve (not provisional), the title
/// was not a generic slot (not transient), and one wrong PID is not a
/// majority event (#784's gate stayed quiet by design). Only the title says
/// who owns the window.
@Suite("Misattributed Control Center module identity")
struct ControlCenterModuleIdentityTests {
    private func tag(namespace: String, title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(namespace), title: title)
    }

    // MARK: - isControlCenterModuleTitle

    /// Every module macOS itself titles, in the spelling it titles them.
    /// The set is the predicate's whole truth, so pin its members.
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

    /// BentoBox modules carry an instance suffix; membership is a prefix
    /// test there. The reporter's bar held `BentoBox-0` alongside the
    /// corrupted Battery entry.
    @Test("BentoBox instance suffixes are recognized")
    func bentoBoxSuffixesAreRecognized() {
        #expect(MenuBarItemTag.isControlCenterModuleTitle("BentoBox-0"))
        #expect(MenuBarItemTag.isControlCenterModuleTitle("BentoBox-12"))
    }

    /// Generic slots and third-party titles are not Control Center modules.
    /// `Item-0` is the case the rewrite must leave alone: Snagit's own item
    /// really is `com.techsmith.snagit.capturehelper:Item-0`, and guessing
    /// there would orphan a real item.
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

    /// Control Center's own modules resolve to Control Center's PID and
    /// namespace — the resolved reading, which must stay manageable.
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

    /// Thaw's own control items never carry a module title, and neither do
    /// its spacers; the predicate must stay quiet for both.
    @Test("Control items and spacers are not misattributed")
    func controlItemsAndSpacersAreNotMisattributed() {
        #expect(!MenuBarItemTag.visibleControlItem.isMisattributedControlCenterModule)
        #expect(!MenuBarItemTag.hiddenControlItem.isMisattributedControlCenterModule)
        #expect(!MenuBarItemTag.alwaysHiddenControlItem.isMisattributedControlCenterModule)
        #expect(!tag(namespace: "com.stonerl.Thaw", title: "Spacer.1234.autosaveName")
            .isMisattributedControlCenterModule)
    }

    // MARK: - canonicalControlCenterModuleIdentifier

    /// The rewrite heals the reporter's exact entry, moving only the
    /// namespace and carrying the title through verbatim.
    @Test("The field entry heals to Control Center's namespace")
    func fieldEntryHeals() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.techsmith.snagit.capturehelper:Battery"
            ) == "com.apple.controlcenter:Battery"
        )
    }

    /// An instance index survives the rewrite intact — two BentoBox
    /// modules keep their distinct spellings.
    @Test("Instance indexes survive the rewrite")
    func instanceIndexSurvivesRewrite() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "com.electron.dockerdesktop:BentoBox-1:2"
            ) == "com.apple.controlcenter:BentoBox-1:2"
        )
    }

    /// A localized display-name namespace heals too: #949's en-GB machine
    /// wrote `Control Centre:Battery` beside the canonical spelling, and
    /// the rewrite merges the ghost into the canonical entry instead of
    /// leaving it for the prune.
    @Test("A display-name namespace heals to the canonical spelling")
    func displayNameNamespaceHeals() {
        #expect(
            MenuBarItemTag.canonicalControlCenterModuleIdentifier(
                "Control Centre:Battery"
            ) == "com.apple.controlcenter:Battery"
        )
    }

    /// The identity function for everything else: Control Center's own
    /// entries, generic slots, app-titled items, and identifiers without a
    /// title at all.
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

    /// ``LayoutSolver/canonicalIdentifier(_:)`` is the migration pass that
    /// runs over saved section orders at load, and it must leave the ghost
    /// alone: renaming it here would merge it with the genuine spelling and
    /// duplicate the entry, which is the wrong repair. The misattribution is
    /// the prune's business, not the rename's.
    @Test("canonicalIdentifier leaves the ghost for the prune")
    func canonicalIdentifierLeavesGhostAlone() {
        #expect(
            LayoutSolver.canonicalIdentifier("com.techsmith.snagit.capturehelper:Battery")
                == "com.techsmith.snagit.capturehelper:Battery"
        )
    }

    /// The prune recognizes the ghost with no live twin to help it: the
    /// title alone is the witness, which is the case the existing
    /// claimed-title rule could not cover. #1027's reporter had no genuine
    /// `com.apple.controlcenter:Battery` entry in the saved order at all —
    /// the live module resolves nil more cycles than not, so nothing had
    /// ever persisted the genuine spelling for the twin rule to find.
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

    /// The genuine spelling survives, whether the ghost sits beside it or
    /// in another section. The second half pins the real-owner scan: the
    /// ghost must not count as the owner of the title "Battery", or the
    /// provisional-duplicate rule would delete the genuine entry instead —
    /// the exact wrong-side deletion #927 fixed for Thaw's own namespace.
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

    /// A third-party app's generic slot is indistinguishable from a
    /// misattributed one by title alone. Snagit's own item really is
    /// `com.techsmith.snagit.capturehelper:Item-0`, and the prune must not
    /// orphan it.
    @Test("A generic slot under a foreign namespace survives the prune")
    func genericSlotSurvivesPrune() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "hidden": ["com.techsmith.snagit.capturehelper:Item-0"],
        ])
        #expect(pruned["hidden"] == ["com.techsmith.snagit.capturehelper:Item-0"])
    }
}
