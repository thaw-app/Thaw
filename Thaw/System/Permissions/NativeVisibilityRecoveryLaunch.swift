//
//  NativeVisibilityRecoveryLaunch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import PlatformRuntimeKit

@MainActor
enum NativeVisibilityRecoveryLaunch {
    static let argument = "--recover-menu-bar-visibility"
    static var isRequested: Bool {
        isRequested(in: ProcessInfo.processInfo.arguments)
    }

    static func isRequested(in arguments: [String]) -> Bool {
        arguments.contains(argument)
    }

    /// One running app, reduced to what the conflict rule reads.
    struct RunningApplication {
        var processIdentifier: pid_t
        var isTerminated: Bool
        var bundleIdentifier: String?
        var localizedName: String?
    }

    private(set) static var isHandingOff = false

    static func conflictingApplications() -> [String] {
        conflictingApplications(
            among: NSWorkspace.shared.runningApplications.map { app in
                RunningApplication(
                    processIdentifier: app.processIdentifier,
                    isTerminated: app.isTerminated,
                    bundleIdentifier: app.bundleIdentifier,
                    localizedName: app.localizedName
                )
            },
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    /// Other live copies of Thaw, including this build's own bundle, and Bartender.
    static func conflictingApplications(
        among applications: [RunningApplication],
        ownProcessIdentifier: pid_t,
        ownBundleIdentifier: String?
    ) -> [String] {
        var bundles: Set = ["com.stonerl.Thaw", "com.stonerl.Thaw.debug", "com.surteesstudios.Bartender"]
        if let ownBundleIdentifier {
            bundles.insert(ownBundleIdentifier)
        }
        return applications.compactMap { app in
            guard app.processIdentifier != ownProcessIdentifier,
                  !app.isTerminated, let bundle = app.bundleIdentifier, bundles.contains(bundle) else { return nil }
            return app.localizedName ?? bundle
        }
    }

    /// Recovery may touch the app list only when launched for it and alone.
    static func ensureExclusiveAccess(isRequested: Bool, conflictingApplications: [String]) throws {
        guard isRequested else { throw NativeVisibilityRecoveryModel.RecoveryError.normalLaunch }
        guard conflictingApplications.isEmpty else { throw NativeVisibilityRecoveryModel.RecoveryError.otherManagerRunning }
    }

    /// The app's file name without its extension, or the bundle ID for an app that is not installed.
    static func displayName(forBundleID bundleID: String, applicationURL: URL?) -> String {
        guard let applicationURL else { return bundleID }
        return applicationURL.deletingPathExtension().lastPathComponent
    }

    static func openRecovery() async throws {
        // The normal quit path may clear its journal using a cached read-back.
        // Keep a separate recovery intent until disk verification succeeds.
        try NativeAppVisibilityRecovery().preserveRecoveryRecords()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [argument]
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        isHandingOff = true
        ApplicationTermination.request()
    }
}

extension NativeVisibilityRecoveryModel {
    static func live() -> NativeVisibilityRecoveryModel {
        let ensureExclusive: @MainActor () throws -> Void = {
            try NativeVisibilityRecoveryLaunch.ensureExclusiveAccess(
                isRequested: NativeVisibilityRecoveryLaunch.isRequested,
                conflictingApplications: NativeVisibilityRecoveryLaunch.conflictingApplications()
            )
        }
        let recovery = NativeAppVisibilityRecovery(ensureExclusiveAccess: ensureExclusive)
        let access = PickedFileAccess.controlCenterVisibilityRecovery
        return NativeVisibilityRecoveryModel(environment: Environment(
            conflictingApplications: NativeVisibilityRecoveryLaunch.conflictingApplications,
            disableNativeHiding: { Defaults.set(false, forKey: .enableNativeAppHiding) },
            requestAccess: { access.hasReadWriteAccess || (access.requestAccessViaOpenPanel() && access.hasReadWriteAccess) },
            inspect: {
                let inventory = try recovery.inspect()
                return (inventory.disabledBundleIDs, inventory.recordedBundleIDs)
            },
            restore: { try await recovery.restore(selectedBundleIDs: $0) },
            displayName: { bundleID in
                NativeVisibilityRecoveryLaunch.displayName(
                    forBundleID: bundleID,
                    applicationURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                )
            }
        ))
    }
}
