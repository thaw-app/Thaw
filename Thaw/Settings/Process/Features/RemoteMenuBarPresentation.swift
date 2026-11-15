//
//  RemoteMenuBarPresentation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel
import Observation

/// The Spaces controls' way to the menu bar agent from the settings process.
/// The agent drops a process's overrides when that process ends, so each request goes to the app's session.
@MainActor
@Observable
final class RemoteMenuBarPresentation: MenuBarPresentationControlling {
    /// One request, named after the method that makes it.
    enum Request: Codable, Equatable {
        case reveal
        case hidden(Bool)
        case autoShowEnabled(Bool)
        case hiddenInSpace(Bool, spaceID: UInt64)
        case autoShowDisabledInSpace(Bool, spaceID: UInt64)
        case autohideHeight(Double, spaceID: UInt64)
        case clearOverrides(spaceID: UInt64)
        case fullScreenAppearance(Bool)
    }

    /// A request with the number its answer comes back under.
    struct Call: Codable, Equatable {
        var id: Int
        var request: Request
    }

    struct Answer: Codable, Equatable {
        var id: Int
        var succeeded: Bool
    }

    /// The settings process's own, which sends through SettingsRemote.
    static let shared = RemoteMenuBarPresentation { SettingsRemote.current?.perform(DisplaysSettingsLink.presentation, $0) }

    /// Whether the app's session can make these requests, as the app last said.
    var isSupported = false

    @ObservationIgnored private let send: (Call) -> Void
    @ObservationIgnored private let patience: Duration
    @ObservationIgnored private var waiting: [Int: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var calls = 0

    /// A call the app hasn't answered after patience counts as declined.
    init(patience: Duration = .seconds(10), send: @escaping (Call) -> Void) {
        self.patience = patience
        self.send = send
    }

    /// Takes the app's answer to a call. An answer to a call that is no longer waiting is dropped.
    func answer(_ answer: Answer) {
        waiting.removeValue(forKey: answer.id)?.resume(returning: answer.succeeded)
    }

    private func ask(_ request: Request) async -> Bool {
        calls += 1
        let id = calls
        // Without an answer the control would stay as it was set, as if macOS had taken the request.
        let giveUp = Task { [weak self, patience] in
            guard (try? await Task.sleep(for: patience)) != nil else { return }
            self?.answer(Answer(id: id, succeeded: false))
        }
        defer { giveUp.cancel() }
        return await withCheckedContinuation { continuation in
            waiting[id] = continuation
            send(Call(id: id, request: request))
        }
    }

    func revealSystemMenuBar() async -> Bool {
        await ask(.reveal)
    }

    func setSystemMenuBarHidden(_ hidden: Bool) async -> Bool {
        await ask(.hidden(hidden))
    }

    func setSystemMenuBarAutoShowEnabled(_ enabled: Bool) async -> Bool {
        await ask(.autoShowEnabled(enabled))
    }

    func setSystemMenuBarHidden(_ hidden: Bool, spaceID: UInt64) async -> Bool {
        await ask(.hiddenInSpace(hidden, spaceID: spaceID))
    }

    func setSystemMenuBarAutoShowDisabled(_ disabled: Bool, spaceID: UInt64) async -> Bool {
        await ask(.autoShowDisabledInSpace(disabled, spaceID: spaceID))
    }

    func setSystemMenuBarAutohideHeight(_ height: Double, spaceID: UInt64) async -> Bool {
        await ask(.autohideHeight(height, spaceID: spaceID))
    }

    func clearSystemMenuBarOverrides(forSpace spaceID: UInt64) async -> Bool {
        await ask(.clearOverrides(spaceID: spaceID))
    }

    func setFullScreenAppearanceOnUserSpace(_ enabled: Bool) async -> Bool {
        await ask(.fullScreenAppearance(enabled))
    }
}

extension RemoteMenuBarPresentation.Request {
    /// Makes the request of a session that keeps it, which is the app's.
    func send(to presentation: any MenuBarPresentationControlling) async -> Bool {
        switch self {
        case .reveal: await presentation.revealSystemMenuBar()
        case let .hidden(hidden): await presentation.setSystemMenuBarHidden(hidden)
        case let .autoShowEnabled(enabled): await presentation.setSystemMenuBarAutoShowEnabled(enabled)
        case let .hiddenInSpace(hidden, spaceID): await presentation.setSystemMenuBarHidden(hidden, spaceID: spaceID)
        case let .autoShowDisabledInSpace(disabled, spaceID): await presentation.setSystemMenuBarAutoShowDisabled(disabled, spaceID: spaceID)
        case let .autohideHeight(height, spaceID): await presentation.setSystemMenuBarAutohideHeight(height, spaceID: spaceID)
        case let .clearOverrides(spaceID): await presentation.clearSystemMenuBarOverrides(forSpace: spaceID)
        case let .fullScreenAppearance(enabled): await presentation.setFullScreenAppearanceOnUserSpace(enabled)
        }
    }
}

extension MenuBarPresentationProvider {
    /// The session the Spaces controls act through: this process's in the app, and the app's,
    /// reached over the link, when Settings runs in its own process.
    static var forSettings: any MenuBarPresentationControlling {
        SettingsRemote.current == nil ? current : RemoteMenuBarPresentation.shared
    }
}
