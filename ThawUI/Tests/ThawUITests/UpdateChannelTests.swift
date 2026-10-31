//
//  UpdateChannelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

@Suite("Update channels")
struct UpdateChannelTests {
    @Test("Alpha gets betas too, so an alpha build updates to the next beta")
    func alphaIncludesBeta() {
        #expect(UpdateChannel.alpha.allowedSparkleChannels.isSuperset(of: UpdateChannel.beta.allowedSparkleChannels))
        #expect(UpdateChannel.alpha.allowedSparkleChannels.contains("alpha"))
    }

    @Test("Beta doesn't get alphas, and Stable gets only the default channel")
    func betaAndStable() {
        #expect(!UpdateChannel.beta.allowedSparkleChannels.contains("alpha"))
        #expect(UpdateChannel.stable.allowedSparkleChannels.isEmpty)
    }
}
