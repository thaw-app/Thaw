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
final class AppRunningTriggersManager {
    private struct SavedRules: Codable {
        var version = 1
        var rules: [AppRunningTrigger]
    }

    private(set) var rules: [AppRunningTrigger] = []
    private(set) var runningBundleIDs: Set<String> = []
    private(set) var canEdit = true
    var errorMessage: String?

    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var heldIdentifiers: Set<String> = []
    @ObservationIgnored private var reveal: ((String) -> Void)?
    @ObservationIgnored private var release: ((String) -> Void)?

    init(store: UserDefaults = Defaults.store) {
        self.store = store
        guard store.object(forKey: Defaults.Key.appRunningTriggers.rawValue) != nil else { return }
        do {
            guard let data = store.data(forKey: Defaults.Key.appRunningTriggers.rawValue) else {
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
            canEdit = false
            errorMessage = String(localized: "Saved triggers could not be read. They have not been changed. Reset triggers to start again.")
        }
    }

    func start(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        runningApplications: @escaping @MainActor () -> [pid_t: String] = {
            Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app in
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

    func stop() {
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

    func updateRunningApplications(_ applications: [pid_t: String]) {
        runningBundleIDs = Set(applications.values)
        reconcile()
    }

    @discardableResult
    func save(_ rule: AppRunningTrigger) -> Bool {
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

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard var rule = rules.first(where: { $0.id == id }) else { return }
        rule.isEnabled = enabled
        save(rule)
    }

    func remove(id: UUID) {
        _ = persist(rules.filter { $0.id != id })
    }

    func reset() {
        store.removeObject(forKey: Defaults.Key.appRunningTriggers.rawValue)
        rules = []
        canEdit = true
        errorMessage = nil
        reconcile()
    }

    private func persist(_ updated: [AppRunningTrigger]) -> Bool {
        guard canEdit else { return false }
        do {
            let data = try JSONEncoder().encode(SavedRules(rules: updated))
            store.set(data, forKey: Defaults.Key.appRunningTriggers.rawValue)
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
