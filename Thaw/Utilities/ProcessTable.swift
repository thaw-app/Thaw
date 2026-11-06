//
//  ProcessTable.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin

/// Reads another process's parent and state from the kernel, which answers even before AppKit has
/// noticed that an app quit.
nonisolated enum ProcessTable {
    struct Entry: Equatable {
        var parentProcessIdentifier: pid_t
        var isZombie: Bool
    }

    /// The process's kernel entry, or nil when no such process exists.
    static func entry(for processIdentifier: pid_t) -> Entry? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        return Entry(
            parentProcessIdentifier: info.kp_eproc.e_ppid,
            isZombie: Int32(info.kp_proc.p_stat) == SZOMB
        )
    }

    /// True while the process exists and has not exited.
    static func isRunning(_ processIdentifier: pid_t) -> Bool {
        entry(for: processIdentifier).map { !$0.isZombie } ?? false
    }
}
