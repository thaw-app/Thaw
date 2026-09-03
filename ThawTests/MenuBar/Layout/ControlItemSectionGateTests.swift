//
//  ControlItemSectionGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``LayoutSolver/controlItemsAreInCanonicalOrder(visibleControlItemBounds:hiddenControlItemBounds:alwaysHiddenControlItemBounds:)``,
/// the gate that stops a bulk apply from planning against a bar whose
/// dividers have drifted out of order.
///
/// #1027's restart produced exactly that state before any apply ran: the
/// hidden divider parked far offscreen, and the live reading placed the
/// visible control item inside the hidden section. The applies that
/// dispatched anyway planned an unmanaged Battery into hidden and anchored
/// moves on the scramble. The room gate (#868) could not see it — drifted
/// dividers leave plenty of room — and a missing divider is deliberately
/// not this gate's business (#849 owns that). The half that keeps the fix
/// from becoming a bug of its own: a bar that cannot be verified passes,
/// and the refusal paths pair the gate with recovery so a scrambled bar
/// converges back instead of wedging.
@Suite("Control item section gate")
struct ControlItemSectionGateTests {
    /// The healthy bar, at the scale of the apply-gate fixtures: the
    /// always-hidden divider left of the hidden one, the chevron right of
    /// it. Absent dividers (no chevron in the reading, always-hidden
    /// disabled) leave the gate's verdict to the dividers that are present.
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

    /// #1027's reading: the chevron sat entirely left of the hidden divider
    /// (the log classified it into the hidden section), and in the same bar
    /// a second cycle had the always-hidden divider drift right of the
    /// hidden one. Each violation refuses on its own.
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

    /// Touching-but-ordered dividers pass: a chevron parked directly
    /// against the hidden divider's trailing edge, and an always-hidden
    /// divider butted against the hidden one's leading edge with the hidden
    /// section empty. Both are ordinary collapsed-section geometry, and a
    /// gate that refused them would refuse every collapsed bar.
    @Test("Adjacent but ordered dividers pass")
    func adjacentOrderedDividersPass() {
        #expect(LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: CGRect(x: 70, y: 0, width: 24, height: 22),
            hiddenControlItemBounds: CGRect(x: 60, y: 0, width: 10, height: 22),
            alwaysHiddenControlItemBounds: CGRect(x: 50, y: 0, width: 10, height: 22)
        ))
    }

    // MARK: - Log-replay regression lock

    /// Replays #1027's dispatch-time reading (thaw_2026-09-02_19-49-29.log,
    /// 19:49:59.161): the bar had already collapsed to one visible item, and
    /// the live reading placed the visible control item inside the hidden
    /// section — the always-hidden divider's window was simultaneously read
    /// under its degraded identity (`com.apple.controlcenter:com.stonerl.Thaw`)
    /// in always-hidden. The gate must refuse that cycle; before the fix,
    /// the apply dispatched against it and planned the unmanaged Battery
    /// into hidden all over again.
    ///
    /// The log records section membership rather than divider bounds, so the
    /// chevron's bounds are synthesized to realize exactly the logged
    /// classification: an item the reading calls hidden sits entirely left
    /// of the hidden divider by that reading's own rules.
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

        // The hidden divider's bounds are unknowable from the log (it was
        // parked offscreen), so stand in a divider at the origin and place
        // the chevron entirely left of it, which is what "classified into
        // the hidden section" means geometrically.
        let hiddenDivider = CGRect(x: 0, y: 0, width: 10, height: 22)
        let chevronInHidden = CGRect(x: -100, y: 0, width: 24, height: 22)

        let ordered = LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: chevronInHidden,
            hiddenControlItemBounds: hiddenDivider,
            alwaysHiddenControlItemBounds: nil
        )
        #expect(!ordered)
    }

    /// A settled cycle passes: the chevron in visible, the always-hidden
    /// divider in always-hidden, exactly what a healthy boot logs. Guards
    /// against a gate that refuses valid layouts — the failure mode that
    /// would wedge applies at startup.
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
