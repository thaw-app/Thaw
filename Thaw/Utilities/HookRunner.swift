//
//  HookRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

/// Executes user-supplied profile-apply hooks with a wall-clock timeout
/// and pipes their output to DiagLog.
///
/// AppleScript files (.scpt / .applescript / .scptd) are routed through
/// /usr/bin/osascript so the user does not need to chmod +x them. All
/// other paths are launched directly and must carry the executable bit.
enum HookRunner {
    private static let diagLog = DiagLog(category: "HookRunner")

    /// Default path to the AppleScript interpreter on macOS. Overridable
    /// per call via the `osascriptPath` parameter on `run` / `runIfEnabled`
    /// (used in tests; production callers take the default).
    static let defaultOSAScriptPath = "/usr/bin/osascript"

    /// File extensions routed through osascript.
    private static let appleScriptExtensions: Set<String> = [
        "scpt",
        "applescript",
        "scptd",
    ]

    enum HookError: Error, CustomStringConvertible {
        case fileMissing(path: String)
        case notExecutable(path: String)
        case launchFailed(path: String, error: Error)
        case timedOut(after: Double)
        case nonZeroExit(Int32)

        var description: String {
            switch self {
            case let .fileMissing(p): return "hook file missing: \(p)"
            case let .notExecutable(p): return "hook file not executable (run chmod +x): \(p)"
            case let .launchFailed(p, e): return "hook launch failed for \(p): \(e)"
            case let .timedOut(s): return "hook timed out after \(s)s"
            case let .nonZeroExit(s): return "hook exited with status \(s)"
            }
        }
    }

    /// Result of a successful hook run.
    struct RunOutcome {
        let exitStatus: Int32
        let stdout: String
        let stderr: String
    }

    /// Context passed into the hook as environment variables.
    struct Context {
        let phase: HookPhase
        let scope: HookScope
        let profileID: UUID
        let profileName: String
        let previousProfileID: UUID?
        let previousProfileName: String?
    }

    /// Non-throwing wrapper. Logs every outcome (success, failure, skip)
    /// and never propagates errors so the apply pipeline keeps moving.
    static func runIfEnabled(
        _ hook: HookScript?,
        context: Context,
        osascriptPath: String = defaultOSAScriptPath
    ) async {
        guard let hook else { return }
        guard hook.isEnabled else {
            diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook disabled, skipping: \(hook.path)")
            return
        }
        do {
            let outcome = try await run(hook, context: context, osascriptPath: osascriptPath)
            diagLog.debug(
                "\(context.scope.rawValue) \(context.phase.rawValue)-hook ok (exit=\(outcome.exitStatus)): \(hook.path)"
            )
            if !outcome.stdout.isEmpty {
                diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook stdout: \(outcome.stdout)")
            }
            if !outcome.stderr.isEmpty {
                diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook stderr: \(outcome.stderr)")
            }
        } catch is CancellationError {
            diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook cancelled: \(hook.path)")
        } catch {
            diagLog.error(
                "\(context.scope.rawValue) \(context.phase.rawValue)-hook failed (\(hook.path)): \(error)"
            )
        }
    }

    /// Throws on failure. Used by the wrapper above; exposed for callers
    /// that want the outcome (none today, but keeps the API honest).
    static func run(
        _ hook: HookScript,
        context: Context,
        osascriptPath: String = defaultOSAScriptPath
    ) async throws -> RunOutcome {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: hook.path)
        guard fm.fileExists(atPath: url.path) else {
            throw HookError.fileMissing(path: hook.path)
        }

        let ext = url.pathExtension.lowercased()
        let useOSAScript = appleScriptExtensions.contains(ext)

        // Verify the executable bit for direct-launch scripts. AppleScript
        // files are read by osascript, so they need read but not execute.
        if !useOSAScript, !fm.isExecutableFile(atPath: url.path) {
            throw HookError.notExecutable(path: hook.path)
        }

        let executablePath: String
        let arguments: [String]
        if useOSAScript {
            executablePath = osascriptPath
            arguments = [url.path]
        } else {
            executablePath = url.path
            arguments = []
        }

        // Merge our env vars on top of the process's inherited environment.
        var env = ProcessInfo.processInfo.environment
        env["THAW_HOOK_PHASE"] = context.phase.rawValue.capitalized
        env["THAW_HOOK_SCOPE"] = context.scope.rawValue.capitalized
        env["THAW_PROFILE_ID"] = context.profileID.uuidString
        env["THAW_PROFILE_NAME"] = context.profileName
        env["THAW_PREVIOUS_PROFILE_ID"] = context.previousProfileID?.uuidString ?? ""
        env["THAW_PREVIOUS_PROFILE_NAME"] = context.previousProfileName ?? ""
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutAccumulator = OutputAccumulator()
        let stderrAccumulator = OutputAccumulator()
        startDraining(stdoutPipe, into: stdoutAccumulator)
        startDraining(stderrPipe, into: stderrAccumulator)

