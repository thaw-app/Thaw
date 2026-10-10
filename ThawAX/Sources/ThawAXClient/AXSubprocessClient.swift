//
//  AXSubprocessClient.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawAXCore

public enum AXSubprocessError: Error, CustomStringConvertible {
    case helperUnavailable(String)
    case helperNotRunning
    case helperExited
    case unexpectedReply
    /// A newer request on a latest-wins lane replaced this one.
    case superseded

    public var description: String {
        switch self {
        case let .helperUnavailable(reason): "AX helper unavailable: \(reason)"
        case .helperNotRunning: "AX helper is not running"
        case .helperExited: "AX helper exited mid-request"
        case .unexpectedReply: "AX helper answered a different request"
        case .superseded: "AX helper request was superseded"
        }
    }
}

/// Talks to one AX helper process with any number of requests in flight.
///
/// Replies arrive out of order, one lane per kind of work, so a stuck walk
/// never delays a hit-test. A timeout fails one request; the process is
/// replaced only when it exits or keeps timing out.
public final class AXSubprocessClient: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Absolute URL of the helper executable.
        public var helperURL: URL
        /// Seconds a request waits for its reply unless it says otherwise.
        public var replyTimeoutSeconds: Double

        public init(helperURL: URL, replyTimeoutSeconds: Double = 10) {
            self.helperURL = helperURL
            self.replyTimeoutSeconds = replyTimeoutSeconds
        }
    }

    private struct Pending {
        let continuation: CheckedContinuation<AXHelperReply, Error>
        let timer: Task<Void, Never>?
    }

    /// Timeouts in a row after which the helper counts as wedged and is
    /// replaced. A single slow request is not reason enough to fail the rest.
    private static let wedgedAfterTimeouts = 3

    /// Consecutive replyless exits after which the helper is abandoned for the
    /// session, so a security agent killing it does not see hundreds of
    /// respawns. Callers fall back to in-process reads.
    private static let abandonAfterExits = 5

    private let configuration: Configuration

    // State below is guarded by lock.
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var generation: UInt64 = 0
    private var nextID: UInt64 = 0
    private var pending: [UInt64: Pending] = [:]
    /// Ids cancelled before their continuation was registered.
    private var cancelledEarly: Set<UInt64> = []
    private var consecutiveTimeouts = 0
    private var consecutiveExits = 0
    private var isAbandoned = false
    private var lastExit: String?
    /// The tail of the running helper's stderr. A helper that dies before it
    /// can reply, in dyld for instance, says why only there.
    private var helperStandardError = Data()
    private static let standardErrorTailLength = 2048

    /// Serializes frame writes; frames must not interleave on the pipe.
    private let writeLock = NSLock()

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// How the most recent helper ended, for the caller's log: its exit
    /// status or the signal that killed it, or that its reply could not be
    /// read. Nil until a helper has ended unexpectedly.
    public var lastExitDescription: String? {
        lock.withLock { lastExit }
    }

    /// Whether the client has stopped launching the helper for this session
    /// after it kept exiting. See abandonAfterExits.
    public var hasAbandonedHelper: Bool {
        lock.withLock { isAbandoned }
    }

    deinit {
        stop()
    }

    /// Enumerates through the helper, launching it if needed.
    public func enumerate(_ request: AXEnumerateRequest = AXEnumerateRequest()) async throws -> AXEnumerateReply {
        guard case let .enumerate(reply) = try await send(.enumerate(request)) else {
            throw AXSubprocessError.unexpectedReply
        }
        return reply
    }

    /// Sends request and waits for its reply, launching the helper if
    /// needed. A helper that exits mid-request is replaced and the request
    /// sent once more, except a press: it may already have happened.
    public func send(_ request: AXHelperRequest, timeoutSeconds: Double? = nil) async throws -> AXHelperReply {
        let timeout = timeoutSeconds ?? configuration.replyTimeoutSeconds
        do {
            return try await sendOnce(request, timeoutSeconds: timeout)
        } catch AXSubprocessError.helperExited where request.lane != .press {
            return try await sendOnce(request, timeoutSeconds: timeout)
        }
    }

    private func sendOnce(_ request: AXHelperRequest, timeoutSeconds: Double) async throws -> AXHelperReply {
        let id = lock.withLock {
            nextID &+= 1
            return nextID
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(id: id, request: request, timeoutSeconds: timeoutSeconds, continuation: continuation)
            }
        } onCancel: {
            self.finish(id, with: .failure(CancellationError()), cancelledEarlyIfAbsent: true)
        }
    }

    private func register(
        id: UInt64,
        request: AXHelperRequest,
        timeoutSeconds: Double,
        continuation: CheckedContinuation<AXHelperReply, Error>
    ) {
        let input: FileHandle
        do {
            input = try lock.withLock { () throws -> FileHandle in
                if cancelledEarly.remove(id) != nil {
                    throw CancellationError()
                }
                let input = try ensureStartedLocked()
                let timer = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(timeoutSeconds))
                    } catch {
                        return
                    }
                    self?.timedOut(id)
                }
                pending[id] = Pending(continuation: continuation, timer: timer)
                return input
            }
        } catch {
            continuation.resume(throwing: error)
            return
        }

        do {
            try writeLock.withLock {
                try AXWire.write(AXRequestFrame(id: id, request: request), to: input)
            }
        } catch {
            // The pipe is gone, so the helper is too. The reader sees the same
            // end of stream and fails everything else in flight.
            finish(id, with: .failure(AXSubprocessError.helperExited))
        }
    }

    // MARK: - Completion

    private func finish(
        _ id: UInt64,
        with result: Result<AXHelperReply, Error>,
        cancelledEarlyIfAbsent: Bool = false
    ) {
        let entry = lock.withLock { () -> Pending? in
            let entry = pending.removeValue(forKey: id)
            if entry == nil, cancelledEarlyIfAbsent {
                cancelledEarly.insert(id)
            }
            return entry
        }
        guard let entry else { return }
        entry.timer?.cancel()
        entry.continuation.resume(with: result)
    }

    private func timedOut(_ id: UInt64) {
        let isWedged = lock.withLock { () -> Bool in
            guard pending[id] != nil else { return false }
            consecutiveTimeouts += 1
            return consecutiveTimeouts >= Self.wedgedAfterTimeouts
        }
        finish(id, with: .failure(AXWire.WireError.timedOut))
        if isWedged {
            restart()
        }
    }

    /// Routes one reply frame to whoever is waiting for it.
    private func deliver(_ frame: AXReplyFrame) {
        lock.withLock {
            consecutiveTimeouts = 0
            consecutiveExits = 0
        }
        switch frame.outcome {
        case let .reply(reply):
            finish(frame.id, with: .success(reply))
        case .superseded:
            finish(frame.id, with: .failure(AXSubprocessError.superseded))
        }
    }

    // MARK: - Process lifecycle

    /// Stops the helper by closing its stdin; it exits on EOF. Every request in
    /// flight fails. Safe to call more than once.
    public func stop() {
        restart()
    }

    private func restart() {
        let failed = lock.withLock { () -> [Pending] in
            tearDownLocked()
            let failed = Array(pending.values)
            pending.removeAll()
            return failed
        }
        for entry in failed {
            entry.timer?.cancel()
            entry.continuation.resume(throwing: AXSubprocessError.helperExited)
        }
    }

    /// Whether a helper executable exists at the given location.
    public static func helperIsAvailable(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// The helper location inside a packaged app, or nil when it is absent.
    public static func embeddedHelperURL(in appBundle: Bundle = .main) -> URL? {
        let candidates = [
            appBundle.bundleURL.appendingPathComponent("Contents/Helpers/ThawAXHelper"),
            appBundle.bundleURL.appendingPathComponent("Contents/MacOS/ThawAXHelper"),
        ]
        return candidates.first { helperIsAvailable(at: $0) }
    }

    /// Returns the running helper's input, launching it if needed. Call with
    /// lock held.
    private func ensureStartedLocked() throws -> FileHandle {
        if let process, process.isRunning, let input {
            return input
        }
        tearDownLocked()

        guard !isAbandoned else {
            throw AXSubprocessError.helperUnavailable("stopped after \(Self.abandonAfterExits) exits in a row")
        }

        guard Self.helperIsAvailable(at: configuration.helperURL) else {
            throw AXSubprocessError.helperUnavailable(configuration.helperURL.path)
        }

        let process = Process()
        process.executableURL = configuration.helperURL
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        // Called with lock held.
        helperStandardError.removeAll()
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            FileHandle.standardError.write(data)
            guard let self else { return }
            self.lock.withLock {
                self.helperStandardError.append(data)
                if self.helperStandardError.count > Self.standardErrorTailLength {
                    self.helperStandardError.removeFirst(self.helperStandardError.count - Self.standardErrorTailLength)
                }
            }
        }

        do {
            try process.run()
        } catch {
            throw AXSubprocessError.helperUnavailable(String(describing: error))
        }

        // A helper that dies between requests closes the pipe under the next
        // write; without this that write raises SIGPIPE and kills Thaw instead
        // of throwing, so the request never gets to fail over.
        _ = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        generation &+= 1
        let readerGeneration = generation
        let output = outputPipe.fileHandleForReading
        let reader = Thread { [weak self] in
            self?.readReplies(from: output, process: process, generation: readerGeneration)
        }
        reader.name = "ThawAXClient.reader"
        reader.qualityOfService = .userInteractive
        reader.start()

        self.process = process
        input = inputPipe.fileHandleForWriting
        return inputPipe.fileHandleForWriting
    }

    /// Reads reply frames until the helper's output ends, then fails whatever
    /// was still waiting on that process.
    private func readReplies(from output: FileHandle, process: Process, generation readerGeneration: UInt64) {
        var unreadableReply: Error?
        // A plain thread never drains autorelease pools, so each read gets
        // its own, or every frame's buffers live forever.
        while autoreleasepool(invoking: {
            let frame: AXReplyFrame?
            do {
                frame = try AXWire.read(AXReplyFrame.self, from: output)
            } catch {
                unreadableReply = error
                frame = nil
            }
            guard let frame else { return false }
            deliver(frame)
            return true
        }) {}
        try? output.close()
        // Only the process this reader served may take the state down; a
        // restart may already have launched its replacement.
        let isCurrent = lock.withLock { generation == readerGeneration }
        if isCurrent {
            noteUnexpectedEnd(of: process, unreadableReply: unreadableReply)
            restart()
        }
    }

    /// Records how a helper that was still meant to be serving ended, and
    /// gives up on it after too many in a row.
    private func noteUnexpectedEnd(of process: Process, unreadableReply: Error?) {
        // The pipe closes a moment before the process is reaped; wait briefly
        // so the status is the real one rather than "still running".
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < deadline {
            usleep(10000)
        }
        let reason = if let unreadableReply {
            "unreadable reply: \(unreadableReply)"
        } else if process.isRunning {
            "closed its output but kept running"
        } else if process.terminationReason == .uncaughtSignal {
            "killed by signal \(process.terminationStatus)"
        } else {
            "exited with status \(process.terminationStatus)"
        }
        lock.withLock {
            let tail = String(decoding: helperStandardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " | ")
            let description = tail.isEmpty ? reason : "\(reason); stderr: \(tail)"
            lastExit = description
            consecutiveExits += 1
            if consecutiveExits >= Self.abandonAfterExits {
                isAbandoned = true
            }
        }
    }

    /// Call with lock held.
    private func tearDownLocked() {
        try? input?.close()
        input = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        generation &+= 1
    }
}
