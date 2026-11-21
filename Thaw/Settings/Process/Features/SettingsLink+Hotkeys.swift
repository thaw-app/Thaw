//
//  SettingsLink+Hotkeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation
import ThawUI

/// The Shortcuts page's share of the link. Only the app registers hotkeys and saves them, so the
/// settings process shows the app's bindings and sends what a recorder changes.
nonisolated enum HotkeysSettingsLink {
    /// The status with the bindings the app holds and whether it could register each.
    static let bindings = "hotkeys.bindings"
    /// The command that gives one hotkey a combination, or takes it away.
    static let assign = "hotkeys.assign"
    /// The command that says a recorder started or stopped listening for one hotkey.
    static let recording = "hotkeys.recording"
    /// The command that captures every section now, for the item shortcut list.
    static let capture = "hotkeys.capture"

    enum Kind: String, Codable {
        case action
        case item
        case profile
    }

    /// One hotkey: a built-in action by its raw value, an item by its identifier or a profile by its ID.
    struct Target: Codable, Hashable {
        var kind: Kind
        var id: String
    }

    struct Binding: Codable, Equatable {
        var combination: KeyCombination?
        /// False when the app could not claim the combination, which a recorder shows as empty.
        var isRegistered: Bool
    }

    /// The actions and items that have a combination, and every profile that has a hotkey.
    struct Bindings: Codable, Equatable {
        /// Counts the edits the settings process sent, so each is answered even when nothing changed.
        var revision = 0
        var actions = [String: Binding]()
        var items = [String: Binding]()
        var profiles = [String: Binding]()
    }

    struct Assignment: Codable, Equatable {
        var target: Target
        var combination: KeyCombination?
    }

    struct Recording: Codable, Equatable {
        var target: Target
        var isRecording: Bool
    }
}

// MARK: - In the app

/// The app's side: it finds the hotkey a target names, assigns it and stands it down for a recorder.
@MainActor
@Observable
final class SettingsHotkeysRelay {
    private typealias Link = HotkeysSettingsLink

    /// What the relay reads from the app and has it do.
    struct App {
        var actions: () -> [Hotkey]
        var items: () -> [String: Hotkey]
        var profiles: () -> [UUID: Hotkey]
        /// Saves a shortcut for an item the app has no hotkey for yet, and makes that hotkey.
        var bindItem: (String, KeyCombination?) -> Void
        var isRegistered: (Hotkey) -> Bool = { $0.isEnabled }
        /// Claims the hotkey's combination, or releases it.
        var setRegistered: (Hotkey, Bool) -> Void = { hotkey, isRegistered in
            if isRegistered {
                hotkey.enable()
            } else {
                hotkey.disable()
            }
        }
    }

    @ObservationIgnored private let app: App
    private var revision = 0
    /// The hotkeys released for a recorder in the settings process. They read as registered meanwhile.
    private var standingDown = Set<Link.Target>()

    init(app: App) {
        self.app = app
    }

    var bindings: HotkeysSettingsLink.Bindings {
        var bindings = Link.Bindings(revision: revision)
        for hotkey in app.actions() where hotkey.keyCombination != nil {
            bindings.actions[hotkey.action.rawValue] = binding(of: hotkey, .action, hotkey.action.rawValue)
        }
        for (identifier, hotkey) in app.items() where hotkey.keyCombination != nil {
            bindings.items[identifier] = binding(of: hotkey, .item, identifier)
        }
        for (id, hotkey) in app.profiles() {
            bindings.profiles[id.uuidString] = binding(of: hotkey, .profile, id.uuidString)
        }
        return bindings
    }

    /// Assigning registers the combination and saves it, as a recorder in the app does.
    func assign(_ assignment: HotkeysSettingsLink.Assignment) {
        if let hotkey = hotkey(for: assignment.target) {
            hotkey.keyCombination = assignment.combination
        } else if assignment.target.kind == .item {
            app.bindItem(assignment.target.id, assignment.combination)
        }
        revision += 1
    }

    /// Releases the hotkey while its recorder listens, so the combination being replaced can be typed.
    func setRecording(_ recording: HotkeysSettingsLink.Recording) {
        guard let hotkey = hotkey(for: recording.target) else {
            standingDown.remove(recording.target)
            return
        }
        if recording.isRecording, app.isRegistered(hotkey) {
            standingDown.insert(recording.target)
        } else {
            standingDown.remove(recording.target)
        }
        app.setRegistered(hotkey, !recording.isRecording)
    }

