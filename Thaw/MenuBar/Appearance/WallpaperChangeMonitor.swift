//
//  WallpaperChangeMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Watches for desktop wallpaper changes and reports them as events.
///
/// Adaptive appearance samples the pixels behind the menu bar, so it does
/// not need to know *what* the wallpaper is — only *when* it changed. macOS
/// posts no public notification for that, so this watches the file the
/// system rewrites whenever the wallpaper is set.
///
/// This is a latency improvement, not a correctness one: the periodic
/// refresh in ``MenuBarManager`` already catches a new wallpaper within its
/// poll interval, and still has to, because a dynamic or aerial wallpaper
/// changes its pixels continuously without ever rewriting the index.
@MainActor
final class WallpaperChangeMonitor {
    /// The wallpaper store index, rewritten by the system on every
    /// wallpaper change. The path moved here in macOS 14; the older
    /// `Dock/desktoppicture.db` no longer exists on the deployment target.
    static let indexURL = URL(
        fileURLWithPath: NSHomeDirectory()
    )
    .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    private let diagLog = DiagLog(category: "WallpaperChangeMonitor")
    private let url: URL
    private let debounce: Duration
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?
    private var restartRetryTask: Task<Void, Never>?

    /// How long to wait before retrying a re-open that lost the race with the
    /// system's replacement of the index.
    private let restartRetryDelay: Duration = .milliseconds(500)

    /// Called on the main actor after the wallpaper changes and the
    /// debounce interval elapses.
    var onChange: (() -> Void)?

    /// Creates a monitor for the given file.
    ///
    /// - Parameters:
    ///   - url: The file to watch. Defaults to the system wallpaper index.
    ///   - debounce: How long to coalesce writes. Setting a wallpaper
    ///     rewrites the index several times in quick succession, and each
    ///     rewrite would otherwise cost a screen capture.
    init(url: URL = WallpaperChangeMonitor.indexURL, debounce: Duration = .milliseconds(500)) {
        self.url = url
        self.debounce = debounce
    }

    deinit {
        // `stop()` is main-actor isolated and deinit is not, so tear the
        // descriptor down directly. The source's cancel handler cannot be
        // relied on here because nothing will run it after deallocation.
        debounceTask?.cancel()
        restartRetryTask?.cancel()
        source?.cancel()
    }

    /// Starts watching. Does nothing if already watching.
    func start() {
        guard source == nil else { return }

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Absent on a fresh account until the user first sets a
            // wallpaper. The periodic refresh covers this case, so this is
            // a downgrade in latency rather than a failure.
            diagLog.debug("Wallpaper index not open-able at \(self.url.path); relying on periodic refresh")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        // Capture the source weakly: GCD retains its handler, so a strong
        // capture here would form a cycle the source cannot break out of.
        // `restart()` replaces the source on every atomic index replacement,
        // so leaked sources would accumulate over a session.
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                // The system replaces the index atomically rather than
                // writing in place, so the descriptor now points at an
                // unlinked inode. Re-open before reporting, or this fires
                // exactly once per launch.
                restart()
            }
            scheduleChange()
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        self.source = source
        source.resume()
        diagLog.debug("Watching wallpaper index at \(self.url.path)")
    }

    /// Stops watching and releases the descriptor.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        restartRetryTask?.cancel()
        restartRetryTask = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Re-opens the watch after an atomic replacement.
    ///
    /// The replacement is not instantaneous, so the re-open can run before the
    /// new file is linked. Nothing else re-opens the watch, so a lost race
    /// would otherwise leave the rest of the session on the periodic refresh
    /// alone; retry once, after which the periodic refresh is the fallback it
    /// always was.
    private func restart() {
        restartRetryTask?.cancel()
        restartRetryTask = nil
        source?.cancel()
        source = nil
        descriptor = -1
        start()
        guard source == nil else { return }
        restartRetryTask = Task { [weak self, restartRetryDelay] in
            try? await Task.sleep(for: restartRetryDelay)
            guard !Task.isCancelled, let self else { return }
            start()
        }
    }

    /// Coalesces a burst of writes into a single reported change.
    private func scheduleChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            onChange?()
        }
    }
}
