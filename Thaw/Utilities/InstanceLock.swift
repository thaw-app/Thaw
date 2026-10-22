//
//  InstanceLock.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

/// An exclusive advisory lock on a file. The kernel releases it when the process exits, so a copy that
/// crashed never leaves it behind.
nonisolated final class InstanceLock {
    /// Shared by every Thaw build, so a release and a debug copy exclude each other.
    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Thaw", directoryHint: .isDirectory)
            .appending(path: "Thaw.instance.lock", directoryHint: .notDirectory)
    }

    let url: URL
    private var descriptor: Int32 = -1

    init(url: URL = InstanceLock.defaultURL) {
        self.url = url
    }

    deinit {
        release()
    }

    var isHeld: Bool {
        descriptor >= 0
    }

    /// Takes the lock without waiting. Taking a lock this object already holds succeeds.
    func tryAcquire() -> SingleInstanceRule.LockState {
        guard descriptor < 0 else { return .acquired }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard file >= 0 else { return .unavailable }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(file)
            return failure == EWOULDBLOCK ? .heldElsewhere : .unavailable
        }
        descriptor = file
        return .acquired
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