    /// A settings process that ended can't say its recorder stopped, so its hotkeys go back to work here.
    func processEnded() {
        for hotkey in standingDown.compactMap(hotkey(for:)) {
            app.setRegistered(hotkey, true)
        }
        standingDown = []
    }

    private func binding(of hotkey: Hotkey, _ kind: Link.Kind, _ id: String) -> Link.Binding {
        Link.Binding(
            combination: hotkey.keyCombination,
            isRegistered: app.isRegistered(hotkey) || standingDown.contains(Link.Target(kind: kind, id: id))
        )
    }

    private func hotkey(for target: Link.Target) -> Hotkey? {
        switch target.kind {
        case .action: app.actions().first { $0.action.rawValue == target.id }
        case .item: app.items()[target.id]
        case .profile: UUID(uuidString: target.id).flatMap { app.profiles()[$0] }
        }
    }
}

extension SettingsHotkeysRelay.App {
    static func live(_ appState: AppState) -> SettingsHotkeysRelay.App {
        SettingsHotkeysRelay.App(
            actions: { [weak appState] in appState?.settings.hotkeys.hotkeys ?? [] },
            items: { [weak appState] in appState?.menuBarManager.itemHotkeys ?? [:] },
            profiles: { [weak appState] in appState?.profileManager.profileHotkeys ?? [:] },
            bindItem: { [weak appState] identifier, combination in
                try? HotkeyBindingStore.items.set(combination, for: identifier)
                appState?.menuBarManager.rebuildItemHotkeys()
            }
        )
    }
}

extension SettingsAppFeature {
    static func hotkeys(_ appState: AppState) -> SettingsAppFeature {
        hotkeys(relay: SettingsHotkeysRelay(app: .live(appState))) { [weak appState] in
            Task { await appState?.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases) }
        }
    }

    static func hotkeys(relay: SettingsHotkeysRelay, capture: @escaping () -> Void) -> SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                HotkeysSettingsLink.bindings: { SettingsLinkPayload.encode(relay.bindings) },
            ],
            commands: [
                HotkeysSettingsLink.assign: { payload in
                    SettingsLinkPayload.decode(HotkeysSettingsLink.Assignment.self, from: payload).map(relay.assign)
                },
                HotkeysSettingsLink.recording: { payload in
                    SettingsLinkPayload.decode(HotkeysSettingsLink.Recording.self, from: payload).map(relay.setRecording)
                },
                HotkeysSettingsLink.capture: { _ in capture() },
            ],
            processEnded: { relay.processEnded() }
        )
    }
}

// MARK: - In the settings process

/// The settings process's side. Its hotkeys never register: they show what the app holds, and what
/// a recorder does to one goes to the app.
@MainActor
final class SettingsHotkeysMirror {
    private typealias Link = HotkeysSettingsLink

    /// The models the pages read their hotkeys from.
    struct Models {
        var actions: [Hotkey]
        /// The items that get a hotkey whether or not a shortcut is saved for them, by identifier.
        var presentItems: () -> Set<String>
        var showItems: ([String: Hotkey]) -> Void
        var showProfiles: ([UUID: Hotkey]) -> Void
    }

    private let models: Models
    private let remote: () -> SettingsRemote?
    /// The app's bindings as last sent, for the items that turn up later.
    private var bindings = Link.Bindings()
    private var items = [String: Hotkey]()
    private var profiles = [String: Hotkey]()
    /// Set while the app's bindings go into the hotkeys, so they are not sent back as edits.
    private var isAdopting = false
    private var itemWatch: Task<Void, Never>?

    init(models: Models, remote: @escaping () -> SettingsRemote? = { .current }) {
        self.models = models
        self.remote = remote
        for hotkey in models.actions {
            forward(hotkey, as: Link.Target(kind: .action, id: hotkey.action.rawValue))
        }
    }

    isolated deinit {
        itemWatch?.cancel()
    }

    func show(_ bindings: HotkeysSettingsLink.Bindings) {
        self.bindings = bindings
        isAdopting = true
        defer { isAdopting = false }
        for hotkey in models.actions {
            adopt(bindings.actions[hotkey.action.rawValue], into: hotkey)
        }
        profiles = hotkeys(.profile, for: Set(bindings.profiles.keys), keeping: profiles, bound: bindings.profiles, adoptsAll: true)
        models.showProfiles(Dictionary(
            profiles.compactMap { id, hotkey in UUID(uuidString: id).map { ($0, hotkey) } },
            uniquingKeysWith: { first, _ in first }
        ))
        showItems(adoptsAll: true)
    }

