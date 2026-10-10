//
//  WallpaperChangeMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Watches the wallpaper index because macOS has no public change notification; adaptive appearance needs timing, not wallpaper identity.
/// Improves latency only: periodic pixel refresh still covers dynamic/aerial wallpapers that never rewrite the index.
@MainActor
final class WallpaperChangeMonitor {
    /// System wallpaper index; Dock/desktoppicture.db does not exist on supported macOS versions.
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

    /// - Parameters:
    ///   - url: The file to watch. Defaults to the system wallpaper index.
    ///   - debounce: Coalesces repeated index writes from one wallpaper change to avoid redundant captures.
    init(url: URL = WallpaperChangeMonitor.indexURL, debounce: Duration = .milliseconds(500)) {
        self.url = url
        self.debounce = debounce
    }

    deinit {
        // deinit cannot call main-actor stop(); cancel the source here for descriptor teardown.
        debounceTask?.cancel()
        restartRetryTask?.cancel()
        source?.cancel()
    }

    /// Starts watching. Does nothing if already watching.
    func start() {
        guard source == nil else { return }

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Fresh accounts may lack the index until a wallpaper is set; periodic refresh still covers them.
            diagLog.debug("Wallpaper index not open-able at \(self.url.path); relying on periodic refresh")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        // GCD retains the handler; weak source capture avoids a cycle and leaks on each index replacement.
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                // Atomic replacement leaves the descriptor on an unlinked inode; reopen or only the first change is observed.
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

    /// Reopening can race the new file's link; retry once, then rely on periodic refresh.
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
