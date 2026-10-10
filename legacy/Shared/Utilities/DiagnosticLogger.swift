//
//  DiagnosticLogger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import OSLog

/// Writes log messages to a file when diagnostic logging is enabled, so users
/// can capture debug logs without a debug build.
///
/// Log files are written to `~/Library/Logs/Thaw/`.
final nonisolated class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    /// Whether diagnostic logging to file is currently enabled.
    /// Thread-safe via OSAllocatedUnfairLock.
    private let isEnabledLock = OSAllocatedUnfairLock(initialState: false)

    var isEnabled: Bool {
        get { isEnabledLock.withLock { $0 } }
        set {
            // Runs on `writeQueue`, ordered against queued writes: swapping the
            // handle off-queue could drop an accepted message or send it to the
            // wrong file. Concurrent toggles can't interleave; the last one wins.
            writeQueue.sync {
                let wasEnabled = isEnabledLock.withLock { $0 }
                guard newValue != wasEnabled else { return }
                if newValue {
                    openLogFile()
                } else {
                    // Stop accepting writes before the footer is written, so no
                    // line can land after it.
                    isEnabledLock.withLock { $0 = false }
                    closeLogFile()
                }
            }
        }
    }

    /// The directory where log files are stored.
    var logDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Thaw", isDirectory: true)
    }

    /// Returns whether any log files exist in the log directory.
    var hasLogFiles: Bool {
        latestLogFile != nil
    }

    /// Returns the most recent log file in the log directory, if any.
    var latestLogFile: URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }
        return contents
            .filter { $0.pathExtension == "log" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return dateA > dateB
            }
            .first
    }

    /// The current log file URL, if logging is active.
    private let currentLogFileLock = OSAllocatedUnfairLock<URL?>(initialState: nil)

    var currentLogFile: URL? {
        currentLogFileLock.withLock { $0 }
    }

    /// A bounded text view of the newest bytes in one diagnostic log file.
    struct TailSnapshot: Equatable {
        /// The log file that was read.
        let fileURL: URL

        /// UTF-8 decoded text from the bounded tail window.
        let text: String
    }

    private let fileHandleLock = OSAllocatedUnfairLock<FileHandle?>(initialState: nil)

    /// Internal logger for DiagnosticLogger's own messages.
    private let osLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw",
        category: "DiagnosticLogger"
    )

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Serial queue for file I/O.
    private let writeQueue = DispatchQueue(
        label: "com.stonerl.Thaw.DiagnosticLogger.writeQueue",
        qos: .utility
    )

    // MARK: - Rotation State

    /// How the log file is rotated and how long old files are kept.
    ///
    /// Set by the app and sent to the XPC targets with the log path, so both
    /// prune by the same rules. Only the process that mints a file rotates it.
    struct RotationPolicy: Codable, Equatable, Sendable {
        /// Rotate once the file reaches this size. `0` disables size rotation.
        var maxFileSizeBytes: UInt64 = 0
        /// Rotate this many seconds after the segment was opened. `0` disables
        /// time rotation.
        var rotationInterval: TimeInterval = 0
        /// Delete log files older than this many days.
        var retentionDays: Int = 2
        /// Never keep more than this many log files, so a small size limit
        /// cannot pile up hundreds of segments inside the retention window.
        var maxFileCount: Int = 50

        /// The widest values any of these settings may take.
        ///
        /// Far above anything the settings UI offers; they only stop external
        /// values from overflowing the arithmetic.
        static let maxRetentionDays = 3650
        static let maxRetainedFileCount = 10000
        static let maxRotationInterval: TimeInterval = 365 * 86400
        static let maxSizeBytes: UInt64 = 1 << 40 // 1 TiB

        /// Returns the policy with every field forced into a usable range.
        ///
        /// A policy can arrive over XPC, and ad-hoc builds have no peer
        /// requirement. Unchecked, a negative retention or zero count deletes
        /// every log, `Int.min` traps, and a non-finite interval breaks the timer.
        func sanitized() -> RotationPolicy {
            var policy = self
            policy.retentionDays = min(max(1, retentionDays), Self.maxRetentionDays)
            policy.maxFileCount = min(max(1, maxFileCount), Self.maxRetainedFileCount)
            policy.maxFileSizeBytes = min(maxFileSizeBytes, Self.maxSizeBytes)
            policy.rotationInterval = rotationInterval.isFinite
                ? min(max(0, rotationInterval), Self.maxRotationInterval)
                : 0
            return policy
        }
    }

    private let policyLock = OSAllocatedUnfairLock(initialState: RotationPolicy())

    /// The current rotation policy.
    var rotationPolicy: RotationPolicy {
        policyLock.withLock { $0 }
    }

    /// Updates the rotation policy and reschedules the maintenance timer.
    ///
    /// Sanitized here because one caller is an untrusted XPC peer.
    func setRotationPolicy(_ policy: RotationPolicy) {
        policyLock.withLock { $0 = policy.sanitized() }
        writeQueue.async { [weak self] in
            self?.rescheduleMaintenanceTimer()
        }
    }

    /// Whether this process owns rotation and pruning. True only in the process
    /// that minted the file via `openLogFile()`; the XPC target attaches to a
    /// path handed to it and merely follows.
    private let isRotationOwnerLock = OSAllocatedUnfairLock(initialState: false)

    /// Called after the owner rotates, so the app can repoint the XPC service.
    /// A closure because `Shared` can't reach the app-only connection. Takes no
    /// argument: reading ``currentLogFile`` at send time avoids pushing a stale path.
    private let onRotateLock = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    var onRotate: (@Sendable () -> Void)? {
        get { onRotateLock.withLock { $0 } }
        set { onRotateLock.withLock { $0 = newValue } }
    }

    /// Timer that polls file size and elapsed time. `writeQueue` only.
    private var maintenanceTimer: DispatchSourceTimer?

    /// When the current segment was opened, on a clock that does not move when
    /// the user or the network changes the system time. `writeQueue` only.
    private var segmentOpenedAt = ContinuousClock.now

    /// Bytes this process has written since the last size check, used to
    /// throttle `fstat` on the hot write path. `writeQueue` only.
    private var bytesSinceSizeCheck = 0

    private init() {
        // Intentionally empty: `DiagnosticLogger` is a singleton, and log file setup is deferred until logging is enabled.
    }

    // MARK: - File Management

    /// Enables diagnostic logging to a file chosen by another process. The XPC
    /// services call this with the app's path so both append to one file.
    /// Safe to call repeatedly.
    ///
    /// - Returns: Whether this process is now writing to `fileURL`. On `false`
    ///   the previous segment is still in use, and the caller must report it.
    @discardableResult
    func attachToFile(at fileURL: URL) -> Bool {
        // Attaching follows a path chosen elsewhere, so this process never owns
        // rotation or pruning.
        isRotationOwnerLock.withLock { $0 = false }
        // Swap on the write queue (see `isEnabled`). A failed open keeps the
        // current segment.
        return writeQueue.sync {
            // The same path can arrive twice; re-opening would write a spurious
            // header and footer into the live file.
            let alreadyAttached = currentLogFileLock.withLock { $0 == fileURL }
                && fileHandleLock.withLock { $0 != nil }
            guard !alreadyAttached else { return true }
            return openLogFile(at: fileURL)
        }
    }

    /// Opens a freshly minted log file. The app calls this when logging is
    /// turned on, then shares the URL via attachToFile(at:).
    private func openLogFile() {
        // The process that mints the file owns rotation and pruning.
        isRotationOwnerLock.withLock { $0 = true }

        let dir = logDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            osLog.error("Failed to create log directory at \(dir.path): \(error)")
            isEnabledLock.withLock { $0 = false }
            return
        }

        let baseName = "thaw_\(fileNameFormatter.string(from: Date()))"
        let fileURL = Self.uniqueLogFileURL(in: dir, baseName: baseName) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        openLogFile(at: fileURL)
    }

    /// Opens the given file, writes the per-process header, and installs it as
    /// the current log file. Shared by minting, attaching, and rotation.
    ///
    /// - Returns: Whether `fileURL` is now the file being written to.
    @discardableResult
    private func openLogFile(at fileURL: URL) -> Bool {
        guard installLogFile(at: fileURL, footerForPrevious: "Diagnostic logging stopped") else {
            // Nothing was disturbed: keep writing to the previous segment when
            // there is one, and only give up when there is not.
            if currentLogFileLock.withLock({ $0 == nil }) {
                isEnabledLock.withLock { $0 = false }
            }
            return false
        }

        // Published last: an accepted message must never find logging enabled
        // before there is a file to write it to.
        isEnabledLock.withLock { $0 = true }
        osLog.info("Diagnostic logging started: \(fileURL.path, privacy: .public)")

        rescheduleMaintenanceTimer()
        // Queued: enabling logging waits on this queue from the main actor.
        let directory = fileURL.deletingLastPathComponent()
        writeQueue.async { [weak self] in
            self?.cleanupOldLogFiles(in: directory, protecting: [fileURL])
        }
        return true
    }

    /// Opens `fileURL`, writes its header, then swaps it in as the current
    /// handle and closes the previous one with `footerForPrevious`.
    ///
    /// A failed open leaves the current segment untouched and returns `false`.
    private func installLogFile(at fileURL: URL, footerForPrevious: String) -> Bool {
        guard let newHandle = openHandle(at: fileURL) else {
            return false
        }
        writeHeader(to: newHandle)

        let previousHandle = fileHandleLock.withLock { handle -> FileHandle? in
            let previous = handle
            handle = newHandle
            return previous
        }
        currentLogFileLock.withLock { $0 = fileURL }
        bytesSinceSizeCheck = 0
        segmentOpenedAt = ContinuousClock.now

        if let previousHandle {
            let ts = timestampFormatter.string(from: Date())
            let footer = "\n\(ts) [DiagnosticLogger] \(footerForPrevious)\n"
            if let data = footer.data(using: .utf8) {
                previousHandle.write(data)
            }
            try? previousHandle.close()
        }
        return true
    }

    /// Opens `fileURL` for appending, creating its directory if needed.
    /// Returns `nil` when the directory or the file cannot be opened.
    private func openHandle(at fileURL: URL) -> FileHandle? {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            osLog.error("Failed to create log directory at \(dir.path): \(error)")
            return nil
        }

        // POSIX open(2) because FileHandle can't set these flags. O_APPEND makes
        // cross-process writes land atomically at EOF (below PIPE_BUF), where
        // FileHandle would truncate and race offsets. O_NOFOLLOW refuses a final
        // symlink, and 0o600 keeps window titles and process names private.
        let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            osLog.error("Failed to open log file at \(fileURL.path): errno \(errno)")
            return nil
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Writes the per-process header into the given handle. `writeQueue` only:
    /// `timestampFormatter` is not thread-safe.
    private func writeHeader(to handle: FileHandle) {
        // Each process writes its own header into the shared file.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        // GitCommitSHA is stamped into Info.plist by a build phase: short SHA,
        // "-dirty" if the tree was unclean, "unknown" if the phase didn't run.
        let sha = Bundle.main.infoDictionary?["GitCommitSHA"] as? String ?? "unknown"
        let header = """
        ========================================
        Thaw Diagnostic Log
        Started: \(timestampFormatter.string(from: Date()))
        Process: \(ProcessInfo.processInfo.processName)
        Version: \(version) (\(build)) commit \(sha)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ========================================\n\n
        """
        if let data = header.data(using: .utf8) {
            handle.write(data)
        }
    }

    /// Closes the current log file.
    private func closeLogFile() {
        maintenanceTimer?.cancel()
        maintenanceTimer = nil
        fileHandleLock.withLock { handle in
            if let handle {
                let ts = timestampFormatter.string(from: Date())
                let footer = "\n\(ts) [DiagnosticLogger] Diagnostic logging stopped\n"
                if let data = footer.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
            handle = nil
        }
        currentLogFileLock.withLock { $0 = nil }
        osLog.info("Diagnostic logging stopped")
    }

    // MARK: - Rotation

    /// Rotates to a freshly minted log file.
    ///
    /// Owner-only, `writeQueue` only. The new file is opened before the old one
    /// is closed, so a failed open leaves the current segment in place.
    private func rotateLogFile() {
        guard isRotationOwnerLock.withLock({ $0 }) else { return }
        guard let previous = currentLogFileLock.withLock({ $0 }) else { return }
        let dir = previous.deletingLastPathComponent()

        let baseName = "thaw_\(fileNameFormatter.string(from: Date()))"
        let newURL = Self.uniqueLogFileURL(in: dir, baseName: baseName) {
            FileManager.default.fileExists(atPath: $0.path)
        }

        guard installLogFile(at: newURL, footerForPrevious: "Rotated to \(newURL.lastPathComponent)") else {
            osLog.error("Rotation failed to open \(newURL.path, privacy: .public); staying on the current segment")
            return
        }

        osLog.info("Rotated diagnostic log to \(newURL.path, privacy: .public)")

        // Tell the app to repoint the service. Called inline: the handler only
        // starts the round trip, and another queue hop could reorder notifications.
        onRotateLock.withLock { $0 }?()

        // The XPC target keeps writing to `previous` until it re-attaches, so
        // that segment stays even when the policy would otherwise prune it.
        writeQueue.async { [weak self] in
            self?.cleanupOldLogFiles(in: dir, protecting: [newURL, previous])
        }
    }

    /// Recreates the timer that polls file size and elapsed time.
    ///
    /// Owner-only, `writeQueue` only. Also covers growth driven solely by the
    /// XPC target, which the app's own write path would never notice.
    private func rescheduleMaintenanceTimer() {
        maintenanceTimer?.cancel()
        maintenanceTimer = nil

        guard isEnabled, isRotationOwnerLock.withLock({ $0 }) else { return }
        let policy = policyLock.withLock { $0 }
        guard policy.maxFileSizeBytes > 0 || policy.rotationInterval > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: writeQueue)
        timer.schedule(deadline: .now() + Self.maintenanceInterval, repeating: Self.maintenanceInterval)
        timer.setEventHandler { [weak self] in
            self?.maintenanceTick()
        }
        maintenanceTimer = timer
        timer.resume()
    }

    /// How often the maintenance timer checks size and elapsed time.
    private static let maintenanceInterval: TimeInterval = 5

    /// Rotates when the file has outgrown the size limit or the segment has
    /// outlived the interval. `writeQueue` only.
    private func maintenanceTick() {
        let policy = policyLock.withLock { $0 }

        if policy.maxFileSizeBytes > 0, let size = currentFileSize(), size >= policy.maxFileSizeBytes {
            rotateLogFile()
            return
        }
        if policy.rotationInterval > 0,
           segmentOpenedAt.duration(to: .now) >= .seconds(policy.rotationInterval)
        {
            rotateLogFile()
        }
    }

    /// The current log file's size on disk, or `nil` when there is no handle.
    ///
    /// Read through `fstat` rather than a per-process byte counter so that
    /// bytes written by the XPC target into the same file count too.
    private func currentFileSize() -> UInt64? {
        fileHandleLock.withLock { handle -> UInt64? in
            guard let fd = handle?.fileDescriptor else { return nil }
            var info = stat()
            guard fstat(fd, &info) == 0 else { return nil }
            return UInt64(info.st_size)
        }
    }

    /// Removes log files the retention policy no longer covers, never touching
    /// `protected`. `writeQueue` only.
    private func cleanupOldLogFiles(in directory: URL, protecting protected: [URL]) {
        let policy = policyLock.withLock { $0 }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            let logFiles = contents
                .filter { $0.pathExtension == "log" }
                .map { url -> (url: URL, created: Date) in
                    let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    return (url, created)
                }

            let staleFiles = Self.filesToPrune(
                logFiles,
                retentionDays: policy.retentionDays,
                maxCount: policy.maxFileCount,
                now: Date(),
                protected: Set(protected)
            )

            for file in staleFiles {
                // One stubborn file must not abort the rest of the prune.
                do {
                    try FileManager.default.removeItem(at: file)
                    osLog.debug("Removed old log file: \(file.lastPathComponent, privacy: .public)")
                } catch CocoaError.fileNoSuchFile {
                    // Another process may have pruned it first; that's expected.
                } catch {
                    osLog.warning(
                        "Failed to remove old log file \(file.lastPathComponent, privacy: .public): \(error)"
                    )
                }
            }
        } catch {
            osLog.warning("Failed to clean up old log files: \(error)")
        }
    }

    // MARK: - Snapshots

    /// Returns a bounded tail of the active or most recent diagnostic log.
    ///
    /// The read is submitted to ``writeQueue`` so every write already accepted
    /// by ``log(level:category:message:)`` is complete before the snapshot is
    /// taken. File lookup and I/O also stay off the caller's executor.
    func tailSnapshot(maxBytes: Int) async -> TailSnapshot? {
        guard maxBytes > 0 else { return nil }
        return await withCheckedContinuation { continuation in
            writeQueue.async { [weak self] in
                guard
                    let self,
                    let fileURL = self.currentLogFile ?? self.latestLogFile,
                    let text = try? Self.readTail(from: fileURL, maxBytes: maxBytes)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: TailSnapshot(fileURL: fileURL, text: text))
            }
        }
    }

    /// Reads no more than `maxBytes` from the end of `fileURL`.
    ///
    /// When the window begins inside a line, that incomplete line is dropped.
    /// `String(decoding:as:)` deliberately tolerates a trailing partial UTF-8
    /// scalar, which another process can expose while appending to the shared
    /// log file.
    static func readTail(from fileURL: URL, maxBytes: Int) throws -> String {
        guard maxBytes > 0 else { return "" }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let byteLimit = UInt64(maxBytes)
        let startOffset = fileSize > byteLimit ? fileSize - byteLimit : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.read(upToCount: maxBytes) ?? Data()

        let completeData: Data
        if startOffset > 0 {
            guard let newline = data.firstIndex(of: 0x0A) else { return "" }
            completeData = Data(data.suffix(from: data.index(after: newline)))
        } else {
            completeData = data
        }
        // Replacement characters keep partial cross-process writes readable.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: completeData, as: UTF8.self)
    }

    // MARK: - Logging

    /// Log levels matching OSLog conventions.
    enum Level: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Writes a log message to the diagnostic log file.
    ///
    /// This is a no-op when diagnostic logging is disabled.
    func log(level: Level, category: String, message: String) {
        guard isEnabled else { return }

        // Capture the time here, format on the queue: `DateFormatter` isn't thread-safe.
        let now = Date()

        writeQueue.async { [weak self] in
            guard let self else { return }
            let timestamp = timestampFormatter.string(from: now)
            let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            fileHandleLock.withLock { handle in
                handle?.write(data)
            }
            checkSizeAfterWrite(byteCount: data.count)
        }
    }

    /// Rotates when this process's own writes have pushed the file past the
    /// size limit. `writeQueue` only.
    ///
    /// The accumulator keeps `fstat` off the per-line path: it runs once per
    /// 64 KB written rather than once per message. Growth driven by the XPC
    /// target is caught by the maintenance timer instead.
    private func checkSizeAfterWrite(byteCount: Int) {
        guard isRotationOwnerLock.withLock({ $0 }) else { return }
        let maxFileSizeBytes = policyLock.withLock { $0.maxFileSizeBytes }
        guard maxFileSizeBytes > 0 else { return }

        bytesSinceSizeCheck += byteCount
        guard bytesSinceSizeCheck >= Self.sizeCheckByteInterval else { return }
        bytesSinceSizeCheck = 0

        if let size = currentFileSize(), size >= maxFileSizeBytes {
            rotateLogFile()
        }
    }

    /// How many bytes this process writes between `fstat` size checks.
    private static let sizeCheckByteInterval = 64 * 1024
}

