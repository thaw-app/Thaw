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
    }

    private(set) var candidates: [Candidate] = []
    private(set) var recordedBundleIDs: Set<String> = []
    var selectedBundleIDs: Set<String> = []
    private(set) var isBusy = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
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
            let inventory = try environment.inspect()
            recordedBundleIDs = inventory.recorded
            candidates = inventory.disabled.filter { !inventory.recorded.contains($0) }.map {
                Candidate(id: $0, name: environment.displayName($0))
            }
            selectedBundleIDs = []
            hasLoaded = true
        } catch {
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
            errorMessage = error.localizedDescription
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
