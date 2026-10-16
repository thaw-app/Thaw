//
//  ControlItemSectionGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``LayoutSolver/controlItemsAreInCanonicalOrder(visibleControlItemBounds:hiddenControlItemBounds:alwaysHiddenControlItemBounds:)``,
/// which stops a bulk apply from planning against dividers that drifted out of order.
///
/// After a restart the hidden divider parked offscreen and the visible control
/// item read inside hidden; applies planned an unmanaged Battery into hidden
/// (#1027). The room gate (#868) cannot see drift, and a missing divider is #849's
/// job. A bar that cannot be verified passes, and refusals pair with recovery so
/// a scrambled bar converges instead of wedging.
@Suite("Control item section gate")
struct ControlItemSectionGateTests {
    /// Absent dividers (no chevron, always-hidden disabled) leave the verdict to those present.
    @Test("Canonical dividers pass, including the apply-gate fixture geometry")
    func canonicalDividersPass() {
        #expect(LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            hiddenControlItemBounds: CGRect(x: 60, y: 0, width: 10, height: 22),
            alwaysHiddenControlItemBounds: CGRect(x: 20, y: 0, width: 10, height: 22)
        ))
        #expect(LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: nil,
            hiddenControlItemBounds: CGRect(x: -5743, y: 0, width: 10, height: 22),
            alwaysHiddenControlItemBounds: CGRect(x: -6000, y: 0, width: 10, height: 22)
        ))
        #expect(LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: nil,
            hiddenControlItemBounds: CGRect(x: -5743, y: 0, width: 10, height: 22),
            alwaysHiddenControlItemBounds: nil
        ))
    }

    /// The chevron entirely left of the hidden divider, and on another cycle the
    /// always-hidden divider right of it (#1027). Each refuses on its own.
    @Test("The #1027 divider states refuse")
    func fieldDividerStatesRefuse() {
        let hidden = CGRect(x: -5743, y: 0, width: 10, height: 22)
        let chevronInHidden = CGRect(x: -5800, y: 0, width: 24, height: 22)
        let ahRightOfHidden = CGRect(x: -5700, y: 0, width: 10, height: 22)

        let chevronDrifted = LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: chevronInHidden,
            hiddenControlItemBounds: hidden,
            alwaysHiddenControlItemBounds: nil
        )
        #expect(!chevronDrifted)

        let ahDrifted = LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: nil,
            hiddenControlItemBounds: hidden,
            alwaysHiddenControlItemBounds: ahRightOfHidden
        )
        #expect(!ahDrifted)

        let bothDrifted = LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: chevronInHidden,
            hiddenControlItemBounds: hidden,
            alwaysHiddenControlItemBounds: ahRightOfHidden
        )
        #expect(!bothDrifted)
    }

    /// A chevron against the hidden divider's trailing edge, or an always-hidden
    /// divider against its leading edge, is ordinary collapsed geometry.
    @Test("Adjacent but ordered dividers pass")
    func adjacentOrderedDividersPass() {
        #expect(LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: CGRect(x: 70, y: 0, width: 24, height: 22),
            hiddenControlItemBounds: CGRect(x: 60, y: 0, width: 10, height: 22),
            alwaysHiddenControlItemBounds: CGRect(x: 50, y: 0, width: 10, height: 22)
        ))
    }

    // MARK: - Log-replay regression lock

    /// Replays #1027's dispatch-time reading: one visible item left, the visible
    /// control item read inside hidden, and the always-hidden divider read under its
    /// degraded identity (`com.apple.controlcenter:com.stonerl.Thaw`). Before the fix
    /// the apply planned Battery into hidden again.
    ///
    /// The log records sections, not bounds, so the chevron's bounds are synthesized
    /// to reproduce the logged classification.
    @Test("The #1027 field cycle is refused")
    func fieldCycleIsRefused() throws {
        let log = """
        2026-09-02 19:49:59.161 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 1 items: ["leits.MeetingBar:Item-0"]
        2026-09-02 19:49:59.161 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 19 items: ["com.steipete.codexbar:codexbar-codex", "com.steipete.codexbar:codexbar-claude", "com.tunabellysoftware.tgpro:Item-0", "eu.exelban.Stats:CPU_bar_chart", "eu.exelban.Stats:GPU_bar_chart", "eu.exelban.Stats:RAM_bar_chart", "com.rogueamoeba.soundsource:SSMainAppMenuIcon", "com.rogueamoeba.soundsource:Input", "com.apphousekitchen.aldente-pro:Item-0", "org.p0deje.Maccy:Item-0", "com.apple.TextInputMenuAgent:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.nektony.App-Cleaner-SIII-UIHelper:Item-0", "com.apple.KerberosMenuExtra:Item-0", "com.apple.controlcenter:Battery", "com.electron.dockerdesktop:Item-0", "com.proxyman.NSProxy:Item-0", "com.paloaltonetworks.GlobalProtect.client:Item-0", "com.kaspersky.kav_agent:Item-0"]
        2026-09-02 19:49:59.161 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 6 items: ["com.apple.controlcenter:com.stonerl.Thaw", "com.steipete.codexbar:codexbar-opencode", "com.steipete.codexbar:codexbar-cursor", "com.shortcutlabs.FlicMac:Item-0", "ru.yandex.desktop.disk2:Item-0", "com.nextcloud.desktopclient:Item-0"]
        """
        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)

        let visibleCtrl = MenuBarItemTag.visibleControlItem.tagIdentifier

        #expect(
            cycle.currentHidden.contains(visibleCtrl),
            "Fixture must carry the visible control item inside hidden, as the field log did"
        )

        // The parked divider's bounds are unknown, so use one at the origin and put the
        // chevron entirely left of it, which is what "classified hidden" means.
        let hiddenDivider = CGRect(x: 0, y: 0, width: 10, height: 22)
        let chevronInHidden = CGRect(x: -100, y: 0, width: 24, height: 22)

        let ordered = LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: chevronInHidden,
            hiddenControlItemBounds: hiddenDivider,
            alwaysHiddenControlItemBounds: nil
        )
        #expect(!ordered)
    }

    /// A healthy boot must pass, or applies wedge at startup.
    @Test("A settled field cycle passes")
    func settledCyclePasses() throws {
        let log = """
        2026-06-11 11:31:05.750 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 3 items: ["leits.MeetingBar:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.apple.controlcenter:Clock"]
        2026-06-11 11:31:05.750 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 2 items: ["com.proxyman.NSProxy:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.Hidden"]
        2026-06-11 11:31:05.751 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 2 items: ["com.shortcutlabs.FlicMac:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden"]
        """
        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)

        let visibleCtrl = MenuBarItemTag.visibleControlItem.tagIdentifier
        #expect(cycle.currentVisible.contains(visibleCtrl))

        // Chevron right of the divider, always-hidden divider left of it.
        let ordered = LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            hiddenControlItemBounds: CGRect(x: 60, y: 0, width: 10, height: 22),
            alwaysHiddenControlItemBounds: CGRect(x: 20, y: 0, width: 10, height: 22)
        )
        #expect(ordered)
    }
}
