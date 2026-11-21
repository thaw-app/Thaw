//
//  SettingsLinkToolsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// A stand-in for the running app: it records the steps a task takes instead of taking them.
@MainActor
private final class FakeApp {
    struct Refused: LocalizedError {
        var errorDescription: String? {
            "The menu bar refused."
        }
    }

    var steps = [String]()
    /// While set, the first wait for moves holds until heldWait is resumed.
    var holdsFirstWait = false
    var heldWait: CheckedContinuation<Void, Never>?
    var backupName: String? = "Backup 1"
    var fails = false
    /// How many times the layout table is found missing before it appears.
    var tableMissing = 0
    var logFile: URL?
    var newestLogFile: URL?
    var isTableUnreadable = false
    var sent = [(topic: String, payload: Data)]()
    /// How often something the app's status reads has changed.
    var statusChanges = 0
    var send: (String, Data) -> Void = { _, _ in }
    let sampleDirectory = FileManager.default.temporaryDirectory.appending(path: "SettingsLinkToolsTests-\(UUID().uuidString)")
    /// A notice of this test's own, so the samples other suites write are not taken for the app's.
    let sampleWritten = Notification.Name("SettingsLinkToolsTests.\(UUID().uuidString)")

    var performer: ToolsTaskPerformer {
        ToolsTaskPerformer(
            waitForMoves: {
                self.steps.append("wait")
                if self.holdsFirstWait {
                    self.holdsFirstWait = false
                    await withCheckedContinuation { self.heldWait = $0 }
                }
            },
            resetSettings: { self.steps.append("resetSettings") },
            rebuildSavedLayout: {
                self.steps.append("rebuild")
                if self.fails {
                    throw Refused()
                }
                return self.backupName
            },
            forgetStrandedRepairs: { self.steps.append("forget") },
            layoutTableExists: {
                self.tableMissing -= 1
                return self.tableMissing < 0
            },
            pause: { _ in self.steps.append("pause") },
            restartMenuBar: { self.steps.append("restartMenuBar") },
            resetPermissions: { self.steps.append("resetPermissions") },
            chooseReducedMode: { self.steps.append("reducedMode") },
            openRecovery: { self.steps.append("openRecovery") },
            writeItemList: {
                self.steps.append("writeItemList")
                return URL(fileURLWithPath: "/tmp/item-dump-1.json")
            },
            restoreBackup: {
                self.steps.append("restore \($0.lastPathComponent)")
                return (3, 1)
            },
            relaunch: { self.steps.append("relaunch") },
            quit: { self.steps.append("quit") }
        )
    }

    func link(tools: ToolsSettings, moveMonitor: MovePipelineMonitor) -> ToolsAppLink {
        ToolsAppLink(tools: tools, moveMonitor: moveMonitor, app: ToolsAppLink.AppSide(
            performer: { self.performer },
            relaunch: { self.steps.append("relaunch") },
            openLogFile: { self.logFile },
            newestLogFile: { self.newestLogFile },
            sampleDirectory: { self.sampleDirectory },
            sampleWritten: sampleWritten,
            isLayoutTableUnreadable: { self.isTableUnreadable },
            send: { topic, payload in
                self.sent.append((topic, payload))
                self.send(topic, payload)
            }
        ))
    }

    var answers: [ToolsTaskAnswer] {
        sent.filter { $0.topic == ToolsLink.answer }.compactMap { SettingsLinkPayload.decode(ToolsTaskAnswer.self, from: $0.payload) }
    }
}

@Suite("Troubleshooting in the settings process", .serialized, .scratchDefaults)
@MainActor
final class SettingsLinkToolsTests {
    private let app = FakeApp()
    private let tools = ToolsSettings()
    private let moveMonitor = MovePipelineMonitor()
    /// The settings process's state, which is built and never started.
    private let child = AppState()
    private var commands = [SettingsLinkMessage]()
    private var followedLogs = [URL?]()
    private var writeEnds = [FileHandle]()
    private var host: SettingsProcessHost?
    private var session: SettingsProcessSession?

