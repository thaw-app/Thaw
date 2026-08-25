//
//  DiagnosticLoggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - DiagnosticLogger.Level Tests

/// Pins the raw values of ``DiagnosticLogger/Level``.
///
/// The raw values are written verbatim into every diagnostic log line, so
/// they are a parsed format rather than an implementation detail.
///
/// Reads only: nothing here reaches the shared ``DiagnosticLogger`` or any
/// other process-global state, so the suite is safe to run in parallel with
/// the rest.
@Suite("Diagnostic logger levels")
struct DiagnosticLoggerLevelTests {
    // MARK: - Raw Values

    @Test("The debug level's raw value is DEBUG")
    func debugRawValue() {
        #expect(DiagnosticLogger.Level.debug.rawValue == "DEBUG")
    }

    @Test("The info level's raw value is INFO")
    func infoRawValue() {
        #expect(DiagnosticLogger.Level.info.rawValue == "INFO")
    }

    @Test("The notice level's raw value is NOTICE")
    func noticeRawValue() {
        #expect(DiagnosticLogger.Level.notice.rawValue == "NOTICE")
    }

    @Test("The warning level's raw value is WARNING")
    func warningRawValue() {
        #expect(DiagnosticLogger.Level.warning.rawValue == "WARNING")
    }

    @Test("The error level's raw value is ERROR")
    func errorRawValue() {
        #expect(DiagnosticLogger.Level.error.rawValue == "ERROR")
    }

    // MARK: - Init From Raw Value

    @Test("DEBUG initializes the debug level")
    func initFromDebugRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "DEBUG")
        #expect(level == .debug)
    }

    @Test("INFO initializes the info level")
    func initFromInfoRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "INFO")
        #expect(level == .info)
    }

    @Test("NOTICE initializes the notice level")
    func initFromNoticeRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "NOTICE")
        #expect(level == .notice)
    }

    @Test("WARNING initializes the warning level")
    func initFromWarningRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "WARNING")
        #expect(level == .warning)
    }

    @Test("ERROR initializes the error level")
    func initFromErrorRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "ERROR")
        #expect(level == .error)
    }

    @Test("An unrecognized raw value initializes nothing")
    func initFromInvalidRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "INVALID")
        #expect(level == nil)
    }

    @Test("A lowercase raw value initializes nothing")
    func initFromLowercaseRawValue() {
        // Raw values are case-sensitive
        let level = DiagnosticLogger.Level(rawValue: "debug")
        #expect(level == nil)
    }

    // MARK: - All Levels

    @Test("Every level has an uppercase raw value")
    func allLevelsHaveUppercaseRawValues() {
        for level in DiagnosticLogger.Level.allCases {
            #expect(level.rawValue == level.rawValue.uppercased(),
                    "Level \(level) should have uppercase raw value")
        }
    }

    @Test("Every level has a distinct raw value")
    func allLevelsAreDistinct() {
        let levels = DiagnosticLogger.Level.allCases
        let rawValues = Set(levels.map(\.rawValue))

        #expect(rawValues.count == levels.count,
                "All levels should have distinct raw values")
    }
}

// MARK: - Retention Tests

/// Covers which log files ``DiagnosticLogger/filesToPrune(_:retentionDays:maxCount:now:protected:)``
/// selects for deletion.
///
/// The decision is pure — dates and URLs in, URLs out — so these run against
/// paths that need not exist. Deleting the wrong file loses the log a user was
/// about to attach to a bug report, so each rule is pinned separately.
///
/// Reads only: nothing here reaches the shared ``DiagnosticLogger`` or the file
/// system, so the suite is safe to run in parallel with the rest.
@Suite("Diagnostic log retention")
struct DiagnosticLoggerRetentionTests {
    private let directory = URL(fileURLWithPath: "/tmp/ThawLogsTests", isDirectory: true)

