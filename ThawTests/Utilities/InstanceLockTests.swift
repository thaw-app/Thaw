//
//  InstanceLockTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The lock file that only one copy of Thaw can hold, tried on a scratch file.
@Suite("Instance lock")
struct InstanceLockTests {
    private func scratchURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "InstanceLockTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Thaw.instance.lock", directoryHint: .notDirectory)
    }

    @Test("Only one holder at a time, and the lock is free again once released")
    func exclusive() {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = InstanceLock(url: url)
        let second = InstanceLock(url: url)
        #expect(first.tryAcquire() == .acquired, "The missing folder and file are created")
        #expect(first.isHeld)
        #expect(first.tryAcquire() == .acquired, "Taking a lock already held succeeds")
        #expect(second.tryAcquire() == .heldElsewhere)
        #expect(!second.isHeld)
        first.release()
        #expect(!first.isHeld)
        #expect(second.tryAcquire() == .acquired)
    }

    @Test("A holder that goes away frees the lock")
    func freedWithHolder() {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var holder: InstanceLock? = InstanceLock(url: url)
        #expect(holder?.tryAcquire() == .acquired)
        holder = nil
        #expect(InstanceLock(url: url).tryAcquire() == .acquired)
    }

    @Test("A lock file that can't be opened is reported as unavailable")
    func unavailable() {
        let lock = InstanceLock(url: URL(filePath: "/dev/null/Thaw.instance.lock"))
        #expect(lock.tryAcquire() == .unavailable)
    }

    @Test("Every build shares one lock file")
    func defaultLocation() {
        #expect(InstanceLock.defaultURL.lastPathComponent == "Thaw.instance.lock")
        #expect(InstanceLock.defaultURL.deletingLastPathComponent().lastPathComponent == "Thaw")
    }
}
