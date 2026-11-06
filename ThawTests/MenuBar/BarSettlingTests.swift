//
//  BarSettlingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Bar settling")
struct BarSettlingTests {
    // MARK: Kinds and yielding

    @Test("Each disturbance starts the settle of its kind", arguments: [
        (BarSettling.Disturbance.thawLaunched, BarSettling.Kind.cold),
        (.appLaunched(bundleID: "com.example.app"), .event),
        (.displayChanged(label: "displayConnect"), .event),
        (.spacingWaveStarted(cause: nil), .preflight),
        (.appsRelaunched(expecting: [], cause: nil), .preflight),
        (.appsRelaunched(expecting: ["com.example.app"], cause: nil), .expectedSet),
    ])
    func kindPerDisturbance(disturbance: BarSettling.Disturbance, kind: BarSettling.Kind) {
        let harness = Harness()
        defer { harness.stop() }

        harness.settling.note(disturbance)

        #expect(harness.settling.isSettling)
        #expect(harness.settling.kind == kind)
        #expect(harness.starts == 1)
    }

    @Test("Weaker settlings yield to stronger ones")
    func yieldOrder() {
        #expect(BarSettling.yields(incoming: .preflight, to: .event))
        #expect(!BarSettling.yields(incoming: .preflight, to: .preflight))
        #expect(BarSettling.yields(incoming: .event, to: .cold))
        #expect(BarSettling.yields(incoming: .event, to: .expectedSet))
        #expect(!BarSettling.yields(incoming: .event, to: .preflight))
        #expect(!BarSettling.yields(incoming: .cold, to: .event))
        #expect(!BarSettling.yields(incoming: .expectedSet, to: .cold))
    }

    @Test("A no-op spacing apply leaves a display settling running")
    func noOpSpacingKeepsDisplaySettling() {
        let harness = Harness()
        defer { harness.stop() }

        harness.settling.note(.displayChanged(label: "displayConnect"))
        harness.settling.note(.spacingWaveStarted(cause: "screenParametersChanged"))
        harness.settling.note(.spacingWaveEnded(cause: "screenParametersChanged", outcome: .noOp))

        #expect(harness.settling.isSettling)
        #expect(harness.settling.kind == .event)
        #expect(harness.starts == 1, "the preflight joined the display settle")
    }

    @Test("A no-op spacing apply still cancels its own preflight")
    func noOpSpacingCancelsOwnPreflight() {
        let harness = Harness()
        defer { harness.stop() }

        harness.settling.note(.spacingWaveStarted(cause: "configurationsChanged"))
        harness.settling.note(.spacingWaveEnded(cause: "configurationsChanged", outcome: .noOp))

        #expect(!harness.settling.isSettling)
        #expect(harness.settling.kind == nil)
    }

    /// 2026-11-05: an app opening at login ended the boot settling 4 s in,
    /// and the structural pass then moved items whose apps were still starting.
    @Test("An app launch at login leaves the boot settling running")
    func appLaunchKeepsColdSettling() {
        let harness = Harness()
        defer { harness.stop() }

        harness.settling.note(.thawLaunched)
        harness.settling.note(.appLaunched(bundleID: "com.example.app"))

        #expect(harness.settling.kind == .cold)
        #expect(harness.settling.expectedBundleIDs == ["com.example.app"], "the launch's ID joins the boot wait")
    }

    @Test("A spacing preflight at login doesn't take an app launch's ID as its own")
    func preflightKeepsColdSettlingAfterLaunch() {
        let harness = Harness()
        defer { harness.stop() }

        harness.settling.note(.thawLaunched)
        harness.settling.note(.appLaunched(bundleID: "com.example.app"))
        harness.settling.note(.spacingWaveStarted(cause: nil))

        #expect(harness.settling.kind == .cold)
        #expect(harness.settling.expectedBundleIDs == ["com.example.app"])
        #expect(harness.starts == 1)
    }

