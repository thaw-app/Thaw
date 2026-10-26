//
//  SettingsProcessHostTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Waits on the main actor until the condition holds, or gives up after the timeout.
/// It returns as soon as the condition holds, so the generous limit only matters
/// on a busy runner, where pipe messages can take seconds.
@MainActor
func settingsLinkWait(timeout: Duration = .seconds(15), until condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// The settings process as the host sees it, played by pipes in this process.
@MainActor
private final class FakeSettingsChild {
    struct Launched {
        let arguments: [String]
        let onEnd: @Sendable (Int32) -> Void
        let toChild: Pipe
        let fromChild: Pipe
        let end: SettingsLinkEndpoint
    }

    var isRunning = true
    var failsToLaunch = false
    private(set) var launches = [Launched]()
    private(set) var received = [SettingsLinkMessage]()

    /// What reached the child, leaving out the notices any defaults write in the test process sends.
    var receivedMessages: [SettingsLinkMessage] {
        received.filter { $0 != .settingsChanged }
    }

    func launch(arguments: [String], onEnd: @escaping @Sendable (Int32) -> Void) throws -> SettingsProcessHost.Child {
        if failsToLaunch {
            throw CocoaError(.fileNoSuchFile)
        }
        let toChild = Pipe()
        let fromChild = Pipe()
        let end = SettingsLinkEndpoint(
            input: toChild.fileHandleForReading,
            output: fromChild.fileHandleForWriting,
            onMessage: { [weak self] in self?.received.append($0) }
        )
        launches.append(Launched(arguments: arguments, onEnd: onEnd, toChild: toChild, fromChild: fromChild, end: end))
        return SettingsProcessHost.Child(
            processIdentifier: -1,
            isRunning: { [weak self] in self?.isRunning ?? false },
            fromChild: fromChild.fileHandleForReading,
            toChild: toChild.fileHandleForWriting
        )
    }
}

/// What the host asked the app to do.
@MainActor
private final class AppSideCalls {
    var reloads = 0
    var openedInApp = [String]()
    var pagesChanged = [String]()
    var updateChecks = 0
    var quits = 0

    func side() -> SettingsProcessHost.AppSide {
        SettingsProcessHost.AppSide(
            reloadSettings: { self.reloads += 1 },
            openInApp: { self.openedInApp.append($0) },
            pageChanged: { self.pagesChanged.append($0) },
            checkForUpdates: { self.updateChecks += 1 },
            quit: { self.quits += 1 },
            updatesState: { .updatesState(canCheck: true, lastCheck: nil) }
        )
    }
}

@Suite("Settings process host")
@MainActor
struct SettingsProcessHostTests {
    private let child = FakeSettingsChild()
    private let calls = AppSideCalls()

    private func host(isEnabled: Bool = true) -> SettingsProcessHost {
        let child = child
        return SettingsProcessHost(
            app: calls.side(),
            isEnabled: { isEnabled },
            launch: { try child.launch(arguments: $0, onEnd: $1) }
        )
    }

    @Test("Nothing starts while the setting is off, in Simple Mode, or for a pane that needs the app")
    func declinedOpens() {
        #expect(!host(isEnabled: false).show(pane: "General", simpleMode: false))
        let host = host()
        #expect(!host.show(pane: "General", simpleMode: true))
        #expect(!host.show(pane: "Menu Bar Layout", simpleMode: false))
        #expect(child.launches.isEmpty)
    }

    @Test("The first open starts the process on the pane and sends it the updater state")
    func launchSendsUpdatesState() async {
        let host = host()
        #expect(host.show(pane: "About", simpleMode: false))
        #expect(child.launches.map(\.arguments) == [["--settings", "About"]])
        #expect(await settingsLinkWait { child.receivedMessages.contains(.updatesState(canCheck: true, lastCheck: nil)) })
    }

    @Test("An open while the process runs brings it to the pane instead of starting another")
    func runningProcessIsReused() async {
        let host = host()
        #expect(host.show(pane: "General", simpleMode: false))
        #expect(host.show(pane: "Privacy", simpleMode: false))
        #expect(child.launches.count == 1)
        #expect(await settingsLinkWait { child.receivedMessages.contains(.show(pane: "Privacy")) })
    }

    @Test("Each message from the process reaches the app")
    func messagesReachTheApp() async throws {
        let host = host()
        #expect(host.show(pane: "General", simpleMode: false))
        let end = try #require(child.launches.first?.end)
        for message: SettingsLinkMessage in [
            .openInApp(pane: "Menu Bar Layout"), .pageChanged(pane: "About"), .checkForUpdates, .quit,
            .show(pane: "General"), .updatesState(canCheck: false, lastCheck: nil), .settingsChanged,
        ] {
            end.send(message)
        }
        #expect(await settingsLinkWait { calls.quits == 1 && calls.reloads > 0 })
        #expect(calls.openedInApp == ["Menu Bar Layout"])
        #expect(calls.pagesChanged == ["About"])
        #expect(calls.updateChecks == 1)
    }

    @Test("A process that ended is started again on the next open")
    func endedProcessIsRestarted() async throws {
        let host = host()
        #expect(host.show(pane: "General", simpleMode: false))
        try #require(child.launches.first).onEnd(0)
        await mainActorQueueDrained()
        #expect(host.show(pane: "About", simpleMode: false))
        #expect(child.launches.count == 2)
    }

    @Test("The end of an earlier process leaves the one started after it alone")
    func staleEndIsIgnored() async throws {
        let host = host()
        #expect(host.show(pane: "General", simpleMode: false))
        child.isRunning = false
        #expect(host.show(pane: "About", simpleMode: false))
        child.isRunning = true
        try #require(child.launches.first).onEnd(0)
        await mainActorQueueDrained()
        #expect(host.show(pane: "Privacy", simpleMode: false))
        #expect(child.launches.count == 2)
    }

    @Test("A process that fails to start leaves the app to show Settings, and the next open tries again")
    func failedLaunch() {
        let host = host()
        child.failsToLaunch = true
        #expect(!host.show(pane: "General", simpleMode: false))
        child.failsToLaunch = false
        #expect(host.show(pane: "General", simpleMode: false))
        #expect(child.launches.count == 1)
    }

    @Test("The app's window tells the process it's up only once it becomes key")
    func appWindowWaitsForKey() async throws {
        let host = host()
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        host.appWindowOpened(window)
        #expect(host.show(pane: "General", simpleMode: false))
        host.appWindowOpened(window)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!child.receivedMessages.contains(.shownInApp), "Nothing is sent before the window is key")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(await settingsLinkWait { child.receivedMessages.contains(.shownInApp) })
        #expect(child.receivedMessages.count { $0 == .shownInApp } == 1)
    }

    @Test("A later app window replaces the wait for an earlier one")
    func laterAppWindowReplacesWait() async throws {
        let host = host()
        let first = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let second = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        #expect(host.show(pane: "General", simpleMode: false))
        host.appWindowOpened(first)
        host.appWindowOpened(second)
        try await Task.sleep(for: .milliseconds(50))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!child.receivedMessages.contains(.shownInApp), "The earlier window no longer counts")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second)
        #expect(await settingsLinkWait { child.receivedMessages.contains(.shownInApp) })
        #expect(child.receivedMessages.count { $0 == .shownInApp } == 1)
    }

    @Test("Once the process closes its end, nothing more is sent to it")
    func closedEndStopsSending() async throws {
        let host = host()
        #expect(host.show(pane: "General", simpleMode: false))
        let launched = try #require(child.launches.first)
        try launched.fromChild.fileHandleForWriting.close()
        #expect(await settingsLinkWait { !host.isLinked })
        #expect(host.show(pane: "Privacy", simpleMode: false))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!child.receivedMessages.contains(.show(pane: "Privacy")))
    }
}
