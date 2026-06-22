//
//  DiagnosticLogger.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import OSLog

/// A centralized diagnostic logger that writes log messages to a file on disk
/// when diagnostic logging is enabled. This allows users to capture detailed
/// debug logs for troubleshooting without requiring a debug build.
///
/// Log files are written to `~/Library/Logs/Thaw/`.
final class DiagnosticLogger: @unchecked Sendable {
    /// The shared diagnostic logger instance.
    static let shared = DiagnosticLogger()

    /// Whether diagnostic logging to file is currently enabled.
    /// Thread-safe via OSAllocatedUnfairLock.
    private let isEnabledLock = OSAllocatedUnfairLock(initialState: false)

    var isEnabled: Bool {
        get { isEnabledLock.withLock { $0 } }
        set {
            let wasEnabled = isEnabledLock.withLock { $0 }
            guard newValue != wasEnabled else { return }
            if newValue {
                // `openLogFile()` flips `isEnabled` to true only after the file
                // handle is installed, so a concurrent `log()` never sees
                // enabled with no handle.
                openLogFile()
            } else {
                // Stop new writes before closing so no line lands after the footer.
                isEnabledLock.withLock { $0 = false }
                closeLogFile()
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

    /// The file handle for writing.
    private let fileHandleLock = OSAllocatedUnfairLock<FileHandle?>(initialState: nil)

    /// Internal logger for DiagnosticLogger's own messages.
    private let osLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw",
        category: "DiagnosticLogger"
    )

    /// Date formatter for log timestamps.
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Date formatter for log file names.
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

    /// The rotation policy. Tunable at runtime from the main app's settings;
    /// the XPC service leaves the defaults and never rotates.
    struct RotationPolicy {
        /// Rotate when the file reaches this size. `0` disables size rotation.
        var maxFileSizeBytes: UInt64 = 0
        /// Rotate after this many seconds. `0` disables time rotation.
        var rotationInterval: TimeInterval = 0
        /// Delete log files older than this many days.
        var retentionDays: Int = 2
        /// Never retain more than this many log files (belt-and-suspenders cap
        /// so a small size limit cannot pile up hundreds of files in a day).
        var maxFileCount: Int = 50
    }

    private let policyLock = OSAllocatedUnfairLock(initialState: RotationPolicy())

    /// The current rotation policy.
    var rotationPolicy: RotationPolicy {
        policyLock.withLock { $0 }
    }

    /// Updates the rotation policy and reschedules the maintenance timer.
    /// Only meaningful in the rotation owner (the main app).
    func setRotationPolicy(_ policy: RotationPolicy) {
        policyLock.withLock { $0 = policy }
        writeQueue.async { [weak self] in
            self?.rescheduleMaintenanceTimer()
        }
    }

    /// Whether this process owns rotation. Only the main app (which mints the
    /// file via `openLogFile()`) rotates; the XPC service merely re-attaches.
    private let isRotationOwnerLock = OSAllocatedUnfairLock(initialState: false)

    /// Called after the owner rotates to a new file, with the new URL, so the
    /// main app can hand the new path to the XPC service. Set on `Shared` to
    /// avoid a dependency on the app-only XPC connection type.
    private let onRotateLock = OSAllocatedUnfairLock<(@Sendable (URL) -> Void)?>(initialState: nil)

    var onRotate: (@Sendable (URL) -> Void)? {
        get { onRotateLock.withLock { $0 } }
        set { onRotateLock.withLock { $0 = newValue } }
    }

    /// Repeating timer that polls file size and elapsed time. `writeQueue` only.
    private var maintenanceTimer: DispatchSourceTimer?

    /// When the current segment was opened. `writeQueue` only.
    private var segmentOpenedAt = Date.distantPast

    /// Bytes written by this process since the last `fstat` size check, used to
    /// throttle `fstat` on the hot write path. `writeQueue` only.
    private var bytesSinceSizeCheck = 0

    private init() {
        // Intentionally empty: `DiagnosticLogger` is a singleton, and log file setup is deferred until logging is enabled.
    }

    // MARK: - File Management

    /// Enables diagnostic logging using an explicit log file URL chosen
    /// by another process. The MenuBarItemService XPC service calls this
    /// after the main app sends its log file path over the XPC channel,
    /// so both processes append to the same file instead of each
    /// minting its own filename from its own wall clock (which can
    /// straddle a one-second boundary at startup and produce two
    /// separate files). Safe to call repeatedly; the existing handle
    /// is closed before the new one is opened.
    func attachToFile(at fileURL: URL) {
        // The XPC service attaches but never owns rotation.
        isRotationOwnerLock.withLock { $0 = false }
        // Serialize against queued writes so in-flight log lines never straddle
        // the descriptor swap. `openLogFileLocked` opens the new file before
        // closing the old one, so a failed open keeps the previous segment.
        writeQueue.sync {
            // Idempotent: a duplicate push of the path we are already writing to
            // (e.g. a retried configureLogging) must not re-header and footer the
            // same file. Only re-open when the target actually changed.
            let alreadyAttached = currentLogFileLock.withLock { $0 == fileURL }
                && fileHandleLock.withLock { $0 != nil }
            guard !alreadyAttached else { return }
            openLogFileLocked(at: fileURL)
        }
    }

    /// Creates the log directory if needed and opens a freshly minted
    /// log file. Called by the main app when diagnostic logging is
    /// turned on; the chosen URL is then shared with the XPC service
    /// via attachToFile(at:).
    private func openLogFile() {
        // The main app mints the file and therefore owns rotation.
        isRotationOwnerLock.withLock { $0 = true }
        writeQueue.sync {
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
            openLogFileLocked(at: fileURL)
        }
    }

    /// Opens the given file and installs it as the current log file. Shared by
    /// the main app's fresh-mint path and the XPC service's attach path. Opens
    /// the new file before closing any previous one, so a failed open keeps the
    /// existing segment. Must run on `writeQueue`.
    private func openLogFileLocked(at fileURL: URL) {
        guard installLogFileLocked(at: fileURL, footerForOld: "Diagnostic logging stopped") else {
            // Open failed: keep logging to the previous segment if there was
            // one; otherwise there is nothing to log to, so disable.
            if currentLogFileLock.withLock({ $0 == nil }) {
                isEnabledLock.withLock { $0 = false }
            }
            return
        }

        // Publish enabled only after the handle is installed.
        isEnabledLock.withLock { $0 = true }
        osLog.info("Diagnostic logging started: \(fileURL.path, privacy: .public)")

        rescheduleMaintenanceTimer()
        // Retention is owned by the rotation owner (the main app); the XPC
        // service must not delete files against the app's policy.
        if isRotationOwnerLock.withLock({ $0 }) {
            cleanupOldLogFilesLocked(in: fileURL.deletingLastPathComponent(), protecting: [fileURL])
        }
    }

    /// Opens `fileURL`, writes its header, then atomically swaps it in as the
    /// current handle and footers + closes any previous one. Returns `false`
    /// without disturbing the current handle when the open fails. Must run on
    /// `writeQueue`.
    private func installLogFileLocked(at fileURL: URL, footerForOld: String) -> Bool {
        guard let newHandle = openHandle(at: fileURL) else {
            osLog.error("Failed to open log file at \(fileURL.path, privacy: .public)")
            return false
        }
        writeHeader(to: newHandle)

        let oldHandle = fileHandleLock.withLock { handle -> FileHandle? in
            let old = handle
            handle = newHandle
            return old
        }
        currentLogFileLock.withLock { $0 = fileURL }
        bytesSinceSizeCheck = 0
        segmentOpenedAt = Date()

        if let oldHandle {
            let ts = timestampFormatter.string(from: Date())
            let footer = "\n\(ts) [DiagnosticLogger] \(footerForOld)\n"
            if let data = footer.data(using: .utf8) {
                oldHandle.write(data)
            }
            try? oldHandle.close()
        }
        return true
    }

    /// Opens `fileURL` for appending and returns a handle, or `nil` on failure.
    private func openHandle(at fileURL: URL) -> FileHandle? {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            osLog.error("Failed to create log directory at \(dir.path): \(error)")
            return nil
        }

        // Open with O_APPEND so the main app and the XPC service can
        // safely write to the same file. FileManager.createFile and
        // FileHandle(forWritingTo:) would truncate an existing file
        // and the two processes' per-fd offsets would race against
        // each other on the same byte range. POSIX open(2) with
        // O_APPEND tells the kernel to atomically position each write
        // at end-of-file, which is atomic between processes for writes
        // smaller than PIPE_BUF on local filesystems; O_CREAT creates
        // the file if absent without touching an existing one. Swift's
        // FileHandle initializers do not expose these flags, hence the
        // POSIX call. O_NOFOLLOW refuses to open through a symlink at the
        // final path component, and 0o600 keeps logs (which carry window
        // titles and process data) readable only by the user.
        let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            osLog.error("Failed to open log file at \(fileURL.path): errno \(errno)")
            return nil
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Writes the per-process header into the given handle. Must run on
    /// `writeQueue` (uses the non-thread-safe timestamp formatter).
    private func writeHeader(to handle: FileHandle) {
        // Each process writes its own header into the shared file.
        // The Process line distinguishes them; chronological order
        // is preserved by the per-line timestamps.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        // GitCommitSHA is stamped into Info.plist when run as a
        // build phase. Defaults to "unknown" when the phase has
        // not been wired up, which is the only signal users need
        // to tell whether a given binary carries the expected
        // commit. Format is the short SHA (git rev-parse --short HEAD)
        // with a "-dirty" suffix when the working tree was not clean
        // at build time.
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

    /// Closes the current log file. Must run on `writeQueue`.
    private func closeLogFileLocked() {
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

    /// Closes the current log file, serializing against queued writes.
    private func closeLogFile() {
        writeQueue.sync { closeLogFileLocked() }
    }

    // MARK: - Rotation

    /// Rotates to a fresh log file, opening the new one before closing the old
    /// so a failed open leaves the current segment intact. Owner-only; must run
    /// on `writeQueue`.
    private func rotateLogFile() {
        guard isRotationOwnerLock.withLock({ $0 }) else { return }
        guard let previous = currentLogFileLock.withLock({ $0 }) else { return }
        let dir = previous.deletingLastPathComponent()

        let baseName = "thaw_\(fileNameFormatter.string(from: Date()))"
        let newURL = Self.uniqueLogFileURL(in: dir, baseName: baseName) {
            FileManager.default.fileExists(atPath: $0.path)
        }

        guard installLogFileLocked(at: newURL, footerForOld: "Rotated to \(newURL.lastPathComponent)") else {
            osLog.error("Rotation failed to open \(newURL.path, privacy: .public); staying on current segment")
            return
        }

        osLog.info("Rotated diagnostic log to \(newURL.path, privacy: .public)")

        // Hand the new path to the XPC service off-queue so the async send
        // never blocks file I/O.
        if let onRotate = onRotateLock.withLock({ $0 }) {
            DispatchQueue.global(qos: .utility).async { onRotate(newURL) }
        }

        // Retention: never delete the new file nor the previous segment — the
        // XPC service may still hold the previous descriptor until it
        // re-attaches.
        cleanupOldLogFilesLocked(in: dir, protecting: [newURL, previous])
    }

    /// (Re)creates the maintenance timer that polls file size and elapsed time.
    /// Owner-only; must run on `writeQueue`.
    private func rescheduleMaintenanceTimer() {
        maintenanceTimer?.cancel()
        maintenanceTimer = nil

        guard isEnabled, isRotationOwnerLock.withLock({ $0 }) else { return }
        let policy = policyLock.withLock { $0 }
        guard policy.maxFileSizeBytes > 0 || policy.rotationInterval > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: writeQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.maintenanceTick()
        }
        maintenanceTimer = timer
        timer.resume()
    }

    /// Periodic owner-side check. Catches growth driven only by the XPC service
    /// (which the hot write path would miss) and time-based rotation. Must run
    /// on `writeQueue`.
    private func maintenanceTick() {
        let policy = policyLock.withLock { $0 }

        if policy.maxFileSizeBytes > 0, let size = currentFileSizeLocked(), size >= policy.maxFileSizeBytes {
            rotateLogFile()
            return
        }
        if policy.rotationInterval > 0, Date().timeIntervalSince(segmentOpenedAt) >= policy.rotationInterval {
            rotateLogFile()
        }
    }

    /// Returns the current log file's on-disk size via `fstat`, or `nil`. Must
    /// run on `writeQueue`.
    private func currentFileSizeLocked() -> UInt64? {
        fileHandleLock.withLock { handle -> UInt64? in
            guard let fd = handle?.fileDescriptor else { return nil }
            var info = stat()
            guard fstat(fd, &info) == 0 else { return nil }
            return UInt64(info.st_size)
        }
    }

    /// Removes log files per the retention policy, never touching `protected`.
    /// Must run on `writeQueue`.
    private func cleanupOldLogFilesLocked(in directory: URL, protecting protected: [URL]) {
        let policy = policyLock.withLock { $0 }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            let files = contents
                .filter { $0.pathExtension == "log" }
                .map { url -> (url: URL, created: Date) in
                    let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    return (url, created)
                }
            let toPrune = Self.filesToPrune(
                files,
                retentionDays: policy.retentionDays,
                maxCount: policy.maxFileCount,
                now: Date(),
                protected: Set(protected)
            )
            for file in toPrune {
                try? FileManager.default.removeItem(at: file)
                osLog.debug("Removed old log file: \(file.lastPathComponent, privacy: .public)")
            }
        } catch {
            osLog.warning("Failed to clean up old log files: \(error)")
        }
    }

    // MARK: - Logging

    /// Log levels matching OSLog conventions.
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Writes a log message to the diagnostic log file.
    ///
    /// This is a no-op when diagnostic logging is disabled.
    ///
    /// - Parameters:
    ///   - level: The severity level.
    ///   - category: The logger category (e.g. "MenuBarItemManager").
    ///   - message: The log message.
    func log(level: Level, category: String, message: String) {
        guard isEnabled else { return }

        // Capture the wall clock here (thread-safe); format on writeQueue,
        // since DateFormatter is not thread-safe.
        let now = Date()

        writeQueue.async { [weak self] in
            guard let self else { return }
            let timestamp = timestampFormatter.string(from: now)
            let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            fileHandleLock.withLock { $0?.write(data) }
            afterWriteLocked(byteCount: data.count)
        }
    }

    /// Hot-path size check. Throttles `fstat` via a byte accumulator and
    /// rotates when the owner's file exceeds the size limit. Must run on
    /// `writeQueue`.
    private func afterWriteLocked(byteCount: Int) {
        guard isRotationOwnerLock.withLock({ $0 }) else { return }
        let maxSize = policyLock.withLock { $0.maxFileSizeBytes }
        guard maxSize > 0 else { return }

        bytesSinceSizeCheck += byteCount
        guard bytesSinceSizeCheck >= 64 * 1024 else { return }
        bytesSinceSizeCheck = 0

        if let size = currentFileSizeLocked(), size >= maxSize {
            rotateLogFile()
        }
    }
}

// MARK: - Rotation Helpers

extension DiagnosticLogger {
    /// Decides which log files to delete, applying age- and count-based
    /// retention while never touching protected files (the current and the
    /// just-rotated segment, whose descriptors may still be held open).
    ///
    /// A file is pruned when it is older than `retentionDays`, or when keeping
    /// it would exceed `maxCount` total retained files (the oldest beyond the
    /// cap go first). Protected files are always retained and count toward the
    /// cap.
    static func filesToPrune(
        _ files: [(url: URL, created: Date)],
        retentionDays: Int,
        maxCount: Int,
        now: Date,
        protected: Set<URL>
    ) -> [URL] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        let allowance = max(0, maxCount - protected.count)

        let candidates = files
            .filter { !protected.contains($0.url) }
            .sorted { $0.created > $1.created } // newest first

        var kept = 0
        var prune: [URL] = []
        for file in candidates {
            let tooOld = file.created < cutoff
            let overCap = kept >= allowance
            if tooOld || overCap {
                prune.append(file.url)
            } else {
                kept += 1
            }
        }
        return prune
    }

    /// Returns a collision-free log file URL in `directory` for `baseName`
    /// (without extension). Falls back to `_2`, `_3`, … suffixes when a file
    /// already exists, since the second-granularity timestamp in the name can
    /// collide when rotation happens within the same second it started.
    static func uniqueLogFileURL(
        in directory: URL,
        baseName: String,
        exists: (URL) -> Bool
    ) -> URL {
        let base = directory.appendingPathComponent("\(baseName).log")
        if !exists(base) {
            return base
        }
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
struct DiagLog {
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