    @Test("A relaunch wave replaces the boot settling and still reads sections at the end")
    func relaunchReplacesColdSettling() async {
        let harness = Harness(samples: [.ready(count: 3, bundleIDs: ["com.example.app"])])

        harness.settling.note(.thawLaunched)
        harness.settling.note(.appsRelaunched(expecting: ["com.example.app"], cause: nil))
        #expect(harness.settling.kind == .expectedSet)
        await harness.settling.settled()

        let ending = BarSettling.Ending(
            disturbance: .appsRelaunched(expecting: ["com.example.app"], cause: nil),
            adoptsObservedMembership: true,
            hitDeadline: false
        )
        #expect(harness.endings == [ending])
    }

    // MARK: Calling off

    @Test("The end of a wave cannot call off a settle that is waiting for apps, Thaw's launch or a display change", arguments: [
        BarSettling.Disturbance.appsRelaunched(expecting: ["com.example.app"], cause: nil),
        .thawLaunched,
        .displayChanged(label: "displayDisconnect"),
        .appLaunched(bundleID: "com.example.app"),
    ])
    func callOffRefused(disturbance: BarSettling.Disturbance) {
        let harness = Harness()
        defer { harness.stop() }

        harness.settling.note(disturbance)
        harness.settling.note(.spacingWaveEnded(cause: nil, outcome: .cancelled))

        #expect(harness.settling.isSettling)
    }

    @Test("Calling off with nothing running does nothing")
    func callOffWhenIdle() {
        let harness = Harness()

        harness.settling.note(.spacingWaveEnded(cause: nil, outcome: .error))

        #expect(!harness.settling.isSettling)
        #expect(harness.starts == 0)
    }

    @Test("A called-off settle never runs the work owed after settling")
    func calledOffSettleOwesNothing() async {
        let harness = Harness(samples: [.ready(count: 2)])

        harness.settling.note(.spacingWaveStarted(cause: nil))
        harness.settling.note(.spacingWaveEnded(cause: nil, outcome: .noOp))
        await harness.settling.settled()
        await Task.yield()

        #expect(harness.endings.isEmpty)
    }

    // MARK: Membership adoption

    @Test("Only the launch settling reads sections from the bar")
    func onlyLaunchSettlingAdoptsMembership() {
        #expect(BarSettling.adoptsObservedMembership(incoming: .cold, replacing: nil))
        #expect(BarSettling.adoptsObservedMembership(incoming: .expectedSet, replacing: .cold))
        #expect(BarSettling.adoptsObservedMembership(incoming: .cold, replacing: .event))
    }

    @Test("An app launch, display change or spacing wave keeps the sections set in Layout", arguments: [
        BarSettling.Kind.event, .expectedSet, .preflight,
    ])
    func laterSettlingsKeepAuthoredSections(kind: BarSettling.Kind) {
        #expect(!BarSettling.adoptsObservedMembership(incoming: kind, replacing: nil))
        #expect(!BarSettling.adoptsObservedMembership(incoming: kind, replacing: .event))
        #expect(!BarSettling.adoptsObservedMembership(incoming: kind, replacing: .expectedSet))
    }

    // MARK: Polling

    @Test("A count-stable settle ends after three steady polls past the first read")
    func countModeNeedsThreeSteadyPolls() {
        var streak = BarSettling.Streak()
        let sample = BarSettling.Sample.ready(count: 4)
        let verdicts = (0 ..< 4).map { _ in
            BarSettling.verdict(for: sample, expecting: nil, minimumElapsed: true, barQuiet: true, streak: &streak)
        }

        #expect(verdicts == [.waiting(.countChanged(from: -1, to: 4)), .waiting(.counting), .waiting(.counting), .settled])
    }

    @Test("A changed count restarts the streak")
    func countChangeResets() {
        var streak = BarSettling.Streak(lastSeenCount: 4, stablePolls: 2)

        let verdict = BarSettling.verdict(for: .ready(count: 5), expecting: nil, minimumElapsed: true, barQuiet: true, streak: &streak)

        #expect(verdict == .waiting(.countChanged(from: 4, to: 5)))
        #expect(streak == .init(lastSeenCount: 5, stablePolls: 0))
    }

