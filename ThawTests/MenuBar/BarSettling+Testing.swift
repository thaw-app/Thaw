//
//  BarSettling+Testing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw

extension BarSettling {
    /// Holds a settle open the way a spacing wave's preflight does, for tests that need a settling bar.
    func holdForTesting() {
        note(.spacingWaveStarted(cause: "test"))
    }

    /// Ends a settle started by holdForTesting() the way a wave that relaunched nothing does.
    func releaseForTesting() {
        note(.spacingWaveEnded(cause: "test", outcome: .noOp))
    }
}
