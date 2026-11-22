//
//  ResidentBenchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The resident benchmark against fake panels and a fake footprint: nothing is shown and no time passes.
@MainActor
@Suite("Resident memory benchmark")
struct ResidentBenchTests {
    private typealias Stage = ResidentBench.Stage
    private typealias Sample = ResidentBench.Sample
    private typealias Report = ResidentBench.Report

    /// What a run did, in order, and the footprints it is handed.
    private final class Script {
        var events: [String] = []
        var footprints: [Double?]
        var output: [String] = []

        init(footprints: [Double?]) {
            self.footprints = footprints
        }

        func nextFootprint() -> Double? {
            footprints.isEmpty ? 10 : footprints.removeFirst()
        }
    }

    private func surface(_ name: String, shows: Bool = true, script: Script) -> ResidentBench.Surface {
        ResidentBench.Surface(
            name: name,
            show: { script.events.append("show \(name)") },
            isShown: { shows },
            close: { script.events.append("close \(name)") }
        )
    }

    private func bench(script: Script, scanSettles: Bool = true, thawBarShows: Bool = true) -> ResidentBench {
        let life = ResidentBench.Life(
            footprint: { script.nextFootprint() },
            sleep: { _ in },
            scanSettled: { scanSettles },
            thawBar: surface("bar", shows: thawBarShows, script: script),
            search: surface("search", script: script),
            settings: surface("settings", script: script),
            trimImageCache: { script.events.append("trim") },
            relieve: { script.events.append("relieve") }
        )
        var timing = ResidentBench.Timing()
        timing.settleSamples = 3
        return ResidentBench(life: life, timing: timing, output: { script.output.append($0) })
    }

    // MARK: Output

    @Test("A sample prints its stage, its footprint and its budget")
    func lineFormat() {
        #expect(Report.line(for: Sample(stage: .thawBarCycled, megabytes: 42.504)) == "RESIDENT thaw-bar-x3 42.50 MiB budget 90")
        #expect(Report.line(for: Sample(stage: .started, megabytes: nil)) == "RESIDENT started unreadable budget 50")
    }

    @Test("The verdict says pass, or lists what failed")
    func verdictLine() {
        #expect(Report.verdictLine(problems: []) == "RESIDENT PASS")
        #expect(Report.verdictLine(problems: ["a", "b"]) == "RESIDENT FAIL: a; b")
    }

    // MARK: Budget check

    private func samples(_ megabytes: Double? = 20, overriding stage: Stage? = nil, with value: Double? = nil) -> [Sample] {
        Stage.allCases.map { Sample(stage: $0, megabytes: $0 == stage ? value : megabytes) }
    }

    @Test("A run with every stage within budget has no problems")
    func withinBudget() {
        #expect(Report.problems(samples: samples(), notes: []).isEmpty)
        #expect(Report.problems(samples: samples(overriding: .settled, with: Stage.settled.budget), notes: []).isEmpty)
    }

    @Test("A fraction over the budget fails, because the unrounded value is compared")
    func fractionOver() {
        let problems = Report.problems(samples: samples(overriding: .searchCycled, with: 100.004), notes: [])
        #expect(problems == ["search-x3: 100.00 MiB, over its 100 MiB budget"])
    }

    @Test("An unreadable footprint fails its stage")
    func unreadable() {
        let problems = Report.problems(samples: samples(overriding: .trimmed, with: nil), notes: [])
        #expect(problems == ["trimmed: footprint unreadable"])
    }

    @Test("Stages not reached fail the run, after its notes")
    func notReached() {
        let problems = Report.problems(samples: Array(samples().prefix(2)), notes: ["scan"])
        #expect(problems == ["scan", "not reached: thaw-bar-x3, search-x3, settings-layout, trimmed, settled"])
    }

    @Test("Stages out of order fail the run")
    func outOfOrder() {
        let reordered = [Sample(stage: .scanSettled, megabytes: 1), Sample(stage: .started, megabytes: 1)]
        #expect(Report.problems(samples: reordered, notes: []) == ["stages out of order: scan-settled, started"])
    }

    // MARK: The run

    @Test("A run cycles each panel three times, opens Settings once, trims, relieves and passes")
    func fullRun() async {
        let script = Script(footprints: [30, 40, 50, 60, 62, 45, 46, 52, 47])
        let bench = bench(script: script)
        let problems = await bench.run()

        #expect(problems.isEmpty)
        #expect(bench.samples.map(\.stage) == Stage.allCases)
        let cycles = Array(repeating: ["show bar", "close bar"], count: 3).flatMap(\.self)
            + Array(repeating: ["show search", "close search"], count: 3).flatMap(\.self)
        #expect(script.events == cycles + ["show settings", "close settings", "trim", "relieve"])
        #expect(bench.samples.last?.megabytes == 52, "the settled stage keeps the highest of its samples")
        #expect(script.output.count == Stage.allCases.count + 1)
        #expect(script.output.last == "RESIDENT PASS")
    }

    @Test("A run whose scan never settles stops there and fails")
    func scanNeverSettles() async {
        let script = Script(footprints: [])
        let bench = bench(script: script, scanSettles: false)
        let problems = await bench.run()

        #expect(bench.samples.map(\.stage) == [.started])
        #expect(script.events.isEmpty, "nothing is shown without a scan")
        #expect(problems.first == "the first menu bar scan did not settle")
        #expect(script.output.last?.hasPrefix("RESIDENT FAIL: ") == true)
    }

    @Test("A panel that never shows is reported once, and the run goes on")
    func panelNeverShows() async {
        let script = Script(footprints: [])
        let bench = bench(script: script, thawBarShows: false)
        let problems = await bench.run()

        #expect(problems == ["bar did not show"])
        #expect(bench.samples.map(\.stage) == Stage.allCases)
    }

    @Test("An unreadable footprint while settling fails the settled stage")
    func unreadableWhileSettling() async {
        let script = Script(footprints: [30, 40, 50, 60, 62, 45, 46, nil])
        let bench = bench(script: script)
        let problems = await bench.run()

        #expect(bench.samples.last == Sample(stage: .settled, megabytes: nil))
        #expect(problems == ["settled: footprint unreadable"])
    }
}
