//
//  SpaceMenuBarKeeper.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

/// Remembers the Spaces page's choices and sends them to the menu bar agent
/// again at launch, for each new Space and after the agent restarts.
@MainActor
@Observable
final class SpaceMenuBarKeeper {
    private(set) var choices: SpaceMenuBarChoices

    @ObservationIgnored private let load: () -> SpaceMenuBarChoices?
    @ObservationIgnored private let save: (SpaceMenuBarChoices) -> Void
    @ObservationIgnored private let presentation: () -> any MenuBarPresentationControlling
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// Changes to Spaces the directory didn't list yet, applied once it does.
    @ObservationIgnored private var pending: [UInt64: [PendingChange]] = [:]

    private enum PendingChange {
        case update((inout SpaceMenuBarChoice) -> Void)
        case forget
    }

    private static nonisolated let diagLog = DiagLog(category: "SpaceMenuBarKeeper")

    init(
        load: @escaping () -> SpaceMenuBarChoices? = loadFromDefaults,
        save: @escaping (SpaceMenuBarChoices) -> Void = saveToDefaults,
        presentation: @escaping () -> any MenuBarPresentationControlling = { MenuBarPresentationProvider.current }
    ) {
        choices = load() ?? SpaceMenuBarChoices()
        self.load = load
        self.save = save
        self.presentation = presentation
    }

