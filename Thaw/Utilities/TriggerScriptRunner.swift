//
//  TriggerScriptRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

private nonisolated final class ScriptOutputAccumulator: @unchecked Sendable {
    private static let maximumRetainedOutputBytes = 1_000_000
    private static let truncationNotice = "\n[Trigger script output truncated]\n"

    private let condition = NSCondition()
    private var data = Data()
    private var acceptsReads = true
    private var activeReads = 0
    private var outputWasTruncated = false
    private let expectedOutputs: Set<String>
    private let searchTailLength: Int
    private var searchTail = ""
    private var matchedExpectedOutputs = Set<String>()
    private var undecodedSearchBytes = Data()

    init(expectedOutputs: Set<String>) {
        self.expectedOutputs = expectedOutputs.filter { !$0.isEmpty }
        self.searchTailLength = self.expectedOutputs.map(\.count).max() ?? 0
    }

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

    func stopAcceptingReadsAndWait() {
        condition.lock()
        acceptsReads = false
        while activeReads > 0 {
            condition.wait()
        }
        condition.unlock()
    }

    func append(_ newData: Data) {
        condition.lock()
        defer { condition.unlock() }
        let remainingCapacity = Self.maximumRetainedOutputBytes - data.count
        if remainingCapacity > 0 {
            data.append(newData.prefix(remainingCapacity))
        }
        if newData.count > remainingCapacity {
            outputWasTruncated = true
        }

        guard !expectedOutputs.isEmpty else { return }
        let searchableText = searchTail + consumeSearchableText(from: newData)
        for expectedOutput in expectedOutputs
            where searchableText.localizedCaseInsensitiveContains(expectedOutput)
        {
            matchedExpectedOutputs.insert(expectedOutput)
        }
        searchTail = searchTailLength > 0
            ? String(searchableText.suffix(searchTailLength))
            : ""
    }

    var collectedData: Data {
        condition.lock()
        defer { condition.unlock() }
        var result = data
        if outputWasTruncated {
            result.append(Data(Self.truncationNotice.utf8))
        }
        return result
    }

    var streamedExpectedOutputs: Set<String> {
        condition.lock()
        defer { condition.unlock() }
        return matchedExpectedOutputs
    }

    /// Decodes arbitrary pipe chunks while retaining only a valid, incomplete
    /// UTF-8 suffix. This keeps Unicode matching independent of kernel read
    /// boundaries without allowing a malformed byte earlier in the chunk to
    /// block later valid text.
    private func consumeSearchableText(from newData: Data) -> String {
        undecodedSearchBytes.append(newData)
        let bytes = [UInt8](undecodedSearchBytes)
        let incompleteSuffixLength = Self.incompleteUTF8SuffixLength(in: bytes)
        undecodedSearchBytes = Data(bytes.suffix(incompleteSuffixLength))
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes.dropLast(incompleteSuffixLength), as: UTF8.self)
    }

    /// Returns the length of a trailing byte sequence that is a syntactically
    /// valid prefix of a multi-byte UTF-8 scalar, or zero when the tail is
    /// complete or malformed. At most three bytes can be incomplete.
    private static func incompleteUTF8SuffixLength(in bytes: [UInt8]) -> Int {
        for length in stride(from: min(3, bytes.count), through: 1, by: -1) {
            let suffix = bytes.suffix(length)
            guard let leadingByte = suffix.first else { continue }

            let expectedLength: Int
            switch leadingByte {
            case 0xC2 ... 0xDF: expectedLength = 2
            case 0xE0 ... 0xEF: expectedLength = 3
            case 0xF0 ... 0xF4: expectedLength = 4
            default: continue
            }

            guard length < expectedLength,
                  suffix.dropFirst().allSatisfy({ 0x80 ... 0xBF ~= $0 })
            else { continue }

            if let secondByte = suffix.dropFirst().first {
                switch leadingByte {
                case 0xE0 where secondByte < 0xA0,
                     0xED where secondByte > 0x9F,
                     0xF0 where secondByte < 0x90,
                     0xF4 where secondByte > 0x8F:
                    continue
                default:
                    break
                }
            }

            return length
        }

        return 0
    }
}

