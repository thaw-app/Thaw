//
//  WallpaperChangeMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Watches for desktop wallpaper changes and reports them as events.
///
/// macOS posts no public notification for wallpaper changes, so this watches
/// the file the system rewrites when the wallpaper is set.
///
/// Only a latency improvement: the periodic refresh in ``MenuBarManager``
/// still has to run, because dynamic and aerial wallpapers change pixels
/// without rewriting the index.
@MainActor
final class WallpaperChangeMonitor {
    /// The wallpaper store index. The older `Dock/desktoppicture.db` no
    /// longer exists on the deployment target.
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

    /// Called on the main actor after the debounce interval elapses.
    var onChange: (() -> Void)?

    /// - Parameters:
    ///   - url: The file to watch.
    ///   - debounce: How long to coalesce writes. Setting a wallpaper
    ///     rewrites the index several times, each costing a screen capture.
    init(url: URL = WallpaperChangeMonitor.indexURL, debounce: Duration = .milliseconds(500)) {
        self.url = url
        self.debounce = debounce
    }

    deinit {
        // `stop()` is main-actor isolated and deinit is not, and the cancel
        // handler won't run after deallocation, so close directly.
        debounceTask?.cancel()
        restartRetryTask?.cancel()
        source?.cancel()
    }

    /// Does nothing if already watching.
    func start() {
        guard source == nil else { return }

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Absent on a fresh account until a wallpaper is set. The
            // periodic refresh covers it.
            diagLog.debug("Wallpaper index not open-able at \(self.url.path); relying on periodic refresh")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        // GCD retains its handler, so a strong capture would leak a source
        // on every `restart()`.
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                // The index is replaced atomically, leaving the descriptor on
                // an unlinked inode. Re-open, or this fires once per launch.
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
    /// The re-open can run before the new file is linked, so retry once
    /// before falling back to the periodic refresh.
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
