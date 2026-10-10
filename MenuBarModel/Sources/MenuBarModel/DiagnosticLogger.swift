//
//  DiagnosticLogger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import OSLog

/// Writes diagnostic log messages to a file on disk when enabled, so users
/// can capture detailed logs for troubleshooting without a debug build.
///
/// Log files are written to ~/Library/Logs/Thaw/.
public final class DiagnosticLogger: Sendable {
    public static let shared = DiagnosticLogger()

    /// Whether diagnostic logging to file is currently enabled.
    /// Thread-safe via OSAllocatedUnfairLock.
    private let isEnabledLock = OSAllocatedUnfairLock(initialState: false)

    public var isEnabled: Bool {
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
    public var logDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Thaw", isDirectory: true)
    }

    /// Returns the most recent log file in the log directory, if any.
    public var latestLogFile: URL? {
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

    public var currentLogFile: URL? {
        currentLogFileLock.withLock { $0 }
    }

    /// The file handle for writing.
    private let fileHandleLock = OSAllocatedUnfairLock<FileHandle?>(initialState: nil)

    /// Internal logger for DiagnosticLogger's own messages.
    private let osLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw",
        category: "DiagnosticLogger"
    )

    /// Timestamp in each log line: yyyy-MM-dd HH:mm:ss.SSS, local time.
    ///
    /// A format style is Sendable, so unlike DateFormatter it can be shared
    /// by every thread that logs without a lock.
    private static let timestampStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .current,
        calendar: Calendar(identifier: .gregorian)
    )

    /// Timestamp in log file names: yyyy-MM-dd_HH-mm-ss, local time.
    private static let fileNameStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)_\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))-\(minute: .twoDigits)-\(second: .twoDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .current,
        calendar: Calendar(identifier: .gregorian)
    )

    /// Serial queue for file I/O.
    private let writeQueue = DispatchQueue(
        label: "com.stonerl.Thaw.DiagnosticLogger.writeQueue",
        qos: .utility
    )

    private init() {
        // Intentionally empty: DiagnosticLogger is a singleton, and log file setup is deferred until logging is enabled.
    }

    // MARK: - File Management

    /// Enables diagnostic logging using a log file URL chosen by another
    /// process. The MenuBarItemService XPC service calls this with the main
    /// app's log path so both append to one file; minting a name from each
    /// wall clock can straddle a second and produce two files. Safe to call
    /// repeatedly; the existing handle is closed first.
    public func attachToFile(at fileURL: URL) {
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

        let fileName = "thaw_\(Self.fileNameStyle.format(Date())).log"
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

        // POSIX open(2) with O_APPEND so the main app and the XPC service can
        // share the file: FileHandle(forWritingTo:) would truncate it and
        // per-fd offsets would race. O_APPEND makes each write land at
        // end-of-file atomically between processes; FileHandle does not
        // expose these flags.
        let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else {
            osLog.error("Failed to open log file at \(fileURL.path): errno \(errno)")
            isEnabledLock.withLock { $0 = false }
            return
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fileHandleLock.withLock { $0 = handle }
        currentLogFileLock.withLock { $0 = fileURL }

        // Each process writes its own header into the shared file. The
        // Process line distinguishes them; the per-line timestamps keep
        // chronological order.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        // GitCommitSHA is stamped into Info.plist by a build phase and reads
        // "unknown" when that phase is not wired up.
        let sha = Bundle.main.infoDictionary?["GitCommitSHA"] as? String ?? "unknown"
        let header = """
        ========================================
        Thaw Diagnostic Log
        Started: \(Self.timestampStyle.format(Date()))
        Process: \(ProcessInfo.processInfo.processName)
        Version: \(version) (\(build)) commit \(sha)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ========================================\n\n
        """
        if let data = header.data(using: .utf8) {
            handle.write(data)
        }

        osLog.info("Diagnostic logging started: \(fileURL.path, privacy: .public)")

        cleanupOldLogFiles(in: dir, keepCount: 5)
    }

    private func closeLogFile() {
        fileHandleLock.withLock { handle in
            if let handle {
                let ts = Self.timestampStyle.format(Date())
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
    public enum Level: String {
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

        let timestamp = Self.timestampStyle.format(Date())
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

/// A lightweight diagnostic-aware logger that wraps os.Logger and
/// additionally writes to the diagnostic log file when enabled. Create one
/// per component, for example DiagLog(category: "MenuBarItemManager") then
/// log.debug("something happened").
///
/// Every level gates on its listeners before evaluating the message: the
/// autoclosure stays un-evaluated unless the diagnostic file is open or
/// os_log will actually persist that level. Debug and info are not persisted
/// in a normal session, so debug call sites inside per-item loops cost one
/// flag check and build no string.
public struct DiagLog: Sendable {
    private let osLogger: Logger
    private let category: String

    public init(category: String) {
        self.osLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw",
            category: category
        )
        self.category = category
    }

    public func debug(_ message: @autoclosure () -> String) {
        guard DiagnosticLogger.shared.isEnabled || osLogger.isEnabled(type: .debug) else { return }
        let msg = message()
        osLogger.debug("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .debug, category: category, message: msg)
    }

    public func info(_ message: @autoclosure () -> String) {
        guard DiagnosticLogger.shared.isEnabled || osLogger.isEnabled(type: .info) else { return }
        let msg = message()
        osLogger.info("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .info, category: category, message: msg)
    }

    public func notice(_ message: @autoclosure () -> String) {
        // OSLogType has no notice level; .default is the nearest gate and is
        // always persisted, so the file flag is the meaningful one here.
        guard DiagnosticLogger.shared.isEnabled || osLogger.isEnabled(type: .default) else { return }
        let msg = message()
        osLogger.notice("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .notice, category: category, message: msg)
    }

    public func warning(_ message: @autoclosure () -> String) {
        // OSLogType has no warning level; os.Logger's warning maps onto the
        // error level.
        guard DiagnosticLogger.shared.isEnabled || osLogger.isEnabled(type: .error) else { return }
        let msg = message()
        osLogger.warning("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .warning, category: category, message: msg)
    }

    public func error(_ message: @autoclosure () -> String) {
        guard DiagnosticLogger.shared.isEnabled || osLogger.isEnabled(type: .error) else { return }
        let msg = message()
        osLogger.error("\(msg, privacy: .public)")
        DiagnosticLogger.shared.log(level: .error, category: category, message: msg)
    }
}
