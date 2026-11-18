//
//  SettingsLinkFeature.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// One page's share of the link on the app's side: the live state it sends, the commands it runs
/// and what it reads again. A page that runs in the settings process adds one to SettingsLinkFeatures.
@MainActor
struct SettingsAppFeature {
    /// Each topic's current payload. It is read inside an observation, so a change to anything
    /// observable it reads is sent too. Nil sends nothing.
    var statuses: [String: () -> Data?] = [:]
    /// What the app does with each command's payload.
    var commands: [String: (Data) -> Void] = [:]
    /// What the app answers each request with. Throwing sends the error's words back instead.
    var requests: [String: (Data) async throws -> Data] = [:]
    /// Runs after the settings process wrote the defaults, once AppSettings has been read again.
    var reload: () -> Void = {
        // Most pages keep everything in AppSettings.
    }

    /// Reads a store kept outside the defaults again, by its name.
    var stores: [String: () -> Void] = [:]
    /// Runs when the settings process has ended, however it ended, to undo what only lasts while it runs.
    var processEnded: () -> Void = {
        // Most pages leave nothing behind.
    }
}

/// The same page's share in the settings process: what it does with the app's state, and what it reads again.
@MainActor
struct SettingsChildFeature {
    /// What the page does with each topic's payload from the app.
    var statuses: [String: (Data) -> Void] = [:]
    /// Runs after the app wrote the defaults, once AppSettings has been read again.
    var reload: () -> Void = {
        // Most pages keep everything in AppSettings.
    }

    /// Reads a store kept outside the defaults again, by its name.
    var stores: [String: () -> Void] = [:]
}

/// The JSON a status or a command carries.
nonisolated enum SettingsLinkPayload {
    /// Keys are sorted, so the same value always encodes to the same bytes and the host can
    /// tell a status it has already sent.
    static func encode(_ value: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(value)
    }

    static func decode<Value: Decodable>(_: Value.Type = Value.self, from data: Data) -> Value? {
        try? JSONDecoder().decode(Value.self, from: data)
    }
}

/// In the settings process, how a page reaches the running app, which has the menu bar engine.
/// Nil in the app itself, where a page acts on the engine directly.
@MainActor
final class SettingsRemote {
    /// Set once by the settings process as it starts.
    static var current: SettingsRemote?

    private let send: (SettingsLinkMessage) -> Void
    /// The requests the app has not answered yet.
    private var waiting = [UUID: CheckedContinuation<Data, any Error>]()

    init(send: @escaping (SettingsLinkMessage) -> Void) {
        self.send = send
    }

    /// Has the app run a command that a SettingsAppFeature registered under this name.
    func perform(_ name: String, _ payload: some Encodable) {
        guard let data = SettingsLinkPayload.encode(payload) else { return }
        send(.command(name: name, payload: data))
    }

    /// A command that needs nothing but its name.
    func perform(_ name: String) {
        send(.command(name: name, payload: Data()))
    }

    /// Tells the app this process saved a store kept outside the defaults.
    func saved(store: String) {
        send(.storeChanged(store: store))
    }

    /// Asks the app and returns its answer. Throws the app's error, or noAnswer once patience runs out.
    func request<Answer: Decodable>(
        _ name: String, _ payload: some Encodable, patience: Duration = SettingsRequestError.patience
    ) async throws -> Answer {
        guard let data = SettingsLinkPayload.encode(payload) else { throw SettingsRequestError.unreadable }
        let id = UUID()
        let giveUp = Task { [weak self] in
            guard (try? await Task.sleep(for: patience)) != nil else { return }
            self?.waiting.removeValue(forKey: id)?.resume(throwing: SettingsRequestError.noAnswer)
        }
        defer { giveUp.cancel() }
        let answer = try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            send(.request(id: id, name: name, payload: data))
        }
        guard let decoded = SettingsLinkPayload.decode(Answer.self, from: answer) else { throw SettingsRequestError.unreadable }
        return decoded
    }

    /// Takes the app's reply. One for a request that is no longer waiting is dropped.
    func answered(id: UUID, payload: Data?, failure: String?) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        if let payload, failure == nil {
            continuation.resume(returning: payload)
        } else {
            continuation.resume(throwing: SettingsRequestError.failed(failure ?? ""))
        }
    }
}

/// Why a request to the app gave no answer to use.
nonisolated enum SettingsRequestError: LocalizedError, Equatable {
    /// The app ran the request and it failed, with the app's words for why.
    case failed(String)
    /// The app did not answer in time.
    case noAnswer
    /// The request or its answer could not be encoded or decoded.
    case unreadable

    /// How long a request waits. The app answers in well under a second unless it is waiting on the menu bar.
    static let patience = Duration.seconds(30)

    var errorDescription: String? {
        switch self {
        case let .failed(words): words
        case .noAnswer: String(localized: "\(Constants.displayName) didn't answer. Try again.")
        case .unreadable: String(localized: "\(Constants.displayName) and its Settings window didn't understand each other.")
        }
    }
}

/// Every page's share of the link. A page that moves to the settings process adds its pane to
/// SettingsProcessRoute.ownProcessPanes and one entry to each list here.
@MainActor
enum SettingsLinkFeatures {
    /// What the app sends, runs and reads again for the pages in the settings process.
    static func app(_ appState: AppState) -> [SettingsAppFeature] {
        [
            AppearanceSettingsLink.app(appState),
            .modules(host: appState.moduleHost, profiles: appState.profilesFeature),
            DisplaysSettingsLink.app(appState),
            .tools(appState),
            .items(appState),
            ThawBarSettingsLink.app(appState),
            .hotkeys(appState),
            ProfilesLink.app(appState),
            OnboardingLink.app(appState),
        ]
    }

    /// What the settings process does with what the app sends.
    static func child(_ appState: AppState) -> [SettingsChildFeature] {
        [
            AppearanceSettingsLink.child(appState),
            .modules(host: appState.moduleHost, profiles: appState.profilesFeature),
            DisplaysSettingsLink.child(appState),
            .tools(appState),
            .items(appState),
            ThawBarSettingsLink.child(appState),
            .hotkeys(appState),
            .triggers(appState),
            ProfilesLink.child(profiles: appState.profileManager),
        ]
    }
}
