//
//  StripSessionVersionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawCapture

@Suite("Display strip session suspension")
struct StripSessionVersionTests {
    @Test func aRequestCannotSurviveConfigurationChangingAwayAndBack() {
        var state = StripSessionVersion()
        let requestAtA = state.configuration
        state.reconfigure() // A → B while capture awaits readiness.
        state.reconfigure() // B → A before the old request resumes.
        #expect(!state.matchesConfiguration(requestAtA))
        #expect(state.matchesConfiguration(state.configuration))
    }

    @Test func anEnqueuedIdleExpiryCannotStopARenewedSession() {
        var state = StripSessionVersion()
        let expiredTimer = state.renewLease()
        // A timer has finished sleeping, but a request reaches the actor first.
        let activeTimer = state.renewLease()
        #expect(!state.matchesLease(expiredTimer))
        #expect(state.matchesLease(activeTimer))
    }

    @Test func refreshingALeaseDoesNotInvalidateAnAwaitingCapture() {
        var state = StripSessionVersion()
        let request = state.configuration
        _ = state.renewLease()
        _ = state.renewLease()
        #expect(state.matchesConfiguration(request))
    }
}