        let clamped = max(1.0, min(hook.timeoutSeconds, 300.0))

        let process: HookProcess
        do {
            process = try HookProcess.launch(
                executablePath: executablePath,
                arguments: arguments,
                environment: env,
                standardOutput: stdoutPipe,
                standardError: stderrPipe
            )
            // The child inherited the pipe writers at launch. Close this
            // process's copies so a completed child produces EOF for the
            // final tail read below.
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
        } catch {
            _ = stopDraining(stdoutPipe, into: stdoutAccumulator)
            _ = stopDraining(stderrPipe, into: stderrAccumulator)
            throw HookError.launchFailed(path: hook.path, error: error)
        }

        // Race process termination against a sleep timeout. Whichever wins
        // tears down the other. The whole race is wrapped in a
        // withTaskCancellationHandler so external cancellation (typically
        // a newer profile apply replacing the layoutTask) also reaps the
        // subprocess instead of leaving it running orphaned. The task
        // group is factored into raceProcessAgainstTimeout so the
        // closure nesting at this call site stays within two levels.
        let exitStatus: Int32
        do {
            exitStatus = try await withTaskCancellationHandler {
                try await raceProcessAgainstTimeout(process: process, timeout: clamped)
            } onCancel: {
                // Synchronous: send SIGTERM so the polling task in the
                // helper sees isRunning flip immediately and the group
                // can unwind without waiting out the remainder of the
                // timeout. Child tasks observe cancellation through the
                // parent's propagated state, so an explicit
                // group.cancelAll here is unnecessary. The matching
                // async wait and SIGINT escalation run in the catch
                // branch below, mirroring the timeout cleanup sequence
                // inside the helper.
                process.terminate()
            }
        } catch is CancellationError {
            await terminateProcess(process)
            _ = stopDraining(stdoutPipe, into: stdoutAccumulator)
            _ = stopDraining(stderrPipe, into: stderrAccumulator)
            throw CancellationError()
        } catch {
            _ = stopDraining(stdoutPipe, into: stdoutAccumulator)
            _ = stopDraining(stderrPipe, into: stderrAccumulator)
            throw error
        }

        let stdout = stopDraining(stdoutPipe, into: stdoutAccumulator)
        let stderr = stopDraining(stderrPipe, into: stderrAccumulator)

        if exitStatus != 0 {
            throw HookError.nonZeroExit(exitStatus)
        }
        return RunOutcome(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
    }