    init() {
        // The log itself stays as it is; these tests only change the setting.
        tools.setLogEnabled = { _ in }
        tools.sendRotationPolicy = { _ in }
    }

    isolated deinit {
        writeEnds.forEach { try? $0.close() }
        try? FileManager.default.removeItem(at: app.sampleDirectory)
    }

    private var report: ToolsAppReport {
        child.settings.tools.appReport
    }

    /// A remote that keeps what it was asked to send.
    private func recordingRemote() -> SettingsRemote {
        SettingsRemote { [weak self] in self?.commands.append($0) }
    }

    private var requests: [ToolsTaskRequest] {
        commands.compactMap { message in
            guard case let .command(name: ToolsLink.perform, payload) = message else { return nil }
            return SettingsLinkPayload.decode(ToolsTaskRequest.self, from: payload)
        }
    }

    private func childFeature() -> SettingsChildFeature {
        .tools(child, followLog: { [weak self] in self?.followedLogs.append($0) })
    }

    /// The app's feature in a host and the page's in a session, joined by pipes as the two processes are.
    private func connect() -> SettingsRemote {
        let toChild = Pipe()
        let fromChild = Pipe()
        writeEnds = [toChild.fileHandleForWriting, fromChild.fileHandleForWriting]
        let host = SettingsProcessHost(
            app: SettingsProcessHost.AppSide(
                reloadSettings: {},
                openInApp: { _ in },
                pageChanged: { _ in },
                checkForUpdates: {},
                quit: {},
                updatesState: { .updatesState(canCheck: false, lastCheck: nil) },
                features: [app.link(tools: tools, moveMonitor: moveMonitor).feature]
            ),
            isEnabled: { true },
            launch: { _, _ in
                SettingsProcessHost.Child(
                    processIdentifier: -1,
                    isRunning: { true },
                    fromChild: fromChild.fileHandleForReading,
                    toChild: toChild.fileHandleForWriting
                )
            }
        )
        app.send = { [weak host] in host?.send(status: $0, payload: $1) }
        #expect(host.show(pane: "Tools", simpleMode: false))
        let navigation = AppNavigationState()
        navigation.settingsNavigationIdentifier = .tools
        let session = SettingsProcessSession(
            navigationState: navigation,
            side: SettingsProcessSession.ProcessSide(
                reloadSettings: {},
                showSettings: {},
                updatesStateChanged: { _, _ in },
                terminate: {},
                features: [childFeature()]
            )
        )
        session.start(input: toChild.fileHandleForReading, output: fromChild.fileHandleForWriting, onClose: {})
        self.host = host
        self.session = session
        return SettingsRemote { [weak session] in session?.send($0) }
    }

    private func perform(_ task: ToolsTask) async throws -> [ToolsTaskEvent] {
        var events = [ToolsTaskEvent]()
        try await app.performer.perform(task) { events.append($0) }
        return events
    }

    // MARK: Payloads

    @Test("Every task, answer, status and move list survives the link")
    func payloads() throws {
        let file = URL(fileURLWithPath: "/tmp/Thaw Items.json")
        let tasks: [ToolsTask] = [.run(.resetSettings), .run(.enterReducedMode), .openRecovery, .writeItemList, .restoreBackup(file)]
        for task in tasks {
            let request = ToolsTaskRequest(id: UUID(), task: task)
            let data = try #require(SettingsLinkPayload.encode(request))
            #expect(SettingsLinkPayload.decode(ToolsTaskRequest.self, from: data) == request)
        }
        let events: [ToolsTaskEvent] = [.message("Done."), .restored(written: 2, skipped: 1), .itemList(file), .finished, .failed("No.")]
        for event in events {
            let answer = ToolsTaskAnswer(request: UUID(), event: event)
            let data = try #require(SettingsLinkPayload.encode(answer))
            #expect(SettingsLinkPayload.decode(ToolsTaskAnswer.self, from: data) == answer)
        }
        let status = ToolsAppStatus(logFile: file, logFileName: "thaw.log", sampleDirectory: file, hasCaptureSamples: true, isLayoutTableUnreadable: true)
        let statusData = try #require(SettingsLinkPayload.encode(status))
        #expect(SettingsLinkPayload.decode(ToolsAppStatus.self, from: statusData) == status)

        moveMonitor.recordStoreMove(item: "Clock", destination: "Hidden", satisfied: true)
        moveMonitor.recordStoreUnavailable()
        let movesData = try #require(SettingsLinkPayload.encode(moveMonitor.snapshot))
        let moves = try #require(SettingsLinkPayload.decode(MovePipelineMonitor.Snapshot.self, from: movesData))
        #expect(moves.storeMoveCount == 1 && moves.sawStoreUnavailable)
        #expect(moves.records.map(\.id) == moveMonitor.records.map(\.id), "a move keeps its identity, so the list doesn't redraw whole")
        #expect(moves.records.first?.itemDescription == "Clock")
    }