    private func logFile(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private func daysAgo(_ days: Double, from now: Date) -> Date {
        now.addingTimeInterval(-days * 86400)
    }

    @Test("A file older than the retention window is pruned, a newer one is kept")
    func prunesFilesPastRetentionWindow() {
        let now = Date()
        let fresh = logFile("thaw_fresh.log")
        let old = logFile("thaw_old.log")

        let stale = DiagnosticLogger.filesToPrune(
            [(url: fresh, created: daysAgo(0.5, from: now)),
             (url: old, created: daysAgo(5, from: now))],
            retentionDays: 2,
            maxCount: 100,
            now: now,
            protected: []
        )

        #expect(stale == [old])
    }

    @Test("Protected files survive both the age limit and the count cap")
    func neverPrunesProtectedFiles() {
        let now = Date()
        let current = logFile("thaw_current.log")
        let previous = logFile("thaw_previous.log")

        let stale = DiagnosticLogger.filesToPrune(
            [(url: current, created: daysAgo(10, from: now)),
             (url: previous, created: daysAgo(9, from: now))],
            retentionDays: 2,
            maxCount: 1,
            now: now,
            protected: [current, previous]
        )

        #expect(stale.isEmpty,
                "The current and just-rotated segments may still have open descriptors")
    }

    @Test("Files beyond the count cap are pruned oldest first")
    func enforcesCountCap() {
        let now = Date()
        let newest = logFile("thaw_1.log")
        let middle = logFile("thaw_2.log")
        let oldest = logFile("thaw_3.log")

        // All three are well inside the retention window; only the cap applies.
        let stale = DiagnosticLogger.filesToPrune(
            [(url: newest, created: daysAgo(0.1, from: now)),
             (url: middle, created: daysAgo(0.2, from: now)),
             (url: oldest, created: daysAgo(0.3, from: now))],
            retentionDays: 30,
            maxCount: 2,
            now: now,
            protected: []
        )

        #expect(stale == [oldest])
    }

    @Test("Nothing is pruned while inside both limits")
    func keepsFilesInsideBothLimits() {
        let now = Date()

        let stale = DiagnosticLogger.filesToPrune(
            [(url: logFile("thaw_a.log"), created: daysAgo(0.1, from: now)),
             (url: logFile("thaw_b.log"), created: daysAgo(0.2, from: now))],
            retentionDays: 2,
            maxCount: 100,
            now: now,
            protected: []
        )

        #expect(stale.isEmpty)
    }

    @Test("Everything unprotected goes when the cap is smaller than the protected set")
    func prunesEverythingWhenProtectedFillsTheCap() {
        let now = Date()
        let current = logFile("thaw_current.log")
        let spare = logFile("thaw_spare.log")

        let stale = DiagnosticLogger.filesToPrune(
            [(url: current, created: now),
             (url: spare, created: daysAgo(0.1, from: now))],
            retentionDays: 30,
            maxCount: 1,
            now: now,
            protected: [current]
        )

        // The protected file alone fills the cap, so nothing else may stay —
        // and the subtraction that works that out must not go negative.
        #expect(stale == [spare])
    }

    @Test("Files of the same age are pruned in a stable order")
    func breaksAgeTiesByPath() {
        let now = Date()
        let sameMoment = daysAgo(0.5, from: now)
        let first = logFile("thaw_a.log")
        let second = logFile("thaw_b.log")

        // Only one of the two fits under the cap. Directory order must not
        // decide which; the tie is broken by path, so `thaw_a.log` survives.
        let stale = DiagnosticLogger.filesToPrune(
            [(url: second, created: sameMoment), (url: first, created: sameMoment)],
            retentionDays: 30,
            maxCount: 1,
            now: now,
            protected: []
        )

        #expect(stale == [second])
    }
}

// MARK: - Rotation Policy Tests

/// Covers ``DiagnosticLogger/RotationPolicy/sanitized()``.
///
/// A policy reaches the MenuBarItemService target over XPC, and a build signed
/// without a team identifier accepts messages from any local process, so these
/// values are untrusted input. Left as they arrive they can delete every log or
/// trap the arithmetic that decides what to keep.
///
/// Reads only: safe to run in parallel with the rest.
@Suite("Diagnostic log rotation policy")
struct DiagnosticLoggerRotationPolicyTests {
    @Test("A retention of zero or less becomes a day")
    func clampsRetentionToAtLeastOneDay() {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.retentionDays = -5

        // A negative retention would put the cutoff in the future, which reads
        // as "every log is too old".
        #expect(policy.sanitized().retentionDays == 1)
    }

