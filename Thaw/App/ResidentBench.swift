//
//  ResidentBench.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Walks Thaw's own process through a scripted life and samples its physical footprint at each Stage.
/// The live app supplies what it drives through Life; see ResidentBench+Live.swift.
final class ResidentBench {
    private let life: Life
    private let timing: Timing
    private let output: (String) -> Void
    private(set) var samples: [Sample] = []
    private var notes: [String] = []

    init(life: Life, timing: Timing, output: @escaping (String) -> Void) {
        self.life = life
        self.timing = timing
        self.output = output
    }

    /// Runs the stages in order, printing a line for each and then the verdict.
    /// Returns the problems found; none means every stage was reached within its budget.
    func run() async -> [String] {
        record(.started, megabytes: life.footprint())
        guard await life.scanSettled() else {
            // Without a scan there is nothing for the Thaw Bar or search to show.
            notes.append("the first menu bar scan did not settle")
            return finish()
        }
        record(.scanSettled, megabytes: life.footprint())
        await cycle(life.thawBar, times: timing.cycles, shown: timing.shown, closed: timing.closed)
        record(.thawBarCycled, megabytes: life.footprint())
        await cycle(life.search, times: timing.cycles, shown: timing.shown, closed: timing.closed)
        record(.searchCycled, megabytes: life.footprint())
        await cycle(life.settings, times: 1, shown: timing.settingsShown, closed: timing.settingsClosed)
        record(.settingsClosed, megabytes: life.footprint())
        life.trimImageCache()
        await life.sleep(timing.trim)
        life.relieve()
        await life.sleep(timing.relief)
        record(.trimmed, megabytes: life.footprint())
        let peak = await settledPeak()
        record(.settled, megabytes: peak)
        return finish()
    }

    private func cycle(_ surface: Surface, times: Int, shown: Duration, closed: Duration) async {
        for _ in 0 ..< times {
            surface.show()
            await life.sleep(shown)
            if !surface.isShown() {
                note("\(surface.name) did not show")
            }
            surface.close()
            // Longer than the relief debounce, so the sweep a close schedules has run.
            await life.sleep(closed)
        }
    }

    /// The highest of the samples, so work on a timer cannot hide behind a quiet moment.
    private func settledPeak() async -> Double? {
        var peak: Double?
        for _ in 0 ..< timing.settleSamples {
            await life.sleep(timing.settleInterval)
            guard let megabytes = life.footprint() else { return nil }
            peak = max(peak ?? megabytes, megabytes)
        }
        return peak
    }

    private func record(_ stage: Stage, megabytes: Double?) {
        let sample = Sample(stage: stage, megabytes: megabytes)
        samples.append(sample)
        output(Report.line(for: sample))
    }

    private func note(_ text: String) {
        guard !notes.contains(text) else { return }
        notes.append(text)
    }

    private func finish() -> [String] {
        let problems = Report.problems(samples: samples, notes: notes)
        output(Report.verdictLine(problems: problems))
        return problems
    }
}

// MARK: - What the run drives

extension ResidentBench {
    /// What the run reads and drives. The live app passes the real services; tests pass fakes.
    struct Life {
        /// The process's physical footprint in MiB, or nil when the kernel will not say.
        var footprint: () -> Double?
        var sleep: (Duration) async -> Void
        /// Waits for the first menu bar scan to settle. False when it never does, as without Accessibility.
        var scanSettled: () async -> Bool
        var thawBar: Surface
        var search: Surface
        /// The app's own Settings window on the Layout page, the one the settings process hands back.
        var settings: Surface
        /// Arms the image cache's idle trim, which runs after the cache's own delay.
        var trimImageCache: () -> Void
        /// Asks for a relief sweep, which runs after its own debounce.
        var relieve: () -> Void
    }

    /// A panel or window the run shows and closes.
    struct Surface {
        let name: String
        var show: () -> Void
        var isShown: () -> Bool
        var close: () -> Void
    }

