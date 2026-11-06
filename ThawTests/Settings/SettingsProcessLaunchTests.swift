//
//  SettingsProcessLaunchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// How the settings process is started and wired, with /bin/cat standing in for Thaw's own executable.
@Suite("Settings process launch")
struct SettingsProcessLaunchTests {
    private final class Ended: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int32?

        var status: Int32? {
            lock.withLock { value }
        }

        func record(_ status: Int32) {
            lock.withLock { value = status }
        }
    }

    @Test(
        "What the app writes reaches the child, the child's output comes back, and its end is reported",
        .timeLimit(.minutes(1))
    )
    func pipesAndEndAreWired() async throws {
        let ended = Ended()
        let child = try SettingsProcessHost.launch(
            URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            onEnd: { ended.record($0) }
        )
        #expect(child.processIdentifier > 0)

        child.toChild.write(Data("hello\n".utf8))
        try child.toChild.close()
        let echoed = try child.fromChild.readToEnd()

        #expect(echoed == Data("hello\n".utf8))
        while ended.status == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ended.status == 0)
        #expect(!child.isRunning())
    }

    @Test("The arguments are passed to the child as given")
    func argumentsArePassed() throws {
        let child = try SettingsProcessHost.launch(
            URL(fileURLWithPath: "/bin/echo"),
            arguments: ["--settings", "general"],
            onEnd: { _ in }
        )
        try child.toChild.close()
        #expect(try child.fromChild.readToEnd() == Data("--settings general\n".utf8))
    }

    @Test("An executable that doesn't exist can't be launched")
    func missingExecutableThrows() {
        #expect(throws: (any Error).self) {
            try SettingsProcessHost.launch(URL(fileURLWithPath: "/nonexistent/thaw-test"), arguments: [], onEnd: { _ in })
        }
    }
}