    @Test("A steady count waits for the minimum time, the host modules and resolved PIDs")
    func countModeBlockers() {
        func judge(_ sample: BarSettling.Sample, minimumElapsed: Bool = true) -> BarSettling.Verdict {
            var streak = BarSettling.Streak(lastSeenCount: sample.managedCount, stablePolls: 2)
            return BarSettling.verdict(for: sample, expecting: nil, minimumElapsed: minimumElapsed, barQuiet: true, streak: &streak)
        }
        var noHost = BarSettling.Sample.ready(count: 3)
        noHost.hostReady = false
        var unresolved = BarSettling.Sample.ready(count: 3)
        unresolved.unresolvedPIDs = 2
        var oneUnresolved = BarSettling.Sample.ready(count: 3)
        oneUnresolved.unresolvedPIDs = 1

        #expect(judge(.ready(count: 3), minimumElapsed: false) == .waiting(.minimumNotElapsed))
        #expect(judge(noHost) == .waiting(.hostNotReady))
        #expect(judge(unresolved) == .waiting(.pidsUnresolved))
        #expect(judge(.ready(count: 0)) == .waiting(.pidsUnresolved), "an empty cache never settles")
        #expect(judge(oneUnresolved) == .settled, "one unresolved PID is tolerated")
    }

    @Test("A count-stable settle waits for a quiet bar when asked to")
    func countModeWaitsForQuietBar() {
        var streak = BarSettling.Streak(lastSeenCount: 3, stablePolls: 2)

        let verdict = BarSettling.verdict(for: .ready(count: 3), expecting: nil, minimumElapsed: true, barQuiet: false, streak: &streak)

        #expect(verdict == .waiting(.barNotQuiet))
        #expect(BarSettling.Disturbance.displayChanged(label: "displayArrangement").waitsForQuietBar)
        #expect(!BarSettling.Disturbance.thawLaunched.waitsForQuietBar)
    }

    @Test("Only a display change settle waits out the quiet period after a wake", arguments: [true, false])
    func onlyDisplayChangeWaitsForQuietBar(isDisplayChange: Bool) async {
        let harness = Harness(samples: [.ready(count: 3)])
        let start = harness.clock.now

        harness.settling.note(.screensWoke)
        harness.settling.note(isDisplayChange ? .displayChanged(label: "displayConnect") : .spacingWaveStarted(cause: nil))
        await harness.settling.settled()

        let waited = start.duration(to: harness.clock.now)
        #expect(isDisplayChange ? waited >= BarSettling.quietPeriod : waited < .seconds(5))
    }

    @Test("An expected-set settle ends once every awaited app is back, ignoring the count and the quiet clock")
    func expectedSetMode() {
        var streak = BarSettling.Streak()
        let partial = BarSettling.Sample.ready(count: 5, bundleIDs: ["com.example.one"])
        var complete = partial
        complete.bundleIDs = ["com.example.one", "com.example.two"]

        let waiting = BarSettling.verdict(for: partial, expecting: ["com.example.one", "com.example.two"], minimumElapsed: true, barQuiet: false, streak: &streak)
        let done = BarSettling.verdict(for: complete, expecting: ["com.example.one", "com.example.two"], minimumElapsed: true, barQuiet: false, streak: &streak)

        #expect(waiting == .waiting(.missing(["com.example.two"])))
        #expect(done == .settled)
    }

    @Test("A settle waiting for apps picks up the ID of a launch that yielded to it")
    func expectedSetRereadEveryPoll() async {
        let harness = Harness(samples: [.ready(count: 3, bundleIDs: ["com.example.one"])])
        defer { harness.stop() }

        harness.settling.note(.appsRelaunched(expecting: ["com.example.one"], cause: nil))
        harness.settling.note(.appLaunched(bundleID: "com.example.two"))
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(harness.settling.isSettling, "com.example.two never came back")
        #expect(harness.endings.isEmpty)
    }

    @Test("A settled bar runs the work owed once, and waiting for it covers that work")
    func settledRunsHostOnce() async {
        let harness = Harness(samples: [.ready(count: 3)])

        harness.settling.note(.displayChanged(label: "displayConnect"))
        await harness.settling.settled()

        #expect(!harness.settling.isSettling)
        #expect(harness.settling.kind == nil)
        #expect(harness.endings == [.init(disturbance: .displayChanged(label: "displayConnect"), adoptsObservedMembership: false, hitDeadline: false)])
        #expect(harness.reads == 1)
    }