    /// How long the run waits at each step.
    struct Timing {
        var cycles = 3
        var shown: Duration = .seconds(2)
        var closed: Duration = .seconds(3)
        /// Layout loads item pictures as it opens.
        var settingsShown: Duration = .seconds(4)
        /// Past the 3 s presentation guard and the relief debounce, so the window's content is gone.
        var settingsClosed: Duration = .seconds(5)
        var trim: Duration = MenuBarItemImageCache.idleTrimDelay + .seconds(5)
        var relief: Duration = .seconds(3)
        var settleInterval: Duration = .seconds(5)
        var settleSamples = 12
    }
}

// MARK: - Stages, budgets and output

extension ResidentBench {
    /// A stage of the run, in the order the run reaches it.
    nonisolated enum Stage: String, CaseIterable, Sendable {
        case started
        case scanSettled = "scan-settled"
        case thawBarCycled = "thaw-bar-x3"
        case searchCycled = "search-x3"
        case settingsClosed = "settings-layout"
        case trimmed
        case settled

        var budget: Double {
            switch self {
            case .started: Budget.started
            case .scanSettled: Budget.scanSettled
            case .thawBarCycled: Budget.thawBarCycled
            case .searchCycled: Budget.searchCycled
            case .settingsClosed: Budget.settingsClosed
            case .trimmed: Budget.trimmed
            case .settled: Budget.settled
            }
        }
    }

    /// The most each stage may hold, in MiB. First guesses from one Mac, about 30 MB just after launch and
    /// 83 MB after four hours, set loose so a normal run passes. Calibrate them from runs on several Macs.
    nonisolated enum Budget {
        static let started: Double = 50
        static let scanSettled: Double = 60
        static let thawBarCycled: Double = 90
        static let searchCycled: Double = 100
        /// The first Settings window in the app keeps about 13 MB of SwiftUI caches for good, so this leaves room for it.
        static let settingsClosed: Double = 100
        static let trimmed: Double = 90
        static let settled: Double = 90
    }

    nonisolated struct Sample: Equatable, Sendable {
        let stage: Stage
        /// Nil when the kernel would not report the footprint.
        let megabytes: Double?
    }

    /// The lines scripts/bench-resident.sh reads, and the verdict.
    nonisolated enum Report {
        static let prefix = "RESIDENT"

        static func line(for sample: Sample) -> String {
            let budget = String(format: "%.0f", sample.stage.budget)
            guard let megabytes = sample.megabytes else {
                return "\(prefix) \(sample.stage.rawValue) unreadable budget \(budget)"
            }
            return "\(prefix) \(sample.stage.rawValue) \(String(format: "%.2f", megabytes)) MiB budget \(budget)"
        }

        /// Everything wrong with a run: its notes, unreadable or over-budget samples, and stages not reached.
        /// The unrounded value is compared, so 90.004 MiB is over a 90 MiB budget.
        static func problems(samples: [Sample], notes: [String]) -> [String] {
            var problems = notes
            for sample in samples {
                guard let megabytes = sample.megabytes else {
                    problems.append("\(sample.stage.rawValue): footprint unreadable")
                    continue
                }
                if megabytes > sample.stage.budget {
                    problems.append(
                        "\(sample.stage.rawValue): \(String(format: "%.2f", megabytes)) MiB, over its \(String(format: "%.0f", sample.stage.budget)) MiB budget"
                    )
                }
            }
            let reached = samples.map(\.stage)
            if reached != Array(Stage.allCases.prefix(reached.count)) {
                problems.append("stages out of order: \(reached.map(\.rawValue).joined(separator: ", "))")
            } else if reached.count < Stage.allCases.count {
                let missing = Stage.allCases.dropFirst(reached.count).map(\.rawValue)
                problems.append("not reached: \(missing.joined(separator: ", "))")
            }
            return problems
        }

        static func verdictLine(problems: [String]) -> String {
            problems.isEmpty ? "\(prefix) PASS" : "\(prefix) FAIL: \(problems.joined(separator: "; "))"
        }
    }
}
