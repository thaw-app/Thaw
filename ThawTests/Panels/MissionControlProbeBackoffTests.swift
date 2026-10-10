//
//  MissionControlProbeBackoffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization for
/// MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor:),
/// which drops the probe from 10 Hz to 2 Hz only after rest sustained for the
/// full settle window; nil, zero or shorter rest keeps the active rate.
@Suite("Mission Control probe rest back-off")
struct MissionControlProbeBackoffTests {
    @Test("displaced, calibrating, or freshly settled keeps the active rate")
    func unsettledHoldsActiveRate() {
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: nil) == 0.1)
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: 0) == 0.1)
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: 1.9) == 0.1)
    }

    @Test("rest beyond the settle window drops to the rest rate")
    func settledRestSlowsDown() {
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: 2.0) == 0.5)
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: 600) == 0.5)
    }
}
