//
//  HookProcess.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

/// Process-group launcher shared by profile hooks and script-result triggers.
///
/// Extracted from the trigger branch's `HookRunner` rewrite so the trigger
/// feature can reuse the process-group semantics without re-landing that
/// file's unrelated refactor on top of the current `HookRunner`.
extension HookRunner {
    /// Process wrapper that launches every hook in its own process group. A
    /// timeout can therefore terminate descendants a shell hook leaves in the
    /// background, rather than only killing the direct script process.
    nonisolated final class HookProcess: @unchecked Sendable {
        let processIdentifier: pid_t

        private let lock = NSLock()
        private var completedStatus: Int32?

        private init(processIdentifier: pid_t) {
            self.processIdentifier = processIdentifier
        }

        static func launch(
            executablePath: String,
            arguments: [String],
            environment: [String: String],
            standardOutput: Pipe,
            standardError: Pipe
        ) throws -> HookProcess {
            var fileActions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
            try check(posix_spawn_file_actions_init(&fileActions))
            defer { posix_spawn_file_actions_destroy(&fileActions) }
            try check(posix_spawnattr_init(&attributes))
            defer { posix_spawnattr_destroy(&attributes) }

            let stdoutReadFD = standardOutput.fileHandleForReading.fileDescriptor
            let stdoutWriteFD = standardOutput.fileHandleForWriting.fileDescriptor
            let stderrReadFD = standardError.fileHandleForReading.fileDescriptor
            let stderrWriteFD = standardError.fileHandleForWriting.fileDescriptor
            // Close pipe readers before assigning either standard descriptor.
            // A GUI-launched process can inherit stdout or stderr closed, in
            // which case Pipe() may reuse fd 1 or 2 for one of those readers.
            // Closing it after dup2 would otherwise close the child's newly
            // connected stdout/stderr instead.
            try check(posix_spawn_file_actions_addclose(&fileActions, stdoutReadFD))
            try check(posix_spawn_file_actions_addclose(&fileActions, stderrReadFD))

            // Close each original writer immediately after its dup2. This
            // avoids accidentally closing a standard descriptor that the
            // next dup2 has just populated when a pipe writer itself reused
            // fd 1 or 2.
            try check(posix_spawn_file_actions_adddup2(&fileActions, stdoutWriteFD, STDOUT_FILENO))
            if stdoutWriteFD != STDOUT_FILENO {
                try check(posix_spawn_file_actions_addclose(&fileActions, stdoutWriteFD))
            }
            try check(posix_spawn_file_actions_adddup2(&fileActions, stderrWriteFD, STDERR_FILENO))
            if stderrWriteFD != STDERR_FILENO {
                try check(posix_spawn_file_actions_addclose(&fileActions, stderrWriteFD))
            }

            // A pgroup of zero creates a new group whose ID is the spawned
            // child PID. We can then signal `-pid` to reap the complete hook
            // tree on cancellation or timeout.
            try check(posix_spawnattr_setpgroup(&attributes, 0))
            try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)))

            let argv = [executablePath] + arguments
            let environmentEntries = environment.map { "\($0.key)=\($0.value)" }
            return try withCStringArray(argv) { argvPointer in
                try withCStringArray(environmentEntries) { environmentPointer in
                    var processIdentifier: pid_t = 0
                    let result = executablePath.withCString { executablePath in
                        posix_spawn(
                            &processIdentifier,
                            executablePath,
                            &fileActions,
                            &attributes,
                            argvPointer,
                            environmentPointer
                        )
                    }
                    try check(result)
                    return HookProcess(processIdentifier: processIdentifier)
                }
            }
        }

        /// Launches a process group whose stdout and stderr both write to the
        /// same pipe. Script-result triggers use this so a timeout has the
        /// same descendant-cleanup guarantee as profile hooks.
        static func launch(
            executablePath: String,
            arguments: [String],
            environment: [String: String],
            combinedOutput: Pipe
        ) throws -> HookProcess {
            var fileActions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
            try check(posix_spawn_file_actions_init(&fileActions))
            defer { posix_spawn_file_actions_destroy(&fileActions) }
            try check(posix_spawnattr_init(&attributes))
            defer { posix_spawnattr_destroy(&attributes) }

            let outputReadFD = combinedOutput.fileHandleForReading.fileDescriptor
            let outputWriteFD = combinedOutput.fileHandleForWriting.fileDescriptor
            // The app may have inherited fd 1 or 2 closed, allowing Pipe to
            // reuse it for its reader. Close that reader before either dup2,
            // never after it has become the child's stdout or stderr.
            try check(posix_spawn_file_actions_addclose(&fileActions, outputReadFD))
            try check(posix_spawn_file_actions_adddup2(&fileActions, outputWriteFD, STDOUT_FILENO))
            try check(posix_spawn_file_actions_adddup2(&fileActions, outputWriteFD, STDERR_FILENO))
            if outputWriteFD != STDOUT_FILENO, outputWriteFD != STDERR_FILENO {
                try check(posix_spawn_file_actions_addclose(&fileActions, outputWriteFD))
            }

            try check(posix_spawnattr_setpgroup(&attributes, 0))
            try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)))

            let argv = [executablePath] + arguments
            let environmentEntries = environment.map { "\($0.key)=\($0.value)" }
            return try withCStringArray(argv) { argvPointer in
                try withCStringArray(environmentEntries) { environmentPointer in
                    var processIdentifier: pid_t = 0
                    let result = executablePath.withCString { executablePath in
                        posix_spawn(
                            &processIdentifier,
                            executablePath,
                            &fileActions,
                            &attributes,
                            argvPointer,
                            environmentPointer
                        )
                    }
                    try check(result)
                    return HookProcess(processIdentifier: processIdentifier)
                }
            }
        }

        var isRunning: Bool {
            exitedStatus() == nil
        }

        var terminationStatus: Int32 {
            exitedStatus() ?? -1
        }

        func terminate() {
            signal(SIGTERM)
        }

        func interrupt() {
            signal(SIGINT)
        }

        func kill() {
            signal(SIGKILL)
        }

        private func signal(_ signal: Int32) {
            // `-pid` targets the isolated process group. Do not fall back to
            // the direct PID: after it exits, PID reuse could signal an
            // unrelated process while a remaining descendant still needs the
            // group-directed signal.
            _ = Darwin.kill(-processIdentifier, signal)
        }

        private func exitedStatus() -> Int32? {
            lock.lock()
            defer { lock.unlock() }
            if let completedStatus {
                return completedStatus
            }

            var waitStatus: Int32 = 0
            let result = waitpid(processIdentifier, &waitStatus, WNOHANG)
            if result == processIdentifier {
                let signal = waitStatus & 0x7F
                let status: Int32 = if signal == 0 {
                    (waitStatus >> 8) & 0xFF
                } else {
                    128 + signal
                }
                completedStatus = status
                return status
            }
            return nil
        }

        private static func check(_ result: Int32) throws {
            guard result == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
            }
        }

        private static func withCStringArray<Result>(
            _ strings: [String],
            body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
        ) throws -> Result {
            let pointers = strings.map { strdup($0) }
            defer { pointers.forEach { free($0) } }
            var nilTerminatedPointers = pointers
            nilTerminatedPointers.append(nil)
            return try nilTerminatedPointers.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
                }
                return try body(baseAddress)
            }
        }
    }
}