    @Test("A settle that never steadies ends at its deadline, and the later deadline wins")
    func laterDeadlineWins() async {
        let harness = Harness(samples: [BarSettling.Sample()])
        let start = harness.clock.now

        harness.settling.note(.spacingWaveStarted(cause: nil))
        harness.clock.now = start.advanced(by: .seconds(1))
        // Replaces the preflight; its own 8 s deadline is earlier than the preflight's 60 s.
        harness.settling.note(.appLaunched(bundleID: "com.example.app"))
        await harness.settling.settled()

        #expect(harness.endings.map(\.hitDeadline) == [true])
        #expect(start.duration(to: harness.clock.now) > .seconds(60))
    }

    // MARK: Waiting

    @Test("Waiting for the settle returns at once when none is running")
    func awaitWithoutSettle() async {
        let harness = Harness()

        await harness.settling.settled()

        #expect(!harness.settling.isSettling)
    }

    @Test("Waiting for the settle follows a replacing settle to its end")
    func awaitFollowsReplacement() async {
        let harness = Harness(samples: [.ready(count: 3)])

        harness.settling.note(.displayChanged(label: "displayConnect"))
        let waiter = Task { await harness.settling.settled() }
        await Task.yield()
        harness.settling.note(.thawLaunched)
        await waiter.value

        #expect(!harness.settling.isSettling)
        #expect(harness.endings.map(\.disturbance) == [.thawLaunched], "the replaced settle owes nothing")
    }

    // MARK: Labels

    @Test("Log labels match the reason strings the settle used to be started with")
    func labels() {
        #expect(BarSettling.Disturbance.thawLaunched.label == "performSetup")
        #expect(BarSettling.Disturbance.appLaunched(bundleID: "x").label == "appLaunch")
        #expect(BarSettling.Disturbance.displayChanged(label: "displayConnect").label == "displayConnect")
        #expect(BarSettling.Disturbance.spacingWaveStarted(cause: nil).label == "spacingRelaunch:preflight")
        #expect(BarSettling.Disturbance.spacingWaveStarted(cause: "userReapply").label == "spacingRelaunch:userReapply:preflight")
        #expect(BarSettling.Disturbance.appsRelaunched(expecting: [], cause: "userReapply").label == "spacingRelaunch:userReapply")
        #expect(BarSettling.Disturbance.spacingWaveEnded(cause: nil, outcome: .noOp).label == "spacingRelaunch:noOp")
        #expect(BarSettling.Disturbance.appLaunched(bundleID: "x").maxDuration == .seconds(8))
        #expect(BarSettling.Disturbance.thawLaunched.maxDuration == .seconds(60))
    }
}

// MARK: - Harness

/// A settle on a hand-driven clock. Each poll's sleep moves the clock on by the poll interval, so a
/// settle runs to its end without waiting in real time. The last scripted sample repeats.
@MainActor
private final class Harness {
    let clock: TestClock
    let settling: BarSettling
    private let samples: [BarSettling.Sample]
    private(set) var reads = 0
    private(set) var starts = 0
    private(set) var endings: [BarSettling.Ending] = []
    private var sampleIndex = 0

    init(samples: [BarSettling.Sample] = [BarSettling.Sample()]) {
        let clock = TestClock()
        self.clock = clock
        self.samples = samples
        settling = BarSettling(now: { clock.now }, sleep: { try await clock.sleep(for: $0) })
        settling.attach(BarSettling.Host(
            awaitInitialRead: { [weak self] in self?.reads += 1 },
            sample: { [weak self] in self?.nextSample() ?? BarSettling.Sample() },
            didStart: { [weak self] in self?.starts += 1 },
            didSettle: { [weak self] in self?.endings.append($0) }
        ))
    }

    /// Ends a settle the test leaves running, the way a wave's end or a deadline would.
    func stop() {
        clock.now = clock.now.advanced(by: .seconds(3600))
    }

    private func nextSample() -> BarSettling.Sample {
        defer { sampleIndex = min(sampleIndex + 1, samples.count - 1) }
        return samples[sampleIndex]
    }
}

private extension BarSettling.Sample {
    static func ready(count: Int, bundleIDs: Set<String> = []) -> Self {
        Self(managedCount: count, unresolvedPIDs: 0, hostReady: true, bundleIDs: bundleIDs)
    }
}
