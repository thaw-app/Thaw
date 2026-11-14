//
//  AutomaticZenRequestsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Automatic Zen Mode requests")
struct AutomaticZenRequestsTests {
    /// Applies each change as MenuBarManager does.
    @MainActor
    private struct Harness {
        var requests = AutomaticZenRequests()
        var isZenModeActive = false

        mutating func report(_ isActive: Bool, _ reason: AutomaticZenRequests.Reason) -> AutomaticZenRequests.Change {
            let change = requests.set(isActive, reason: reason, isZenModeActive: isZenModeActive)
            switch change {
            case .engage: isZenModeActive = true
            case .withdraw: isZenModeActive = false
            case .none: break
            }
            return change
        }

        mutating func toggleByHand() {
            requests.takeManualOwnership()
            isZenModeActive.toggle()
        }
    }

    @Test("A source that keeps asking after a manual off is ignored until it stops")
    func declinedSourceWaitsForItsEnd() {
        var zen = Harness()
        #expect(zen.report(true, .screenSharing) == .engage)
        zen.toggleByHand()

        #expect(zen.report(true, .screenSharing) == .none)
        #expect(!zen.isZenModeActive)

        #expect(zen.report(false, .screenSharing) == .none)
        #expect(zen.report(true, .screenSharing) == .engage)
    }

    @Test("Another source still engages and withdraws after a manual off")
    func otherSourceStillEngages() {
        var zen = Harness()
        #expect(zen.report(true, .screenSharing) == .engage)
        zen.toggleByHand()

        #expect(zen.report(true, .recording) == .engage)
        #expect(zen.report(true, .screenSharing) == .none)
        #expect(zen.report(false, .recording) == .withdraw)
        #expect(!zen.isZenModeActive)
    }

    @Test("Zen Mode turned on by hand outlasts a source that ends")
    func manualOnOutlastsSource() {
        var zen = Harness()
        zen.toggleByHand()

        #expect(zen.report(true, .recording) == .none)
        #expect(zen.report(false, .recording) == .none)
        #expect(zen.isZenModeActive)
    }

    @Test("A manual toggle declines every source asking at that moment")
    func manualToggleDeclinesAllAskingSources() {
        var zen = Harness()
        #expect(zen.report(true, .screenSharing) == .engage)
        #expect(zen.report(true, .recording) == .none)
        zen.toggleByHand()

        #expect(zen.report(true, .screenSharing) == .none)
        #expect(zen.report(true, .recording) == .none)
        #expect(!zen.isZenModeActive)
    }
}