    /// Gives an item that turned up its hotkey. The others keep what they show, which may be an
    /// edit the app has yet to answer.
    func itemsChanged() {
        showItems(adoptsAll: false)
    }

    /// Follows the mirrored item list, as the app follows its own.
    func followItems(_ itemCache: @escaping () -> MenuBarItemCache?) {
        itemWatch = Task { @MainActor [weak self] in
            for await _ in Observations({ itemCache() }) {
                guard let self else { return }
                itemsChanged()
            }
        }
    }

    private func showItems(adoptsAll: Bool) {
        let wanted = models.presentItems().union(bindings.items.keys)
        items = hotkeys(.item, for: wanted, keeping: items, bound: bindings.items, adoptsAll: adoptsAll)
        models.showItems(items)
    }

    /// The hotkeys for these identifiers. One already there is kept, so its recorder keeps its hotkey.
    private func hotkeys(
        _ kind: Link.Kind,
        for identifiers: Set<String>,
        keeping current: [String: Hotkey],
        bound: [String: Link.Binding],
        adoptsAll: Bool
    ) -> [String: Hotkey] {
        var hotkeys = [String: Hotkey]()
        for identifier in identifiers {
            if let hotkey = current[identifier] {
                if adoptsAll {
                    adopt(bound[identifier], into: hotkey)
                }
                hotkeys[identifier] = hotkey
            } else {
                let hotkey = Hotkey(action: kind == .profile ? .profileApply : .openMenuBarItem)
                adopt(bound[identifier], into: hotkey)
                forward(hotkey, as: Link.Target(kind: kind, id: identifier))
                hotkeys[identifier] = hotkey
            }
        }
        return hotkeys
    }

    /// Shows what the app holds for a hotkey. One the app has no combination for reads as empty.
    private func adopt(_ binding: Link.Binding?, into hotkey: Hotkey) {
        if hotkey.keyCombination != binding?.combination {
            hotkey.keyCombination = binding?.combination
        }
        let isRegistered = binding?.isRegistered ?? false
        if hotkey.isEnabledInApp != isRegistered {
            hotkey.isEnabledInApp = isRegistered
        }
    }

    /// Has the app register and save what a recorder changes on this hotkey, and stand it down while one listens.
    private func forward(_ hotkey: Hotkey, as target: Link.Target) {
        hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
            guard let self, let hotkey, !isAdopting else { return }
            // The recorder shows the choice at once. The app answers whether it could claim it.
            hotkey.isEnabledInApp = hotkey.keyCombination != nil
            remote()?.perform(Link.assign, Link.Assignment(target: target, combination: hotkey.keyCombination))
        }
        hotkey.recordingDidChange = { [weak self] isRecording in
            self?.remote()?.perform(Link.recording, Link.Recording(target: target, isRecording: isRecording))
        }
    }
}

extension SettingsHotkeysMirror.Models {
    static func live(_ appState: AppState) -> SettingsHotkeysMirror.Models {
        SettingsHotkeysMirror.Models(
            actions: appState.settings.hotkeys.hotkeys,
            presentItems: { [weak appState] in
                // The items the app gives a hotkey; see MenuBarManager.rebuildItemHotkeys().
                let items = appState?.itemManager.managedItems.filter { $0.isUserActionable && $0.sourcePID != nil }
                return Set(items?.map(\.uniqueIdentifier) ?? [])
            },
            showItems: { [weak appState] in appState?.menuBarManager.itemHotkeys = $0 },
            showProfiles: { [weak appState] in appState?.profileManager.profileHotkeys = $0 }
        )
    }
}

extension SettingsChildFeature {
    static func hotkeys(_ appState: AppState) -> SettingsChildFeature {
        let mirror = SettingsHotkeysMirror(models: .live(appState))
        mirror.followItems { [weak appState] in appState?.itemManager.itemCache }
        return hotkeys(mirror: mirror)
    }

    static func hotkeys(mirror: SettingsHotkeysMirror) -> SettingsChildFeature {
        SettingsChildFeature(statuses: [
            HotkeysSettingsLink.bindings: { payload in
                SettingsLinkPayload.decode(HotkeysSettingsLink.Bindings.self, from: payload).map(mirror.show)
            },
        ])
    }
}

extension MenuBarItemImageCache {
    /// Captures every section now, since hidden ones are captured only on request. Only the app
    /// reads the screen, so the settings process asks it.
    @MainActor
    func captureForItemHotkeyList(remote: SettingsRemote? = .current) async {
        guard let remote else {
            await recaptureNow(sections: MenuBarSection.Name.allCases)
            return
        }
        remote.perform(HotkeysSettingsLink.capture)
    }
}
