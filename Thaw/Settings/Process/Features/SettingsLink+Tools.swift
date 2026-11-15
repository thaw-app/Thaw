//
//  SettingsLink+Tools.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit

/// The names the Troubleshooting page uses on the link.
nonisolated enum ToolsLink {
    /// The app's recent item moves, sent while detailed logging is on.
    static let moves = "tools.moves"
    /// What else the page shows that only the app knows. See ToolsAppStatus.
    static let status = "tools.status"
    /// What a task the page asked for says, and how it ended. See ToolsTaskAnswer.
    static let answer = "tools.answer"
    /// The page came up, so the app looks at its status again.
    static let refresh = "tools.refresh"
    /// A task for the app. See ToolsTaskRequest.
    static let perform = "tools.perform"
    static let relaunch = "tools.relaunch"
}

/// What the Troubleshooting page shows that only the running app knows.
nonisolated struct ToolsAppStatus: Codable, Equatable, Sendable {
    /// The log file the app is writing, which the settings process appends to. Nil while the log is off.
    var logFile: URL?
    /// The name the page shows: that file, or the newest one when none is open.
    var logFileName: String?
    /// Where the app keeps its capture samples, a folder named after its own process.
    var sampleDirectory: URL
    var hasCaptureSamples = false
    /// Whether the app may read macOS's saved menu bar layout. Only the app holds that grant.
    var isLayoutTableUnreadable = false
}

/// A task with the number its answers come back under.
nonisolated struct ToolsTaskRequest: Codable, Equatable, Sendable {
    var id: UUID
    var task: ToolsTask
}

nonisolated struct ToolsTaskAnswer: Codable, Equatable, Sendable {
    var request: UUID
    var event: ToolsTaskEvent
}

/// A task that failed in the app, with the app's words for why.
nonisolated struct ToolsTaskFailure: LocalizedError, Equatable {
    var message: String

    var errorDescription: String? {
        message
    }
}

// MARK: - In the app

/// The Troubleshooting page's share of the link in the app: it sends what only the app knows and
/// does the tasks its settings process asks for.
@MainActor
@Observable
final class ToolsAppLink {
    /// What the link reads from the app and does in it.
    struct AppSide {
        /// Nil once the app's state has gone, when there is nothing left to act on.
        var performer: () -> ToolsTaskPerformer?
        var relaunch: () -> Void
        var openLogFile: () -> URL?
        var newestLogFile: () -> URL?
        var sampleDirectory: () -> URL
        /// Posted when a capture sample is written.
        var sampleWritten = CaptureDiagnostics.didWriteSample
        var isLayoutTableUnreadable: () -> Bool
        var send: (_ topic: String, _ payload: Data) -> Void
    }

    private let tools: ToolsSettings
    private let moveMonitor: MovePipelineMonitor
    private let app: AppSide
    /// Counts what can change the status without anything observable changing, so it is looked at again.
    private var statusRevision = 0
    @ObservationIgnored
    private var sampleWatch: Task<Void, Never>?
    @ObservationIgnored
    private var running: Task<Void, Never>?

    init(tools: ToolsSettings, moveMonitor: MovePipelineMonitor, app: AppSide) {
        self.tools = tools
        self.moveMonitor = moveMonitor
        self.app = app
    }

    var feature: SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                // At most the 25 newest moves, and only while the page lists them.
                ToolsLink.moves: { [self] in
                    tools.enableDiagnosticLogging ? SettingsLinkPayload.encode(moveMonitor.snapshot) : nil
                },
                ToolsLink.status: { [self] in SettingsLinkPayload.encode(status()) },
            ],
            commands: [
                ToolsLink.refresh: { [self] _ in refresh() },
                ToolsLink.perform: { [self] in received($0) },
                ToolsLink.relaunch: { [self] _ in app.relaunch() },
            ],
            processEnded: { [self] in
                sampleWatch?.cancel()
                sampleWatch = nil
            }
        )
    }

    private func status() -> ToolsAppStatus {
        // Any of the log settings can open, close or replace the log file.
        _ = (statusRevision, tools.enableDiagnosticLogging, tools.diagnosticLogMaxSizeMB)
        _ = (tools.diagnosticLogRetentionDays, tools.diagnosticLogRotationInterval)
        let logFile = app.openLogFile()
        let samples = app.sampleDirectory()
        return ToolsAppStatus(
            logFile: logFile,
            logFileName: (logFile ?? app.newestLogFile())?.lastPathComponent,
            sampleDirectory: samples,
            hasCaptureSamples: MaintenanceTools.hasCaptureSamples(in: samples),
            isLayoutTableUnreadable: app.isLayoutTableUnreadable()
        )
    }

    /// Looks at the status again, and from now on whenever a capture sample is written.
    private func refresh() {
        statusRevision += 1
        guard sampleWatch == nil else { return }
        let written = NotificationCenter.default.notifications(named: app.sampleWritten)
        sampleWatch = Task { @MainActor [weak self] in
            for await _ in written {
                self?.statusRevision += 1
            }
        }
    }

    private func received(_ payload: Data) {
        guard let request = SettingsLinkPayload.decode(ToolsTaskRequest.self, from: payload) else { return }
        let earlier = running
        // One task at a time, in the order asked. A task runs to its end even when the settings
        // process has gone: half a restore is worse than a whole one.
        running = Task { @MainActor [self] in
            await earlier?.value
            await run(request)
        }
    }

    private func run(_ request: ToolsTaskRequest) async {
        guard let performer = app.performer() else { return }
        do {
            try await performer.perform(request.task) { answer(request.id, $0) }
            answer(request.id, .finished)
        } catch {
            answer(request.id, .failed(error.localizedDescription))
        }
        statusRevision += 1
    }

    private func answer(_ request: UUID, _ event: ToolsTaskEvent) {
        guard let payload = SettingsLinkPayload.encode(ToolsTaskAnswer(request: request, event: event)) else { return }
        app.send(ToolsLink.answer, payload)
    }
}

