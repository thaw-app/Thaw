//
//  HookProcess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

/// Process-group launcher shared by profile hooks and script-result triggers.
extension HookRunner {
    /// Process wrapper that launches every hook in its own process group. A
    /// timeout can therefore terminate descendants a shell hook leaves in the
    /// background, rather than only killing the direct script process.
    final nonisolated class HookProcess: @unchecked Sendable {
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
            // Close pipe readers before any dup2. A GUI-launched process can inherit
            // stdout/stderr closed, so Pipe() may reuse fd 1 or 2, and closing it after
            // dup2 would close the child's new stdout/stderr.
            try check(posix_spawn_file_actions_addclose(&fileActions, stdoutReadFD))
            try check(posix_spawn_file_actions_addclose(&fileActions, stderrReadFD))

            // Close each writer right after its dup2, so a writer that reused fd 1 or 2
            // can't close a descriptor the next dup2 just filled.
            try check(posix_spawn_file_actions_adddup2(&fileActions, stdoutWriteFD, STDOUT_FILENO))
            if stdoutWriteFD != STDOUT_FILENO {
                try check(posix_spawn_file_actions_addclose(&fileActions, stdoutWriteFD))
            }
            try check(posix_spawn_file_actions_adddup2(&fileActions, stderrWriteFD, STDERR_FILENO))
            if stderrWriteFD != STDERR_FILENO {
                try check(posix_spawn_file_actions_addclose(&fileActions, stderrWriteFD))
            }

            return try spawnInOwnProcessGroup(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                fileActions: &fileActions,
                attributes: &attributes
            )
        }

        /// Puts the child in its own process group, then spawns it. A pgroup of zero
        /// makes the child PID the group ID, so signalling `-pid` reaps the whole hook
        /// tree on cancellation or timeout.
        private static func spawnInOwnProcessGroup(
            executablePath: String,
            arguments: [String],
            environment: [String: String],
            fileActions: inout posix_spawn_file_actions_t?,
            attributes: inout posix_spawnattr_t?
        ) throws -> HookProcess {
            try check(posix_spawnattr_setpgroup(&attributes, 0))
            try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)))

            let argv = [executablePath] + arguments
            let environmentEntries = environment.map { "\($0.key)=\($0.value)" }
            return try withCStringArray(argv) { argvPointer in
                try withCStringArray(environmentEntries) { environmentPointer in
                    try spawnAndCheck(
                        executablePath: executablePath,
                        argvPointer: argvPointer,
                        environmentPointer: environmentPointer,
                        fileActions: &fileActions,
                        attributes: &attributes
                    )
                }
            }
        }

        /// The actual posix_spawn, extracted from the launchers so their
        /// argument-pinning closures stay two deep. Caller pins the argument
        /// and environment arrays; this pins the executable path itself.
        private static func spawnAndCheck(
            executablePath: String,
            argvPointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
            environmentPointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
            fileActions: inout posix_spawn_file_actions_t?,
            attributes: inout posix_spawnattr_t?
        ) throws -> HookProcess {
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

            return try spawnInOwnProcessGroup(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                fileActions: &fileActions,
                attributes: &attributes
            )
        }

        var isRunning: Bool {
            exitedStatus() == nil
        }

        var terminationStatus: Int32 {
            exitedStatus() ?? -1
        }

        /// Whether any member of the child's process group is still alive.
        ///
        /// A group-directed `kill` returns before the kernel has torn the
        /// members down, so callers that promise "no descendants survive"
        /// must poll this rather than trust the `kill` return value.
        var hasLiveProcessGroup: Bool {
            Darwin.kill(-processIdentifier, 0) == 0
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
            var result = waitpid(processIdentifier, &waitStatus, WNOHANG)
            while result == -1, errno == EINTR {
                result = waitpid(processIdentifier, &waitStatus, WNOHANG)
            }
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
            // Failure means terminated. `waitpid` returns -1 with ECHILD once reaped (or
            // if never ours), and treating that as running traps `isRunning` pollers
            // forever. Only result 0 means still running.
            if result == -1 {
                completedStatus = -1
                return -1
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
