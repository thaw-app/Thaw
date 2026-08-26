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
        source.setEventHandler { [weak self] in
            guard let self else { return }
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
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Re-opens the watch after an atomic replacement.
    private func restart() {
        source?.cancel()
        source = nil
        descriptor = -1
        start()
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
