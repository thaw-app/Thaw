//  Adapted from Barometer (https://github.com/mackid1993/Barometer)
//  Copyright (Barometer) © 2026 mackid1993. Used with permission.
//  Licensed under the GNU GPLv3
//
//  CPUSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

/// Cumulative Mach scheduler ticks for one logical CPU.
struct CPUCoreTicks: Sendable {
    /// User-mode ticks.
    let user: UInt64

    /// System-mode ticks.
    let system: UInt64

    /// Idle ticks.
    let idle: UInt64
}

/// Cumulative ticks for every logical CPU.
struct CPUTickSnapshot: Sendable {
    /// Per-core counters in logical CPU order.
    let cores: [CPUCoreTicks]
}

/// Reads per-CPU scheduler counters from Mach.
struct CPUSource: Sendable {
    /// Reads cumulative scheduler ticks for every logical CPU.
    func readTicks() throws -> CPUTickSnapshot {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        // Each mach_host_self() call adds a send-right reference; release it to avoid leaking at every sample.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else {
            throw CPUSourceError.machError(result)
        }

        defer {
            let byteCount = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), byteCount)
        }

        let values = UnsafeBufferPointer(start: processorInfo, count: Int(processorInfoCount))
        let stateCount = Int(CPU_STATE_MAX)
        let cores = (0 ..< Int(processorCount)).map { coreIndex in
            let base = coreIndex * stateCount
            return CPUCoreTicks(
                user: UInt64(values[base + Int(CPU_STATE_USER)]),
                system: UInt64(values[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(values[base + Int(CPU_STATE_IDLE)])
            )
        }
        return CPUTickSnapshot(cores: cores)
    }
}

/// Errors emitted by the Mach CPU source.
enum CPUSourceError: Error, Sendable {
    case machError(kern_return_t)
}