    /// Drains a pipe while its subprocess runs. Waiting to read either pipe
    /// until after `waitUntilExit` can deadlock a hook that writes more than a
    /// pipe buffer (typically 64 KiB) to stdout or stderr.
    private static func startDraining(_ pipe: Pipe, into accumulator: OutputAccumulator) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            guard accumulator.beginRead() else { return }
            defer { accumulator.endRead() }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            accumulator.append(data)
        }
    }

    /// Stops asynchronous reads without a synchronous EOF read. A hook can
    /// deliberately leave a background child holding stdout or stderr open;
    /// waiting for EOF after the direct hook exits would then defeat its
    /// wall-clock timeout. The readability handler has already accumulated
    /// every available byte while the hook was running. A final nonblocking
    /// drain captures any last buffer whose readability callback has not run
    /// yet, without waiting for a detached child to close the pipe.
    private static func stopDraining(
        _ pipe: Pipe,
        into accumulator: OutputAccumulator
    ) -> String {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil
        accumulator.stopAcceptingReadsAndWait()
        pipe.fileHandleForWriting.closeFile()
        drainAvailableBytes(from: handle, into: accumulator)
        return accumulator.string
    }

    private static func drainAvailableBytes(from handle: FileHandle, into accumulator: OutputAccumulator) {
        let fileDescriptor = handle.fileDescriptor
        let originalFlags = fcntl(fileDescriptor, F_GETFL)
        guard originalFlags >= 0 else { return }
        guard fcntl(fileDescriptor, F_SETFL, originalFlags | O_NONBLOCK) >= 0 else { return }
        defer { _ = fcntl(fileDescriptor, F_SETFL, originalFlags) }

        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        for _ in 0 ..< 64 {
            let bytesRead = buffer.withUnsafeMutableBytes { buffer in
                Darwin.read(fileDescriptor, buffer.baseAddress, buffer.count)
            }
            if bytesRead > 0 {
                accumulator.append(Data(buffer.prefix(Int(bytesRead))))
                continue
            }
            // EOF (0) and EAGAIN both mean no additional data is available
            // without blocking. Other read errors are non-fatal because hook
            // output is diagnostic only.
            guard bytesRead < 0, errno == EINTR else { return }
        }
    }

    private final class OutputAccumulator: @unchecked Sendable {
        private static let maximumRetainedOutputBytes = 1_000_000
        private static let truncationNotice = "\n[Hook output truncated]\n"

        private let condition = NSCondition()
        private var data = Data()
        private var acceptsReads = true
        private var activeReads = 0
        private var outputWasTruncated = false

        /// Marks an asynchronous readability callback as in flight. Once
        /// draining begins, callbacks queued before the handler is cleared
        /// become no-ops rather than racing the final snapshot.
        func beginRead() -> Bool {
            condition.lock()
            defer { condition.unlock() }
            guard acceptsReads else { return false }
            activeReads += 1
            return true
        }

        func endRead() {
            condition.lock()
            activeReads -= 1
            if activeReads == 0 {
                condition.broadcast()
            }
            condition.unlock()
        }

        /// Prevents new callbacks from reading and waits for any callback
        /// that already took pipe bytes to append them before the final
        /// nonblocking drain/snapshot proceeds.
        func stopAcceptingReadsAndWait() {
            condition.lock()
            acceptsReads = false
            while activeReads > 0 {
                condition.wait()
            }
            condition.unlock()
        }

        func append(_ additionalData: Data) {
            guard !additionalData.isEmpty else { return }
            condition.lock()
            let remainingCapacity = Self.maximumRetainedOutputBytes - data.count
            if remainingCapacity > 0 {
                data.append(additionalData.prefix(remainingCapacity))
            }
            if additionalData.count > remainingCapacity {
                outputWasTruncated = true
            }
            condition.unlock()
        }

        var string: String {
            condition.lock()
            let snapshot = data
            let outputWasTruncated = outputWasTruncated
            condition.unlock()
            // swiftlint:disable:next optional_data_string_conversion
            var output = String(decoding: [UInt8](snapshot), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if outputWasTruncated {
                output.append(Self.truncationNotice)
            }
            return output
        }
    }

    /// Process wrapper that launches every hook in its own process group. A
    /// timeout can therefore terminate descendants a shell hook leaves in the
    /// background, rather than only killing the direct script process.
    final class HookProcess: @unchecked Sendable {
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

    /// Awaits whichever wins first: the process exiting, or the timeout
    /// elapsing. On exit, returns the terminationStatus. On timeout, it
    /// terminates the hook before returning HookError.timedOut.
    private static func raceProcessAgainstTimeout(
        process: HookProcess,
        timeout: Double
    ) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask { try await pollProcessExit(process) }
            group.addTask { try await timeoutTick(seconds: timeout) }

            guard let first = try await group.next() else {
                group.cancelAll()
                return -1
            }
            group.cancelAll()

            if let status = first {
                return status
            }

            // Timeout fired before the process exited.
            await terminateProcess(process)
            throw HookError.timedOut(after: timeout)
        }
    }

    /// Stops an uncooperative hook without allowing its output pipe to defeat
    /// the caller's timeout. SIGKILL is a final fallback after the same TERM
    /// and INT grace periods used by the previous cleanup path.
    private static func terminateProcess(_ process: HookProcess) async {
        // Each signal deliberately targets the process group even if the
        // direct shell already exited. A background child can ignore TERM;
        // conditioning escalation on the direct child's state would then
        // leak it past the hook's timeout.
        process.terminate()
        try? await Task.sleep(for: .seconds(1))
        process.interrupt()
        try? await Task.sleep(for: .milliseconds(100))
        process.kill()
        // Reap the direct child after SIGKILL. Bounded polling preserves
        // HookRunner's timeout contract while avoiding a zombie until the app
        // exits if a script ignored TERM and INT.
        for _ in 0 ..< 20 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Polls isRunning instead of registering a terminationHandler after
    /// process.run(). Foundation only invokes the handler on the
    /// running-to-exited transition, so a hook that exits in the window
    /// between process.run() returning and the handler being assigned
    /// would never fire it; the continuation would dangle and the
    /// timeout would race in as a false positive. Polling reads live
    /// state, so a process that already terminated returns its status
    /// on the first probe.
    private static func pollProcessExit(_ process: HookProcess) async throws -> Int32 {
        while process.isRunning {
            try await Task.sleep(for: .milliseconds(50))
        }
        return process.terminationStatus
    }

    /// Sleeps for the given duration then returns nil to signal "timeout
    /// won the race" inside the task group.
    private static func timeoutTick(seconds: Double) async throws -> Int32? {
        try await Task.sleep(for: .seconds(seconds))
        return nil
    }
}
