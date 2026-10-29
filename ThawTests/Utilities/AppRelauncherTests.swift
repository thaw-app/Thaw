//
//  AppRelauncherTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("App relaunch watcher")
struct AppRelauncherTests {
    @Test("The bundle path is passed as its own argument, never inside the shell program")
    func pathIsAPositionalArgument() {
        let path = "/Applications/It's \"Thaw\" $(touch /tmp/pwned) `id` & me.app"

        let arguments = AppRelauncher.watcherArguments(pid: 4242, bundlePath: path)

        #expect(arguments.count == 5)
        #expect(arguments[0] == "-c")
        #expect(!arguments[1].contains(path))
        #expect(!arguments[1].contains("4242"))
        #expect(arguments[1].contains("\"$1\""))
        #expect(arguments[1].contains("/usr/bin/open \"$2\""))
        #expect(arguments[2] == "sh")
        #expect(arguments[3] == "4242")
        #expect(arguments[4] == path)
    }

    @Test("Running the watcher with a hostile path executes none of it")
    func hostilePathIsNotExecuted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppRelauncherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("marker").path
        let path = directory.path + "/missing ' \" $(touch \(marker)) `touch \(marker)`.app"

        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()

        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = AppRelauncher.watcherArguments(pid: finished.processIdentifier, bundlePath: path)
        watcher.standardError = FileHandle.nullDevice
        try watcher.run()
        watcher.waitUntilExit()

        #expect(!FileManager.default.fileExists(atPath: marker))
    }
}