    @Test("A monitor shows the moves it is handed, capped like its own")
    func monitorShowsAnotherProcessMoves() {
        for index in 0 ..< 30 {
            moveMonitor.recordStoreMove(item: "Item \(index)", destination: "Hidden", satisfied: true)
        }
        var snapshot = moveMonitor.snapshot
        snapshot.records += snapshot.records
        let mirror = MovePipelineMonitor()
        mirror.show(snapshot)
        #expect(mirror.storeMoveCount == 30)
        #expect(mirror.records.count == 25)
        #expect(mirror.records.first?.itemDescription == "Item 29")
    }

    // MARK: The tasks in the app

    @Test("Each tool takes the steps it took on the page, and says the same")
    func toolsTakeTheirSteps() async throws {
        #expect(try await perform(.run(.resetSettings)) == [.message("Settings were reset to defaults.")])
        #expect(app.steps == ["resetSettings"])

        app.steps = []
        app.tableMissing = 2
        let rebuilt = try await perform(.run(.resetMenuBarLayoutPositions))
        #expect(rebuilt == [.message("macOS's saved layout was deleted. Backup saved as Backup 1. Relaunching…")])
        #expect(app.steps == ["wait", "rebuild", "forget", "pause", "pause", "relaunch"], "it relaunches once the new table exists")

        app.steps = []
        app.backupName = nil
        #expect(try await perform(.run(.resetMenuBarLayoutPositions)) == [.message("macOS's saved layout was deleted. Relaunching…")])

        app.steps = []
        #expect(try await perform(.run(.restartMenuBar)) == [.message("The menu bar was restarted. Relaunching…")])
        #expect(app.steps == ["wait", "restartMenuBar", "relaunch"])

        app.steps = []
        #expect(try await perform(.run(.resetPermissions)) == [.message("Permissions cleared. Quitting…")])
        #expect(app.steps == ["resetPermissions", "quit"])

        app.steps = []
        #expect(try await perform(.run(.enterReducedMode)).isEmpty)
        #expect(app.steps == ["reducedMode", "relaunch"])
    }

