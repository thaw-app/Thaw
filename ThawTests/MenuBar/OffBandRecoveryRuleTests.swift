//
//  OffBandRecoveryRuleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Off-band recovery")
struct OffBandRecoveryRuleTests {
    private let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]

    @Test("The Thaw icon the user turned off measures no width on purpose, so nothing is recovered")
    func turnedOffIconIsLeftAlone() {
        let collapsed = CGRect(x: 1500, y: 1050, width: 0, height: 30)
        #expect(!OffBandRecoveryRule.needsRecovery(collapsed, isThawIcon: true, showsIcon: false, screenFrames: screens))
        #expect(!OffBandRecoveryRule.needsRecovery(CGRect(x: -1, y: 1050, width: 1, height: 30), isThawIcon: true, showsIcon: false, screenFrames: screens))
    }

    @Test("A shown icon, or a divider, with no width still gets recovered")
    func otherDegenerateFramesRecover() {
        let collapsed = CGRect(x: 1500, y: 1050, width: 0, height: 30)
        #expect(OffBandRecoveryRule.needsRecovery(collapsed, isThawIcon: true, showsIcon: true, screenFrames: screens))
        #expect(OffBandRecoveryRule.needsRecovery(collapsed, isThawIcon: false, showsIcon: false, screenFrames: screens))
        #expect(OffBandRecoveryRule.needsRecovery(CGRect(x: -1, y: 1050, width: 30, height: 24), isThawIcon: true, showsIcon: true, screenFrames: screens))
    }

    @Test("A seated frame never needs recovery")
    func seatedFrame() {
        #expect(!OffBandRecoveryRule.needsRecovery(CGRect(x: 1500, y: 1050, width: 30, height: 24), isThawIcon: true, showsIcon: true, screenFrames: screens))
    }
}
