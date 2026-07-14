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
            let oldValue = isEnabledLock.withLock { current -> Bool in
                let old = current
                current = newValue
                return old
            }
            if newValue, !oldValue {
                openLogFile()
            } else if !newValue, oldValue {
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

    /// Date formatter for log timestamps. DateFormatter is mutable, so every
    /// use is serialized: diagnostic messages can originate on any queue.
    private let timestampFormatter = OSAllocatedUnfairLock(initialState: {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }())

    /// Date formatter for log file names, likewise protected from concurrent
    /// enable/attach calls.
    private let fileNameFormatter = OSAllocatedUnfairLock(initialState: {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }())

    /// Serial queue for file I/O.
    private let writeQueue = DispatchQueue(
        label: "com.stonerl.Thaw.DiagnosticLogger.writeQueue",
        qos: .utility
    )

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
        let wasEnabled = isEnabledLock.withLock { current -> Bool in
            let was = current
            current = true
            return was
        }
        if wasEnabled {
            closeLogFile()
        }
        openLogFile(at: fileURL)
    }

    /// Creates the log directory if needed and opens a freshly minted
    /// log file. Called by the main app when diagnostic logging is
    /// turned on; the chosen URL is then shared with the XPC service
    /// via attachToFile(at:).
    private func openLogFile() {
        let dir = logDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            osLog.error("Failed to create log directory at \(dir.path): \(error)")
            isEnabledLock.withLock { $0 = false }
            return
        }

        let fileName = "thaw_\(fileNameString(from: Date())).log"
        openLogFile(at: dir.appendingPathComponent(fileName))
    }

    /// Opens the given file with O_APPEND and writes the per-process
    /// header. Shared by the main app's fresh-mint path and the XPC
    /// service's attach path so both processes use identical open and
    /// header logic.
    private func openLogFile(at fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            osLog.error("Failed to create log directory at \(dir.path): \(error)")
            isEnabledLock.withLock { $0 = false }
            return
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
        // POSIX call.
        let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else {
            osLog.error("Failed to open log file at \(fileURL.path): errno \(errno)")
            isEnabledLock.withLock { $0 = false }
            return
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fileHandleLock.withLock { $0 = handle }
        currentLogFileLock.withLock { $0 = fileURL }

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
        Started: \(timestampString(from: Date()))
        Process: \(ProcessInfo.processInfo.processName)
        Version: \(version) (\(build)) commit \(sha)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ========================================\n\n
        """
        if let data = header.data(using: .utf8) {
            handle.write(data)
        }

        osLog.info("Diagnostic logging started: \(fileURL.path, privacy: .public)")

        // Clean up old log files (keep last 5)
        cleanupOldLogFiles(in: dir, keepCount: 5)
    }

    /// Closes the current log file.
    private func closeLogFile() {
        fileHandleLock.withLock { handle in
            if let handle {
                let ts = timestampString(from: Date())
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

    /// Removes old log files, keeping only the most recent `keepCount`.
    private func cleanupOldLogFiles(in directory: URL, keepCount: Int) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                )
                let logFiles = files
                    .filter { $0.pathExtension == "log" }
                    .sorted { a, b in
                        let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                        let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                        return dateA > dateB
                    }

                if logFiles.count > keepCount {
                    for file in logFiles.dropFirst(keepCount) {
                        try FileManager.default.removeItem(at: file)
                        osLog.debug("Removed old log file: \(file.lastPathComponent, privacy: .public)")
                    }
                }
            } catch {
                osLog.warning("Failed to clean up old log files: \(error)")
            }
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
    func log(level: Level, category: String, at date: Date = Date(), message: String) {
        guard isEnabled else { return }

        let timestamp = timestampString(from: date)
        let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"

        guard let data = line.data(using: .utf8) else { return }

        writeQueue.async { [weak self] in
            self?.fileHandleLock.withLock { handle in
                handle?.write(data)
            }
        }
    }

    private func timestampString(from date: Date) -> String {
        timestampFormatter.withLock { $0.string(from: date) }
    }

    private func fileNameString(from date: Date) -> String {
        fileNameFormatter.withLock { $0.string(from: date) }
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
    /// A single lock protects the mutable formatter used by every lightweight
    /// logger. DiagLog values are commonly shared by main-actor and detached
    /// work, so an instance formatter would still be raced by those callers.
    private static let timestampFormatter = OSAllocatedUnfairLock(initialState: {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }())

    init(category: String) {
        self.osLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw",
            category: category
        )
        self.category = category
    }

    /// Shared emission for all five levels: evaluate the message once,
    /// capture a single timestamp instant, forward it to os_log (with the
    /// per-level emitter closure) and to the diagnostic file when that
    /// optional file sink is enabled.
    ///
    /// Console logging is intentionally independent of the file-logging
    /// setting. The setting promises to avoid disk writes, not to remove
    /// normal OSLog visibility for startup, layout, and permission paths.
    private func emit(
        level: DiagnosticLogger.Level,
        message: () -> String,
        toOSLog: (String) -> Void
    ) {
        let now = Date()
        let msg = message()
        let timestamp = Self.timestampFormatter.withLock { $0.string(from: now) }
        toOSLog("[\(timestamp)] \(msg)")
        DiagnosticLogger.shared.log(level: level, category: category, at: now, message: msg)
    }

    func debug(_ message: @autoclosure () -> String) {
        emit(level: .debug, message: message) {
            osLogger.debug("\($0, privacy: .public)")
        }
    }

    func info(_ message: @autoclosure () -> String) {
        emit(level: .info, message: message) {
            osLogger.info("\($0, privacy: .public)")
        }
    }

    func notice(_ message: @autoclosure () -> String) {
        emit(level: .notice, message: message) {
            osLogger.notice("\($0, privacy: .public)")
        }
    }

    func warning(_ message: @autoclosure () -> String) {
        emit(level: .warning, message: message) {
            osLogger.warning("\($0, privacy: .public)")
        }
    }

    func error(_ message: @autoclosure () -> String) {
        emit(level: .error, message: message) {
            osLogger.error("\($0, privacy: .public)")
        }
    }
}
