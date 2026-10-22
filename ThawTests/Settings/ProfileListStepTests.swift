//
//  ProfileListStepTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Profile list arrow keys")
struct ProfileListStepTests {
    private let ids = [UUID(), UUID(), UUID()]

    @Test("Up and down select the profile above or below")
    func stepsUpAndDown() {
        #expect(ProfileListStep.profile(after: ids[1], in: ids, moving: .down) == ids[2])
        #expect(ProfileListStep.profile(after: ids[1], in: ids, moving: .up) == ids[0])
    }

    @Test("The selection stays put at either end of the list")
    func stopsAtTheEnds() {
        #expect(ProfileListStep.profile(after: ids[0], in: ids, moving: .up) == nil)
        #expect(ProfileListStep.profile(after: ids[2], in: ids, moving: .down) == nil)
    }

    @Test("Left, right, no selection or a deleted profile move nothing")
    func ignoresOtherKeys() {
        #expect(ProfileListStep.profile(after: ids[1], in: ids, moving: .left) == nil)
        #expect(ProfileListStep.profile(after: ids[1], in: ids, moving: .right) == nil)
        #expect(ProfileListStep.profile(after: nil, in: ids, moving: .down) == nil)
        #expect(ProfileListStep.profile(after: UUID(), in: ids, moving: .down) == nil)
    }
}
