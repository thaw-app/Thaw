//
//  MemoryReclaimer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Darwin
import Foundation
import MenuBarModel

/// Return wholly free malloc pages after large closes; partially occupied pages remain resident until reused.
/// Debounce close bursts and memory-pressure events so cache cleanup finishes before one sweep.
enum MemoryReclaimer {
    private static let diagLog = DiagLog(category: "MemoryReclaimer")

    /// Allow delayed SwiftUI graph teardown to finish before sweeping.
    private static let debounce: Duration = .seconds(1)

    private static var pendingRelief: Task<Void, Never>?
    private static var pressureSource: DispatchSourceMemoryPressure?
    private static var footprintLog: Task<Void, Never>?

    /// How often the footprint goes into the log, so a slow climb shows when it began.
    static let footprintLogInterval: Duration = .seconds(600)
    /// Far above a settled Thaw (about 40 MB); passing it once gets a warning.
    nonisolated static let footprintWarningMegabytes: UInt64 = 150

    /// Starts listening for system memory pressure. Called once at launch.
    static func start() {
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler {
            // Caches clear on this event too; debounce lets cleanup finish before sweeping.
            scheduleRelief(reason: "system memory pressure")
        }
        source.resume()
        pressureSource = source
        startFootprintLog()
    }

    private static func startFootprintLog() {
        footprintLog = Task {
            var warned = false
            // The continuous clock keeps counting while the Mac sleeps.
            for await _ in AsyncTimerSequence(interval: footprintLogInterval, clock: .continuous) {
                guard let footprint = physicalFootprint() else { continue }
                warned = logFootprint(megabytes: footprint / 1_048_576, alreadyWarned: warned)
            }
        }
    }

    /// Logs one footprint sample, as a warning the first time it passes the
    /// line. Returns whether the warning has been given.
    static func logFootprint(megabytes: UInt64, alreadyWarned: Bool) -> Bool {
        guard shouldWarn(megabytes: megabytes, alreadyWarned: alreadyWarned) else {
            diagLog.info("footprint \(megabytes) MB")
            return alreadyWarned
        }
        diagLog.warning("footprint \(megabytes) MB, above \(footprintWarningMegabytes) MB")
        return true
    }

    /// Warns the first time the footprint passes the line, not on every sample after.
    static nonisolated func shouldWarn(megabytes: UInt64, alreadyWarned: Bool) -> Bool {
        !alreadyWarned && megabytes > footprintWarningMegabytes
    }

    /// Runs a relief sweep once closes stop arriving for a moment.
    static func scheduleRelief(reason: String) {
        pendingRelief?.cancel()
        pendingRelief = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await relieve(reason: reason)
        }
    }

    private static func relieve(reason: String) async {
        let before = physicalFootprint()
        // Sweeping locks every zone's free lists; run off-main to avoid UI stalls on large heaps.
        await Task.detached(priority: .utility) {
            _ = malloc_zone_pressure_relief(nil, 0)
        }.value
        let after = physicalFootprint()
        if let before, let after {
            diagLog.info(
                "Relief after \(reason): footprint \(before / 1_048_576) MB -> \(after / 1_048_576) MB"
            )
        } else {
            diagLog.info("Relief after \(reason)")
        }
    }

    /// Physical footprint matching footprint(1) and Activity Monitor.
    static nonisolated func physicalFootprint() -> UInt64? {
        var info = rusage_info_v4()
        // proc_pid_rusage's pointer-to-pointer type expects the struct address itself.
        // Rebind it; passing a pointer to a local pointer would overrun that local.
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            UnsafeMutableRawPointer(pointer)
                .withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { buffer in
                    proc_pid_rusage(getpid(), RUSAGE_INFO_V4, buffer)
                }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }
}
