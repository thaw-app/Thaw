//
//  NativeVisibilityRecoveryModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

@MainActor
@Observable
final class NativeVisibilityRecoveryModel {
    struct Candidate: Identifiable {
        let id: String
        let name: String
    }

    struct Environment {
        var conflictingApplications: () -> [String]
        var disableNativeHiding: () -> Void
        var requestAccess: () -> Bool
        var inspect: () throws -> (disabled: [String], recorded: Set<String>)
        var restore: (Set<String>) async throws -> Int
        var displayName: (String) -> String
        var wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }
        /// True for the error the records throw when one exists but can't be read.
        var isUnreadableRecord: (Error) -> Bool = { _ in false }
        /// Moves the unreadable records aside and returns where they went.
        var setAsideUnreadableRecords: () throws -> [URL] = { [] }
    }

    private(set) var candidates: [Candidate] = []
    private(set) var recordedBundleIDs: Set<String> = []
    var selectedBundleIDs: Set<String> = []
    private(set) var isBusy = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    /// True while Thaw's record of the apps it hid exists but can't be read.
    /// No app list is shown until the user sets the record aside.
    private(set) var recordIsUnreadable = false
    /// Where the unreadable records went after the user set them aside.
    private(set) var setAsideLocations: [URL] = []
    @ObservationIgnored private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    var canRestore: Bool {
        hasLoaded && !isBusy && (!selectedBundleIDs.isEmpty || !recordedBundleIDs.isEmpty)
    }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        successMessage = nil
        hasLoaded = false
        defer { isBusy = false }
        do {
            for _ in 0 ..< 50 {
                if environment.conflictingApplications().isEmpty {
                    break
                }
                try await environment.wait()
            }
            try requireExclusiveAccess()
            environment.disableNativeHiding()
            guard environment.requestAccess() else { throw RecoveryError.accessNotGranted }
            try requireExclusiveAccess()
            try loadInventory()
        } catch {
            noteFailure(error)
        }
    }

    /// Sets the unreadable records aside, then lists every switched-off app,
    /// none of them selected. Call it only after the user confirmed.
    func setAsideUnreadableRecords() {
        guard recordIsUnreadable, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }
        do {
            try requireExclusiveAccess()
            setAsideLocations = try environment.setAsideUnreadableRecords()
            recordIsUnreadable = false
            try loadInventory()
        } catch {
            noteFailure(error)
        }
    }

    private func loadInventory() throws {
        let inventory = try environment.inspect()
        recordedBundleIDs = inventory.recorded
        candidates = inventory.disabled.filter { !inventory.recorded.contains($0) }.map {
            Candidate(id: $0, name: environment.displayName($0))
        }
        selectedBundleIDs = []
        recordIsUnreadable = false
        hasLoaded = true
    }

    /// An unreadable record is explained by its own state, not as an error.
    private func noteFailure(_ error: Error) {
        if environment.isUnreadableRecord(error) {
            recordIsUnreadable = true
            hasLoaded = false
            candidates = []
            recordedBundleIDs = []
            selectedBundleIDs = []
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        guard canRestore else { return }
        isBusy = true
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }
        do {
            try requireExclusiveAccess()
            _ = try await environment.restore(selectedBundleIDs)
            successMessage = String(localized: "Visibility settings were saved and verified. Quit recovery and check your menu bar before reopening Thaw. Native hiding remains off.")
            hasLoaded = false
            selectedBundleIDs = []
            recordedBundleIDs = []
            candidates = []
        } catch {
            noteFailure(error)
        }
    }

    private func requireExclusiveAccess() throws {
        guard environment.conflictingApplications().isEmpty else { throw RecoveryError.otherManagerRunning }
    }

    enum RecoveryError: LocalizedError {
        case otherManagerRunning, accessNotGranted, normalLaunch

        var errorDescription: String? {
            switch self {
            case .otherManagerRunning:
                String(localized: "Quit other copies of Thaw and Bartender before continuing. Recovery records have been kept.")
            case .accessNotGranted:
                String(localized: "Read and write access was not granted. Try again or restore the app switches in System Settings → Menu Bar.")
            case .normalLaunch:
                String(localized: "Open recovery from Troubleshooting so normal hiding can stop first.")
            }
        }
    }
}