    @Test("A tool that fails stops there and does not relaunch")
    func failedToolStops() async {
        app.fails = true
        await #expect(throws: FakeApp.Refused.self) {
            _ = try await self.perform(.run(.resetMenuBarLayoutPositions))
        }
        #expect(app.steps == ["wait", "rebuild"])
    }

    @Test("Recovery, the item list and a restore each reach their step")
    func otherTasks() async throws {
        #expect(try await perform(.openRecovery).isEmpty)
        #expect(try await perform(.writeItemList) == [.itemList(URL(fileURLWithPath: "/tmp/item-dump-1.json"))])
        #expect(try await perform(.restoreBackup(URL(fileURLWithPath: "/tmp/Backup 2"))) == [.restored(written: 3, skipped: 1)])
        #expect(app.steps == ["openRecovery", "writeItemList", "wait", "restore Backup 2"], "a restore waits for moves to end first")
    }

    // MARK: The app's side

    private func appStatus(_ feature: SettingsAppFeature) -> ToolsAppStatus? {
        feature.statuses[ToolsLink.status]?().flatMap { SettingsLinkPayload.decode(ToolsAppStatus.self, from: $0) }
    }

    @Test("The app's status names its log file, its samples and whether it can read the layout table")
    func appStatus() throws {
        let feature = app.link(tools: tools, moveMonitor: moveMonitor).feature
        app.newestLogFile = URL(fileURLWithPath: "/tmp/logs/older.log")
        var status = try #require(appStatus(feature))
        #expect(status.logFile == nil)
        #expect(status.logFileName == "older.log", "with no file open the page names the newest one, as it does in the app")
        #expect(status.sampleDirectory == app.sampleDirectory)
        #expect(!status.hasCaptureSamples && !status.isLayoutTableUnreadable)

        app.logFile = URL(fileURLWithPath: "/tmp/logs/current.log")
        app.isTableUnreadable = true
        try FileManager.default.createDirectory(at: app.sampleDirectory, withIntermediateDirectories: true)
        try Data().write(to: app.sampleDirectory.appending(path: "crop-1.png"))
        status = try #require(appStatus(feature))
        #expect(status.logFile == app.logFile)
        #expect(status.logFileName == "current.log")
        #expect(status.hasCaptureSamples && status.isLayoutTableUnreadable)
    }

    @Test("Moves are sent only while detailed logging is on, when the page lists them")
    func movesFollowLogging() throws {
        let feature = app.link(tools: tools, moveMonitor: moveMonitor).feature
        moveMonitor.recordStoreMove(item: "Clock", destination: "Hidden", satisfied: false)
        tools.enableDiagnosticLogging = false
        #expect(feature.statuses[ToolsLink.moves]?() == nil)
        tools.enableDiagnosticLogging = true
        let data = try #require(feature.statuses[ToolsLink.moves]?())
        #expect(SettingsLinkPayload.decode(MovePipelineMonitor.Snapshot.self, from: data) == moveMonitor.snapshot)
    }

    @Test("The app runs the tasks it is asked for one after another and answers each under its number")
    func appAnswersTasks() async throws {
        let feature = app.link(tools: tools, moveMonitor: moveMonitor).feature
        let run = try #require(feature.commands[ToolsLink.perform])
        let first = ToolsTaskRequest(id: UUID(), task: .run(.restartMenuBar))
        let second = ToolsTaskRequest(id: UUID(), task: .run(.resetMenuBarLayoutPositions))
        app.fails = true
        app.holdsFirstWait = true
        try run(#require(SettingsLinkPayload.encode(first)))
        try run(#require(SettingsLinkPayload.encode(second)))
        run(Data("not a task".utf8))
        #expect(await settingsLinkWait { app.heldWait != nil })
        await mainActorQueueDrained()
        #expect(app.steps == ["wait"], "the second task waits while the first is held")
        app.heldWait?.resume()
        app.heldWait = nil
        #expect(await settingsLinkWait { app.answers.count == 3 })
        #expect(app.answers == [
            ToolsTaskAnswer(request: first.id, event: .message("The menu bar was restarted. Relaunching…")),
            ToolsTaskAnswer(request: first.id, event: .finished),
            ToolsTaskAnswer(request: second.id, event: .failed("The menu bar refused.")),
        ])
        #expect(app.steps == ["wait", "restartMenuBar", "relaunch", "wait", "rebuild"])

        app.steps = []
        feature.commands[ToolsLink.relaunch]?(Data())
        #expect(app.steps == ["relaunch"])
    }

    @Test("The app follows its capture samples from when the page comes up until the settings process ends")
    func appFollowsSamples() async throws {
        let feature = app.link(tools: tools, moveMonitor: moveMonitor).feature
        let refresh = try #require(feature.commands[ToolsLink.refresh])
        func watchStatus() {
            withObservationTracking {
                _ = feature.statuses[ToolsLink.status]?()
            } onChange: { [app] in
                Task { @MainActor in app.statusChanges += 1 }
            }
        }
        watchStatus()
        refresh(Data())
        #expect(await settingsLinkWait { app.statusChanges == 1 }, "the page coming up has the app look at its status again")
        watchStatus()
        #expect(await settingsLinkWait {
            NotificationCenter.default.post(name: app.sampleWritten, object: nil)
            return app.statusChanges == 2
        })
        feature.processEnded()
        watchStatus()
        refresh(Data())
        #expect(await settingsLinkWait { app.statusChanges == 3 })
    }

    // MARK: The settings process's side

    @Test("The page takes the app's status, moves and answers, and ignores what it can't read")
    func childTakesWhatTheAppSends() throws {
        let feature = childFeature()
        let log = URL(fileURLWithPath: "/tmp/logs/current.log")
        let status = ToolsAppStatus(logFile: log, logFileName: "current.log", sampleDirectory: app.sampleDirectory, hasCaptureSamples: true)
        try feature.statuses[ToolsLink.status]?(#require(SettingsLinkPayload.encode(status)))
        #expect(report.status == status)
        #expect(followedLogs == [log], "this process appends to the file the app has open")

        moveMonitor.recordStoreMove(item: "Clock", destination: "Hidden", satisfied: true)
        try feature.statuses[ToolsLink.moves]?(#require(SettingsLinkPayload.encode(moveMonitor.snapshot)))
        #expect(child.itemManager.moveMonitor.snapshot == moveMonitor.snapshot)

        for topic in [ToolsLink.status, ToolsLink.moves, ToolsLink.answer] {
            feature.statuses[topic]?(Data("garbage".utf8))
        }
        #expect(report.status == status)
        #expect(followedLogs.count == 1)
        try feature.statuses[ToolsLink.answer]?(#require(SettingsLinkPayload.encode(ToolsTaskAnswer(request: UUID(), event: .finished))))
    }

    @Test("A task asked of the app reports what the app says and ends as the app's did")
    func taskWaitsForTheApp() async throws {
        let feature = childFeature()
        let answer = try #require(feature.statuses[ToolsLink.answer])
        let remote = recordingRemote()
        var events = [ToolsTaskEvent]()
        let finished = Task { @MainActor in
            try await self.report.perform(.restoreBackup(URL(fileURLWithPath: "/tmp/Backup 2")), via: remote) { events.append($0) }
        }
        #expect(await settingsLinkWait { requests.count == 1 })
        let request = try #require(requests.first)
        #expect(request.task == .restoreBackup(URL(fileURLWithPath: "/tmp/Backup 2")))
        try answer(#require(SettingsLinkPayload.encode(ToolsTaskAnswer(request: UUID(), event: .failed("Someone else's.")))))
        try answer(#require(SettingsLinkPayload.encode(ToolsTaskAnswer(request: request.id, event: .restored(written: 4, skipped: 0)))))
        try answer(#require(SettingsLinkPayload.encode(ToolsTaskAnswer(request: request.id, event: .finished))))
        try await finished.value
        #expect(events == [.restored(written: 4, skipped: 0)])

        let failing = Task { @MainActor in
            try await self.report.perform(.openRecovery, via: remote) { _ in }
        }
        #expect(await settingsLinkWait { requests.count == 2 })
        try answer(#require(SettingsLinkPayload.encode(ToolsTaskAnswer(request: requests[1].id, event: .failed("Recovery is busy.")))))
        let failure = await #expect(throws: ToolsTaskFailure.self) { try await failing.value }
        #expect(failure?.localizedDescription == "Recovery is busy.")
    }

    // MARK: Here or in the app

    @Test("In the app a task runs here; in the settings process it is sent to the app")
    func taskRunsHereOrInTheApp() async throws {
        var events = [ToolsTaskEvent]()
        try await ToolsTasks.perform(.run(.resetSettings), appState: child, remote: nil, local: { _ in self.app.performer }, report: { events.append($0) })
        #expect(app.steps == ["resetSettings"])
        #expect(events == [.message("Settings were reset to defaults.")])
        #expect(commands.isEmpty)

        app.steps = []
        let hints = FirstRunHintStore(read: { [FirstRunHint.allCases.first?.rawValue ?? ""] }, write: { _ in }, onFirstHide: {})
        child.settings.general.lastCustomThawIcon = ControlItemImageSet.userSelectableThawIcons.first
        ToolsTasks.forgetWhatResetCleared(in: child.settings, hints: hints)
        #expect(child.settings.general.lastCustomThawIcon == nil && hints.dismissed.isEmpty)

        let remote = recordingRemote()
        child.settings.general.lastCustomThawIcon = ControlItemImageSet.userSelectableThawIcons.first
        let asked = Task { @MainActor in
            try await ToolsTasks.perform(.run(.resetSettings), appState: self.child, remote: remote, local: { _ in self.app.performer })
        }
        #expect(await settingsLinkWait { requests.count == 1 })
        #expect(app.steps.isEmpty, "the settings process resets nothing itself")
        report.received(ToolsTaskAnswer(request: requests[0].id, event: .finished))
        try await asked.value
        #expect(child.settings.general.lastCustomThawIcon == nil, "what this process only keeps in memory goes once the app has reset")

        var relaunchedHere = 0
        ToolsTasks.relaunch(child, remote: nil, local: { _ in relaunchedHere += 1 })
        #expect(relaunchedHere == 1 && commands.count == 1)
        ToolsTasks.relaunch(child, remote: remote, local: { _ in relaunchedHere += 1 })
        #expect(relaunchedHere == 1)
        #expect(commands.last == .command(name: ToolsLink.relaunch, payload: Data()))
    }

    @Test("In the settings process the files section has the app write the item list, copies it itself and shows the app's samples")
    func filesSection() async throws {
        #expect(DiagnosticFilesSection.current(child, remote: nil).appReport == nil)
        let section = DiagnosticFilesSection.current(child, remote: recordingRemote())
        #expect(section.appReport === report)

        let folder = FileManager.default.temporaryDirectory.appending(path: "SettingsLinkToolsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let written = folder.appending(path: "item-dump-1.json")
        let chosen = folder.appending(path: "Items.json")
        try Data("{}".utf8).write(to: written)

        let saved = Task { @MainActor in try await section.actions.saveItemList(chosen) }
        #expect(await settingsLinkWait { requests.count == 1 })
        #expect(requests[0].task == .writeItemList)
        report.received(ToolsTaskAnswer(request: requests[0].id, event: .itemList(written)))
        report.received(ToolsTaskAnswer(request: requests[0].id, event: .finished))
        try await saved.value
        #expect(try Data(contentsOf: chosen) == Data("{}".utf8))

        let refused = Task { @MainActor in try await section.actions.saveItemList(chosen) }
        #expect(await settingsLinkWait { requests.count == 2 })
        report.received(ToolsTaskAnswer(request: requests[1].id, event: .failed("No Accessibility.")))
        await #expect(throws: ToolsTaskFailure(message: "No Accessibility.")) { try await refused.value }

        let silent = Task { @MainActor in try await section.actions.saveItemList(chosen) }
        #expect(await settingsLinkWait { requests.count == 3 })
        report.received(ToolsTaskAnswer(request: requests[2].id, event: .finished))
        await #expect(throws: CocoaError.self) { try await silent.value }
    }

    @Test("Shown in the settings process, the page names the app's log file, has the app look again and warns as the app would")
    func pageInTheSettingsProcess() async {
        let settings = child.settings.tools
        settings.setLogEnabled = { _ in }
        settings.sendRotationPolicy = { _ in }
        settings.enableDiagnosticLogging = true
        report.show(ToolsAppStatus(logFileName: "the-apps.log", sampleDirectory: app.sampleDirectory, isLayoutTableUnreadable: true))
        let remote = recordingRemote()
        let size = CGSize(width: 760, height: 1600)
        func page(_ view: some View) -> OffscreenRender<AnyView> {
            OffscreenRender(
                AnyView(view.environment(child).environment(\.settingsPaneTitle, nil).frame(width: size.width, height: size.height)),
                size: size
            )
        }

        let pane = page(ToolsSettingsPane(settings: settings, remote: remote))
        #expect(await pane.settle { pane.texts().contains { $0.contains("the-apps.log") } })
        #expect(commands.contains(.command(name: ToolsLink.refresh, payload: Data())))

        let backups = page(ThawForm { MenuBarLayoutBackupsSection(refreshToken: 0, remote: remote) })
        #expect(await backups.settle { backups.texts().contains { $0.contains("Backups can't include") } })
        report.show(ToolsAppStatus(sampleDirectory: app.sampleDirectory))
        #expect(await backups.settle { !backups.texts().contains { $0.contains("Backups can't include") } })
    }

    @Test("Only the app changes the log when a setting changes")
    func onlyTheAppChangesTheLog() {
        var changes = [Bool]()
        ToolsSettings.logChange(isSettingsProcess: true) { changes.append($0) }(true)
        #expect(changes.isEmpty, "the settings process appends to the app's file and never opens, rotates or prunes one")
        ToolsSettings.logChange(isSettingsProcess: false) { changes.append($0) }(true)
        #expect(changes == [true])

        var switched = 0
        tools.setLogEnabled = { _ in switched += 1 }
        tools.enableDiagnosticLogging.toggle()
        #expect(switched == 1)
    }

    @Test("Troubleshooting runs in the settings process, with its share of the link on both sides")
    func route() {
        #expect(SettingsProcessRoute.ownProcessPanes.contains(SettingsNavigationIdentifier.tools.rawValue))
        #expect(SettingsLinkFeatures.app(child).contains { $0.commands[ToolsLink.perform] != nil && $0.statuses[ToolsLink.status] != nil })
        #expect(SettingsLinkFeatures.child(child).contains { $0.statuses[ToolsLink.answer] != nil })
        // Building the live steps takes none of them.
        _ = ToolsTaskPerformer.live(child)
    }

    // MARK: Both sides, joined

    @Test("Over the link the page mirrors the app's state and its tasks run in the app")
    func overTheLink() async throws {
        app.logFile = URL(fileURLWithPath: "/tmp/logs/current.log")
        tools.enableDiagnosticLogging = true
        moveMonitor.recordStoreMove(item: "Clock", destination: "Hidden", satisfied: true)
        let remote = connect()
        #expect(await settingsLinkWait { report.status.logFileName == "current.log" })
        #expect(followedLogs.last == app.logFile)
        #expect(await settingsLinkWait { child.itemManager.moveMonitor.records.count == 1 })

        moveMonitor.recordStoreMove(item: "Wi-Fi", destination: "Visible", satisfied: false)
        #expect(await settingsLinkWait { child.itemManager.moveMonitor.snapshot == moveMonitor.snapshot })

        var events = [ToolsTaskEvent]()
        try await ToolsTasks.perform(.run(.restartMenuBar), appState: child, remote: remote, report: { events.append($0) })
        #expect(events == [.message("The menu bar was restarted. Relaunching…")])
        #expect(app.steps == ["wait", "restartMenuBar", "relaunch"])

        app.fails = true
        await #expect(throws: ToolsTaskFailure(message: "The menu bar refused.")) {
            try await ToolsTasks.perform(.run(.resetMenuBarLayoutPositions), appState: self.child, remote: remote)
        }

        // Once the page is up the app follows its capture samples, which nothing observable holds.
        remote.perform(ToolsLink.refresh)
        try FileManager.default.createDirectory(at: app.sampleDirectory, withIntermediateDirectories: true)
        try Data().write(to: app.sampleDirectory.appending(path: "crop-1.png"))
        #expect(await settingsLinkWait {
            NotificationCenter.default.post(name: app.sampleWritten, object: nil)
            return report.status.hasCaptureSamples
        })

        ToolsTasks.relaunch(child, remote: remote)
        #expect(await settingsLinkWait { app.steps.last == "relaunch" })
    }
}