    @Test("A file count of zero becomes one")
    func clampsFileCountToAtLeastOne() {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.maxFileCount = 0

        #expect(policy.sanitized().maxFileCount == 1)
    }

    @Test("An extreme file count cannot survive to overflow the allowance")
    func clampsExtremeFileCount() {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.maxFileCount = .min

        let sanitized = policy.sanitized()
        #expect(sanitized.maxFileCount == 1)

        // The value that used to trap: subtracting the protected count from it.
        let stale = DiagnosticLogger.filesToPrune(
            [],
            retentionDays: sanitized.retentionDays,
            maxCount: sanitized.maxFileCount,
            now: Date(),
            protected: [URL(fileURLWithPath: "/tmp/ThawLogsTests/thaw.log")]
        )
        #expect(stale.isEmpty)
    }

    @Test("A non-finite rotation interval turns scheduled rotation off")
    func rejectsNonFiniteInterval() {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.rotationInterval = .nan
        #expect(policy.sanitized().rotationInterval == 0)

        // Infinity is not finite either, so it means "never", not "always".
        policy.rotationInterval = .infinity
        #expect(policy.sanitized().rotationInterval == 0)
    }

    @Test("Sizes and intervals are held under their ceilings")
    func clampsSizeAndInterval() {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.maxFileSizeBytes = .max
        policy.rotationInterval = .greatestFiniteMagnitude

        let sanitized = policy.sanitized()
        #expect(sanitized.maxFileSizeBytes == DiagnosticLogger.RotationPolicy.maxSizeBytes)
        #expect(sanitized.rotationInterval == DiagnosticLogger.RotationPolicy.maxRotationInterval)
    }

    @Test("A policy the settings UI can produce passes through untouched")
    func leavesReasonableValuesAlone() {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.maxFileSizeBytes = 10 * 1024 * 1024
        policy.rotationInterval = 3600
        policy.retentionDays = 2
        policy.maxFileCount = 50

        #expect(policy.sanitized() == policy)
    }
}

// MARK: - File Name Tests

/// Covers the collision handling in
/// ``DiagnosticLogger/uniqueLogFileURL(in:baseName:exists:)``.
///
/// Log file names carry a second-granular timestamp, so rotating twice inside
/// one second would otherwise reuse a name and append to a segment already in
/// use. Existence is injected, so these run without touching the file system.
///
/// Reads only: safe to run in parallel with the rest.
@Suite("Diagnostic log file names")
struct DiagnosticLoggerFileNameTests {
    private let directory = URL(fileURLWithPath: "/tmp/ThawLogsTests", isDirectory: true)
    private let baseName = "thaw_2026-06-07_09-48-52"

    @Test("An unused name is taken as is")
    func usesBaseNameWhenFree() {
        let url = DiagnosticLogger.uniqueLogFileURL(in: directory, baseName: baseName) { _ in false }

        #expect(url.lastPathComponent == "thaw_2026-06-07_09-48-52.log")
    }

    @Test("A taken name gains a numeric suffix")
    func appendsSuffixOnCollision() {
        let taken: Set<URL> = [directory.appendingPathComponent("\(baseName).log")]

        let url = DiagnosticLogger.uniqueLogFileURL(in: directory, baseName: baseName) { taken.contains($0) }

        #expect(url.lastPathComponent == "thaw_2026-06-07_09-48-52_2.log")
    }

    @Test("The suffix keeps climbing until a name is free")
    func incrementsSuffixUntilFree() {
        let taken: Set<URL> = [
            directory.appendingPathComponent("\(baseName).log"),
            directory.appendingPathComponent("\(baseName)_2.log"),
        ]

        let url = DiagnosticLogger.uniqueLogFileURL(in: directory, baseName: baseName) { taken.contains($0) }

        #expect(url.lastPathComponent == "thaw_2026-06-07_09-48-52_3.log")
    }
}
