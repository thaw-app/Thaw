//
//  SettingsLinkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Settings process link")
struct SettingsLinkTests {
    @Test("A message survives being written as a line", arguments: [
        SettingsLinkMessage.show(pane: "General"),
        .show(pane: nil),
        .settingsChanged,
        .openInApp(pane: "Menu Bar Layout"),
        .pageChanged(pane: "About"),
        .updatesState(canCheck: true, lastCheck: Date(timeIntervalSince1970: 1_800_000_000)),
        .updatesState(canCheck: false, lastCheck: nil),
        .checkForUpdates,
        .quit,
    ])
    func roundTrip(message: SettingsLinkMessage) {
        #expect(message.line.last == 0x0A)
        #expect(SettingsLinkMessage(line: message.line.dropLast()) == message)
    }

    @Test("A line that isn't a message is dropped")
    func strayLine() {
        #expect(SettingsLinkMessage(line: Data("some log line".utf8)) == nil)
        #expect(SettingsLinkMessage(line: Data()) == nil)
    }

    @Test("Two ends of a pipe pass messages in order, and a closed pipe ends the link")
    @MainActor
    func endpoints() async {
        let toChild = Pipe()
        let fromChild = Pipe()
        var received = [SettingsLinkMessage]()
        var endpoints = [SettingsLinkEndpoint]()
        await confirmation("the child end closes") { closed in
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                endpoints.append(SettingsLinkEndpoint(
                    input: toChild.fileHandleForReading,
                    output: fromChild.fileHandleForWriting,
                    onMessage: { received.append($0) },
                    onClose: {
                        closed()
                        done.resume()
                    }
                ))
                let app = SettingsLinkEndpoint(
                    input: fromChild.fileHandleForReading,
                    output: toChild.fileHandleForWriting,
                    onMessage: { _ in }
                )
                endpoints.append(app)
                app.send(.show(pane: "About"))
                app.send(.updatesState(canCheck: true, lastCheck: nil))
                try? toChild.fileHandleForWriting.close()
            }
        }
        endpoints.forEach { $0.close() }
        #expect(received == [.show(pane: "About"), .updatesState(canCheck: true, lastCheck: nil)])
    }

    @Test("Only enabled, non-Simple-Mode opens of local panes use the settings process")
    func route() {
        #expect(SettingsProcessRoute.runsInOwnProcess(pane: "General", simpleMode: false, isEnabled: true))
        #expect(!SettingsProcessRoute.runsInOwnProcess(pane: "General", simpleMode: false, isEnabled: false))
        #expect(!SettingsProcessRoute.runsInOwnProcess(pane: "General", simpleMode: true, isEnabled: true))
        #expect(!SettingsProcessRoute.runsInOwnProcess(pane: "Menu Bar Layout", simpleMode: false, isEnabled: true))
    }

    @Test("The launch pane follows the settings argument")
    func launchPane() {
        #expect(SettingsProcessRoute.launchPane(in: ["Thaw", "--settings", "The Lab"]) == "The Lab")
        #expect(SettingsProcessRoute.launchPane(in: ["Thaw", "--settings"]) == nil)
        #expect(SettingsProcessRoute.launchPane(in: ["Thaw"]) == nil)
    }
}
