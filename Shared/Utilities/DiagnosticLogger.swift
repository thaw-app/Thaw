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
            if newValue && !oldValue {
                openLogFile()
            } else if !newValue && oldValue {
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

    private init() {}

    // MARK: - File Management

    /// Creates the log directory if needed and opens a new log file.
    private func openLogFile() {
        let dir = logDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            osLog.error("Failed to create log directory at \(dir.path): \(error)")
            return
        }

        let fileName = "thaw_\(fileNameFormatter.string(from: Date())).log"
        let fileURL = dir.appendingPathComponent(fileName)

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            fileHandleLock.withLock { $0 = handle }
            currentLogFileLock.withLock { $0 = fileURL }

            // Write header
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let header = """
            ========================================
            Thaw Diagnostic Log
            Started: \(timestampFormatter.string(from: Date()))
            Version: \(version) (\(build))
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            ========================================\n\n
            """
            if let data = header.data(using: .utf8) {
                handle.write(data)
            }

            osLog.info("Diagnostic logging started: \(fileURL.path, privacy: .public)")
        } catch {
            osLog.error("Failed to open log file at \(fileURL.path): \(error)")
        }

        // Clean up old log files (keep last 5)
        cleanupOldLogFiles(in: dir, keepCount: 5)
    }

    /// Closes the current log file.
    private func closeLogFile() {
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
    func log(level: Level, category: String, message: String) {
        guard isEnabled else { return }

        let timestamp = timestampFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"

        guard let data = line.data(using: .utf8) else { return }

        writeQueue.async { [weak self] in
            self?.fileHandleLock.withLock { handle in
                handle?.write(data)
            }
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