    /// Re-applies everything now, then each new Space from directory and everything after each agent restart.
    func start(directory: SpaceDirectory, agentRestarts: AsyncStream<Void>) {
        stop()
        tasks.append(Task { [weak self, directory] in
            var previous = directory.spaces
            await self?.reapply(.everything, spaces: previous)
            for await spaces in Observations({ directory.spaces }) {
                self?.resolvePending(in: spaces)
                let keys = SpaceMenuBarReapply.newKeys(from: previous, to: spaces)
                previous = spaces
                if !keys.isEmpty {
                    await self?.reapply(.spaces(keys), spaces: spaces)
                }
            }
        })
        tasks.append(Task { [weak self, directory] in
            for await _ in agentRestarts {
                await self?.reapply(.everything, spaces: directory.spaces)
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// Sends the stored choices that scope covers. Returns the requests macOS accepted.
    @discardableResult
    func reapply(_ scope: SpaceMenuBarReapply.Scope, spaces: [Bridging.ManagedSpace]) async -> [SpaceMenuBarRequest] {
        reload()
        return await send(SpaceMenuBarReapply.requests(for: choices, spaces: spaces, scope: scope))
    }

    /// Undoes the stored choices in the menu bar agent, then forgets them.
    func resetAll(spaces: [Bridging.ManagedSpace]) async {
        reload()
        let requests = SpaceMenuBarReapply.resetRequests(for: choices, spaces: spaces)
        removeAll()
        await send(requests)
    }

    @discardableResult
    private func send(_ requests: [SpaceMenuBarRequest]) async -> [SpaceMenuBarRequest] {
        var accepted: [SpaceMenuBarRequest] = []
        for request in requests {
            if await send(request) {
                accepted.append(request)
            } else {
                Self.diagLog.warning("The menu bar agent declined a stored Space choice: \(request)")
            }
        }
        return accepted
    }

    private func send(_ request: SpaceMenuBarRequest) async -> Bool {
        let presentation = presentation()
        return switch request {
        case .hiddenEverywhere:
            await presentation.setSystemMenuBarHidden(true)
        case .fullScreenAppearanceEverywhere:
            await presentation.setFullScreenAppearanceOnUserSpace(true)
        case let .hidden(spaceID):
            await presentation.setSystemMenuBarHidden(true, spaceID: spaceID)
        case let .autoShowDisabled(spaceID):
            await presentation.setSystemMenuBarAutoShowDisabled(true, spaceID: spaceID)
        case let .revealStripHeight(height, spaceID):
            await presentation.setSystemMenuBarAutohideHeight(height, spaceID: spaceID)
        case .shownEverywhere:
            await presentation.setSystemMenuBarHidden(false)
        case .standardAppearanceEverywhere:
            await presentation.setFullScreenAppearanceOnUserSpace(false)
        case let .clearOverrides(spaceID):
            await presentation.clearSystemMenuBarOverrides(forSpace: spaceID)
        }
    }

    // MARK: Recording

    /// The stored choice for the Space with spaceID, or the defaults when it has none or isn't listed.
    func choice(forSpaceID spaceID: UInt64, in spaces: [Bridging.ManagedSpace]) -> SpaceMenuBarChoice {
        SpaceMenuBarReapply.key(forSpaceID: spaceID, in: spaces).map(choices.choice(forKey:)) ?? SpaceMenuBarChoice()
    }

    /// Stores a choice macOS accepted for the Space with spaceID. A Space not
    /// listed yet keeps the change until the directory lists it.
    func record(spaceID: UInt64, in spaces: [Bridging.ManagedSpace], _ change: @escaping (inout SpaceMenuBarChoice) -> Void) {
        guard let key = SpaceMenuBarReapply.key(forSpaceID: spaceID, in: spaces) else {
            hold(.update(change), forSpaceID: spaceID)
            return
        }
        update { $0.update(key: key, change) }
    }

    /// Drops what was stored for the Space with spaceID, as Reset This Space does.
    func forget(spaceID: UInt64, in spaces: [Bridging.ManagedSpace]) {
        guard let key = SpaceMenuBarReapply.key(forSpaceID: spaceID, in: spaces) else {
            hold(.forget, forSpaceID: spaceID)
            return
        }
        update { $0.spaces[key] = nil }
    }

    /// Whether a change waits for its Space to be listed.
    var hasPendingChanges: Bool {
        !pending.isEmpty
    }

    private func hold(_ change: PendingChange, forSpaceID spaceID: UInt64) {
        guard spaceID != 0 else { return }
        Self.diagLog.debug("Space \(spaceID) isn't listed yet; keeping its choice until it is")
        pending[spaceID, default: []].append(change)
    }

    /// Stores the held changes whose Space spaces now lists.
    func resolvePending(in spaces: [Bridging.ManagedSpace]) {
        for (spaceID, changes) in pending {
            guard let key = SpaceMenuBarReapply.key(forSpaceID: spaceID, in: spaces) else { continue }
            pending[spaceID] = nil
            update { choices in
                for change in changes {
                    switch change {
                    case let .update(apply): choices.update(key: key, apply)
                    case .forget: choices.spaces[key] = nil
                    }
                }
            }
        }
    }

    func recordHiddenEverywhere(_ hidden: Bool) {
        update { $0.isHiddenEverywhere = hidden }
    }

    func recordFullScreenAppearanceEverywhere(_ enabled: Bool) {
        update { $0.usesFullScreenAppearanceEverywhere = enabled }
    }

    func removeAll() {
        update { $0 = SpaceMenuBarChoices() }
    }

    /// The settings window can run in its own process and save there, so stored data wins over memory.
    private func reload() {
        let stored = load() ?? SpaceMenuBarChoices()
        if stored != choices {
            choices = stored
        }
    }

    private func update(_ change: (inout SpaceMenuBarChoices) -> Void) {
        reload()
        var next = choices
        change(&next)
        guard next != choices else { return }
        choices = next
        save(next)
    }
}

extension SpaceMenuBarKeeper {
    static nonisolated func loadFromDefaults() -> SpaceMenuBarChoices? {
        guard let data = Defaults.data(forKey: .spaceMenuBarChoices) else { return nil }
        do {
            return try JSONDecoder().decode(SpaceMenuBarChoices.self, from: data)
        } catch {
            diagLog.error("Error decoding the Spaces page choices: \(error)")
            return nil
        }
    }

    static nonisolated func saveToDefaults(_ choices: SpaceMenuBarChoices) {
        do {
            try Defaults.set(JSONEncoder().encode(choices), forKey: .spaceMenuBarChoices)
        } catch {
            diagLog.error("Error encoding the Spaces page choices: \(error)")
        }
    }

    /// Each time MenuBarAgent comes back with a new process, as launchd restarts it.
    static func liveAgentRestarts() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        var detector = MenuBarAgentRestartDetector()
        let observation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) { workspace, _ in
            let pids = Set(workspace.runningApplications.filter { $0.bundleIdentifier == SharedConstants.menuBarHostingBundleID }.map(\.processIdentifier))
            if detector.observe(pids) {
                continuation.yield()
            }
        }
        continuation.onTermination = { _ in observation.invalidate() }
        return stream
    }
}
