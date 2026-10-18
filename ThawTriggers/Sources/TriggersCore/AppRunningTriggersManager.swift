//
//  AppRunningTriggersManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Observation

@MainActor
@Observable
public final class AppRunningTriggersManager {
    /// The key the rules are stored under, in the module's defaults and in
    /// Thaw's, where they lived before triggers became a module.
    public static let storageKey = "AppRunningTriggersV1"

    private struct SavedRules: Codable {
        var version = 1
        var rules: [AppRunningTrigger]
    }

    public private(set) var rules: [AppRunningTrigger] = []
    public private(set) var runningBundleIDs: Set<String> = []
    public private(set) var canEdit = true
    public var errorMessage: String?

    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var heldIdentifiers: Set<String> = []
    @ObservationIgnored private var reveal: ((String) -> Void)?
    @ObservationIgnored private var release: ((String) -> Void)?

    public init(store: UserDefaults = .standard) {
        self.store = store
        guard store.object(forKey: Self.storageKey) != nil else { return }
        do {
            guard let data = store.data(forKey: Self.storageKey) else {
                throw CocoaError(.coderReadCorrupt)
            }
            let saved = try JSONDecoder().decode(SavedRules.self, from: data)
            guard saved.version == 1,
                  saved.rules.allSatisfy(\.isValid),
                  Set(saved.rules.map(\.id)).count == saved.rules.count
            else {
                throw CocoaError(.coderReadCorrupt)
            }
            rules = saved.rules
        } catch {
            // The window says so in its own section, with the reset button.
            canEdit = false
        }
    }

    public func start(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        runningApplications: @escaping @MainActor () -> [pid_t: String] = {
            AppRunningTriggersManager.bundleIDsByPID(NSWorkspace.shared.runningApplications.compactMap { app in
                guard !app.isTerminated, let bundleID = app.bundleIdentifier else { return nil }
                return (app.processIdentifier, bundleID)
            })
        },
        reveal: @escaping (String) -> Void,
        release: @escaping (String) -> Void
    ) {
        stop()
        self.reveal = reveal
        self.release = release
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            notificationCenter.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateRunningApplications(runningApplications())
                }
                .store(in: &subscriptions)
        }
        updateRunningApplications(runningApplications())
    }

    /// NSWorkspace can list one pid twice, and gives -1 to every app with no
    /// process yet. Either made a unique-keys dictionary trap at launch.
    public static nonisolated func bundleIDsByPID(_ applications: [(pid: pid_t, bundleID: String)]) -> [pid_t: String] {
        var result: [pid_t: String] = [:]
        for (index, app) in applications.enumerated() {
            // An app with no pid still counts as running, under a key of its own.
            let key = app.pid > 0 ? app.pid : pid_t(-(index + 1))
            result[key] = result[key] ?? app.bundleID
        }
        return result
    }

    public func stop() {
        subscriptions.removeAll()
        let previous = heldIdentifiers
        heldIdentifiers.removeAll()
        for identifier in previous.sorted() {
            release?(identifier)
        }
        reveal = nil
        release = nil
        runningBundleIDs = []
    }

    public func updateRunningApplications(_ applications: [pid_t: String]) {
        runningBundleIDs = Set(applications.values)
        reconcile()
    }

    @discardableResult
    public func save(_ rule: AppRunningTrigger) -> Bool {
        guard rule.isValid else {
            errorMessage = String(localized: "Choose an app and at least one menu bar item.")
            return false
        }
        var updated = rules
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        return persist(updated)
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        guard var rule = rules.first(where: { $0.id == id }) else { return }
        rule.isEnabled = enabled
        save(rule)
    }

    public func remove(id: UUID) {
        _ = persist(rules.filter { $0.id != id })
    }

    public func reset() {
        store.removeObject(forKey: Self.storageKey)
        rules = []
        canEdit = true
        errorMessage = nil
        reconcile()
    }

    /// Copies the rules Thaw saved before triggers became a module, once:
    /// only when this store has none of its own.
    public static func importFromThaw(into store: UserDefaults, hostDefaults: UserDefaults?) {
        guard store.object(forKey: storageKey) == nil,
              let data = hostDefaults?.data(forKey: storageKey)
        else { return }
        store.set(data, forKey: storageKey)
    }

    private func persist(_ updated: [AppRunningTrigger]) -> Bool {
        guard canEdit else { return false }
        do {
            let data = try JSONEncoder().encode(SavedRules(rules: updated))
            store.set(data, forKey: Self.storageKey)
            rules = updated
            errorMessage = nil
            reconcile()
            return true
        } catch {
            errorMessage = String(localized: "The trigger could not be saved. Try again.")
            return false
        }
    }

    private func reconcile() {
        guard let reveal, let release else { return }
        let wanted = Set(rules.filter { $0.matches(runningBundleIDs: runningBundleIDs) }
            .flatMap { $0.targets.map(\.id) })
        let added = wanted.subtracting(heldIdentifiers)
        let removed = heldIdentifiers.subtracting(wanted)
        heldIdentifiers = wanted
        // One hold per target across all matching rules; never write a saved section assignment.
        for identifier in added.sorted() {
            reveal(identifier)
        }
        for identifier in removed.sorted() {
            release(identifier)
        }
    }
}