extension SettingsAppFeature {
    static func tools(_ appState: AppState) -> SettingsAppFeature {
        ToolsAppLink(
            tools: appState.settings.tools,
            moveMonitor: appState.itemManager.moveMonitor,
            app: ToolsAppLink.AppSide(
                performer: { [weak appState] in appState.map(ToolsTaskPerformer.live) },
                relaunch: { [weak appState] in appState?.restartSelf() },
                openLogFile: { DiagnosticLogger.shared.currentLogFile },
                newestLogFile: { DiagnosticLogger.shared.latestLogFile },
                sampleDirectory: { CaptureDiagnostics.sampleDirectory },
                isLayoutTableUnreadable: { RuntimePreferenceStore.positionsDomainAccess() == .denied },
                send: { [weak appState] in appState?.settingsProcessHost.send(status: $0, payload: $1) }
            )
        ).feature
    }
}

// MARK: - In the settings process

/// In the settings process, what the running app says for the Troubleshooting page: the state
/// only it knows, and the answers to the tasks the page asked for.
@MainActor
@Observable
final class ToolsAppReport {
    private(set) var status = ToolsAppStatus(sampleDirectory: CaptureDiagnostics.sampleDirectory)
    @ObservationIgnored
    private var waiting = [UUID: AsyncStream<ToolsTaskEvent>.Continuation]()

    func show(_ status: ToolsAppStatus) {
        self.status = status
    }

    func received(_ answer: ToolsTaskAnswer) {
        waiting[answer.request]?.yield(answer.event)
    }

    /// Has the app run task, reports what it says and returns when it finished. Throws a
    /// ToolsTaskFailure with the app's words when it failed.
    func perform(_ task: ToolsTask, via remote: SettingsRemote, report: (ToolsTaskEvent) -> Void) async throws {
        let request = UUID()
        let (events, continuation) = AsyncStream<ToolsTaskEvent>.makeStream()
        waiting[request] = continuation
        defer { waiting[request] = nil }
        remote.perform(ToolsLink.perform, ToolsTaskRequest(id: request, task: task))
        for await event in events {
            switch event {
            case .message, .restored, .itemList: report(event)
            case .finished: return
            case let .failed(message): throw ToolsTaskFailure(message: message)
            }
        }
    }

    /// Appends this process's log lines to the file the app has open, and stops when the app's
    /// log is off. The settings process never opens a file of its own, rotates or prunes.
    static func appendToLog(_ file: URL?) {
        guard let file else {
            DiagnosticLogger.shared.isEnabled = false
            return
        }
        if DiagnosticLogger.shared.currentLogFile?.path != file.path {
            DiagnosticLogger.shared.attachToFile(at: file)
        }
    }
}

extension SettingsChildFeature {
    static func tools(
        _ appState: AppState,
        followLog: @escaping @MainActor (URL?) -> Void = ToolsAppReport.appendToLog
    ) -> SettingsChildFeature {
        let report = appState.settings.tools.appReport
        let moveMonitor = appState.itemManager.moveMonitor
        return SettingsChildFeature(statuses: [
            ToolsLink.moves: { payload in
                if let moves = SettingsLinkPayload.decode(MovePipelineMonitor.Snapshot.self, from: payload) {
                    moveMonitor.show(moves)
                }
            },
            ToolsLink.status: { payload in
                guard let status = SettingsLinkPayload.decode(ToolsAppStatus.self, from: payload) else { return }
                report.show(status)
                followLog(status.logFile)
            },
            ToolsLink.answer: { payload in
                if let answer = SettingsLinkPayload.decode(ToolsTaskAnswer.self, from: payload) {
                    report.received(answer)
                }
            },
        ])
    }
}
