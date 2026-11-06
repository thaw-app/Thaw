//
//  BarSettlingEndWorkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation
import Testing
@testable import Thaw

/// Once the bar has settled, the work owed afterwards runs to its end even if a new disturbance arrives
/// while it runs. That work re-applies the active profile, whose spacing wave reports itself here.
@MainActor
@Suite("Bar settling end work")
struct BarSettlingEndWorkTests {
    private func makeSettling(endWork: SettleEndWorkProbe) -> BarSettling {
        let settling = BarSettling(sleep: { _ in await Task.yield() }, minimumDuration: .zero)
        settling.attach(BarSettling.Host(
            awaitInitialRead: { /* Nothing cached to wait for. */ },
            sample: { BarSettling.Sample(managedCount: 2, hostReady: true) },
            didStart: { /* Nothing to call off. */ },
            didSettle: { _ in await endWork.run() }
        ))
        return settling
    }

    /// 2026-11-05: a profile re-applied at the end of the launch settle started a spacing preflight,
    /// which cancelled the settle's final cache passes, so the saved layout was not restored then.
    @Test("A spacing wave that relaunches nothing leaves the end work to finish")
    func noOpWaveDuringEndWork() async {
        let endWork = SettleEndWorkProbe()
        let settling = makeSettling(endWork: endWork)

        settling.note(.thawLaunched)
        await waitUntil {
            endWork.started
        } tracking: {
            _ = endWork.started
        }
        #expect(!settling.isSettling)

        settling.note(.spacingWaveStarted(cause: nil))
        settling.note(.spacingWaveEnded(cause: nil, outcome: .noOp))
        endWork.release()
        await waitUntil {
            endWork.finishedUncancelled != nil
        } tracking: {
            _ = endWork.finishedUncancelled
        }

        #expect(endWork.finishedUncancelled == true)
    }

    @Test("A wave that relaunches apps starts its own settle without cancelling the end work")
    func relaunchDuringEndWork() async {
        let endWork = SettleEndWorkProbe()
        let settling = makeSettling(endWork: endWork)

        settling.note(.displayChanged(label: "displayConnect"))
        await waitUntil {
            endWork.started
        } tracking: {
            _ = endWork.started
        }

        settling.note(.spacingWaveStarted(cause: nil))
        #expect(settling.isSettling)
        endWork.release()
        await waitUntil {
            endWork.finishedUncancelled != nil
        } tracking: {
            _ = endWork.finishedUncancelled
        }

        #expect(endWork.finishedUncancelled == true)
        settling.note(.spacingWaveEnded(cause: nil, outcome: .noOp))
    }
}

/// Settle end work that waits partway through, the way the real one waits on a profile re-apply.
@MainActor
@Observable
final class SettleEndWorkProbe {
    var started = false
    var finishedUncancelled: Bool?
    @ObservationIgnored private var gate: CheckedContinuation<Void, Never>?

    /// Only the first run waits: a replacement settle that ends during a test must not wait on a gate
    /// nobody releases.
    func run() async {
        guard !started else { return }
        started = true
        await withCheckedContinuation { gate = $0 }
        finishedUncancelled = !Task.isCancelled
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}