/// Runs a user-supplied script for a script-result trigger condition and
/// returns its exit code and combined output, with a wall-clock timeout.
///
/// AppleScript files (.scpt / .applescript / .scptd) are routed through
/// `osascript`; everything else is launched directly and must carry the
/// executable bit.
enum TriggerScriptRunner {
    private static let diagLog = DiagLog(category: "TriggerScriptRunner")

    private static let appleScriptExtensions: Set<String> = ["scpt", "applescript", "scptd"]

    /// Runs the script at `path`, returning its outcome, or `nil` on launch
    /// failure. Times out after `timeout` seconds (the process is terminated
    /// and a non-zero exit code is reported).
    static func run(
        path: String,
        timeout: Double = 10,
        expectedOutputs: Set<String> = []
    ) async -> ScriptOutcome? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else {
            return nil
        }

        let pipe = Pipe()

        let outputAccumulator = ScriptOutputAccumulator(expectedOutputs: expectedOutputs)
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            guard outputAccumulator.beginRead() else { return }
            defer { outputAccumulator.endRead() }
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            outputAccumulator.append(data)
        }

        let ext = (trimmed as NSString).pathExtension.lowercased()
        let executablePath: String
        let arguments: [String]
        if appleScriptExtensions.contains(ext) {
            executablePath = "/usr/bin/osascript"
            arguments = [trimmed]
        } else {
            executablePath = trimmed
            arguments = []
        }

        let process: HookRunner.HookProcess
        do {
            process = try HookRunner.HookProcess.launch(
                executablePath: executablePath,
                arguments: arguments,
                environment: ProcessInfo.processInfo.environment,
                combinedOutput: pipe
            )
            // The child inherited this descriptor. Closing our writer makes
            // EOF available after ordinary scripts exit, while detached-child
            // handling below never waits for that EOF.
            pipe.fileHandleForWriting.closeFile()
        } catch {
            outputHandle.readabilityHandler = nil
            outputAccumulator.stopAcceptingReadsAndWait()
            diagLog.warning("Failed to launch trigger script \(trimmed): \(error.localizedDescription)")
            return nil
        }

        // Race the process against the timeout.
        let timedOut = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                while process.isRunning {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return false }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if timedOut {
            process.terminate()
            diagLog.warning("Trigger script timed out after \(timeout)s: \(trimmed)")
            try? await Task.sleep(for: .milliseconds(500))
            // The direct shell may have exited from TERM while a background
            // descendant remains. Continue escalating the process group so
            // timeout means no script descendants survive.
            process.interrupt()
            try? await Task.sleep(for: .milliseconds(100))
            process.kill()
            // `kill` returns before the kernel tears the group down. Wait for
            // the group to drain so a returning timeout really does mean no
            // descendant outlived the script.
            //
            // `isRunning` is polled alongside the group check because it is
            // what reaps the direct child. Without it that child stays a
            // zombie -- still a group member -- and the loop would burn its
            // whole budget waiting for a process that has already exited.
            var groupDrainAttempts = 0
            var groupDrained = false
            while groupDrainAttempts < 40 {
                _ = process.isRunning
                if !process.hasLiveProcessGroup {
                    groupDrained = true
                    break
                }
                groupDrainAttempts += 1
                try? await Task.sleep(for: .milliseconds(25))
            }
            if groupDrained {
                diagLog.warning("Force-killed trigger script process group after timeout: \(trimmed)")
            } else {
                diagLog.error(
                    "Trigger script process group still alive after force-kill and drain budget: \(trimmed)"
                )
            }
        }

        while process.isRunning {
            try? await Task.sleep(for: .milliseconds(25))
        }
        outputHandle.readabilityHandler = nil
        outputAccumulator.stopAcceptingReadsAndWait()
        drainAvailableBytes(from: outputHandle, into: outputAccumulator)
        let data = outputAccumulator.collectedData
        // swiftlint:disable:next optional_data_string_conversion
        let output = String(decoding: [UInt8](data), as: UTF8.self)
        let exitCode = timedOut ? -1 : process.terminationStatus
        return ScriptOutcome(
            exitCode: exitCode,
            output: output,
            matchedExpectedOutputs: outputAccumulator.streamedExpectedOutputs
        )
    }

    /// Captures a final buffered tail without blocking on a background child
    /// that inherited the script pipe and intentionally remains alive.
    private static func drainAvailableBytes(from handle: FileHandle, into accumulator: ScriptOutputAccumulator) {
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
            guard bytesRead < 0, errno == EINTR else { return }
        }
    }
}
