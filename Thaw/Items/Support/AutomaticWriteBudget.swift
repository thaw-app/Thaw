//
//  AutomaticWriteBudget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Caps how often automatic passes may write while nobody touches the bar. Past the limit they
/// pause, which breaks a loop of repairs answering each other.
nonisolated struct AutomaticWriteBudget {
    static let limit = 4
    static let window = Duration.seconds(30)
    static let pause = Duration.seconds(60)

    private var writingPasses = [ContinuousClock.Instant]()
    private var pausedUntil: ContinuousClock.Instant?

    func allowsAutomaticWrites(at now: ContinuousClock.Instant = .now) -> Bool {
        pausedUntil.map { now >= $0 } ?? true
    }

    /// Records an automatic pass that wrote, and returns true when it starts a pause.
    @discardableResult
    mutating func noteWritingPass(at now: ContinuousClock.Instant = .now) -> Bool {
        writingPasses.removeAll { $0.duration(to: now) >= Self.window }
        writingPasses.append(now)
        guard writingPasses.count > Self.limit else { return false }
        writingPasses.removeAll()
        pausedUntil = now + Self.pause
        return true
    }

    mutating func noteUserAction() {
        writingPasses.removeAll()
        pausedUntil = nil
    }
}