// MARK: - Rotation Helpers

/// Explicitly nonisolated: these run on the logger's write queue, and the
/// target's default actor isolation is MainActor.
nonisolated extension DiagnosticLogger {
    /// Returns the log files that retention no longer covers.
    ///
    /// A file is pruned when older than `retentionDays` or when newer files fill
    /// `maxCount`; same-age ties go by path. `protected` files may still be open,
    /// so they are always kept and count against `maxCount`. Ordered newest first.
    static func filesToPrune(
        _ files: [(url: URL, created: Date)],
        retentionDays: Int,
        maxCount: Int,
        now: Date,
        protected: Set<URL>
    ) -> [URL] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        // A comparison, not a subtraction: an unsanitized `Int.min` would trap.
        let cap = max(0, maxCount)
        let allowance = cap > protected.count ? cap - protected.count : 0

        let candidates = files
            .filter { !protected.contains($0.url) }
            .sorted { lhs, rhs in
                lhs.created == rhs.created
                    ? lhs.url.path < rhs.url.path
                    : lhs.created > rhs.created // newest first
            }

        var kept = 0
        var stale: [URL] = []
        for file in candidates {
            if file.created < cutoff || kept >= allowance {
                stale.append(file.url)
            } else {
                kept += 1
            }
        }
        return stale
    }

    /// Returns a log file URL in `directory` for `baseName` that no file
    /// already occupies, appending `_2`, `_3`, … on collision.
    ///
    /// File name timestamps are second-granular, so two rotations in one second
    /// would otherwise reuse a name.
    static func uniqueLogFileURL(
        in directory: URL,
        baseName: String,
        exists: (URL) -> Bool
    ) -> URL {
        let base = directory.appendingPathComponent("\(baseName).log")
        guard exists(base) else { return base }

        var suffix = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName)_\(suffix).log")
            if !exists(candidate) {
                return candidate
            }
            suffix += 1
        }
    }
}

// MARK: - DiagLog

/// A lightweight diagnostic-aware logger that wraps `os.Logger` and
/// additionally writes to the diagnostic log file when enabled.
///
/// Create one per component:
/// ```
/// private let log = DiagLog(category: "MenuBarItemManager")
/// log.debug("something happened")
/// ```
nonisolated struct DiagLog {
    private let osLogger: Logger
    private let category: String

    init(category: String) {
        self.osLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw",
            category: category
        )
        self.category = category
    }

    func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.debug("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .debug, category: category, message: msg)
    }

    func info(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.info("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .info, category: category, message: msg)
    }

    func notice(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.notice("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .notice, category: category, message: msg)
    }

    func warning(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.warning("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .warning, category: category, message: msg)
    }

    func error(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.error("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .error, category: category, message: msg)
    }
}
