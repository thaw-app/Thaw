//
//  FeatureTips.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import TipKit

/// Thaw's TipKit setup, done once per process from the entry point.
/// A new feature announcement follows LayoutMultiSelectTip and shows with ThawHintTipViewStyle.
@MainActor
final class FeatureTips {
    /// What one launch hands to TipKit.
    struct Setup: Equatable {
        let datastoreURL: URL
        /// Whether this launch is an upgrade from a version before multi-select.
        let isMultiSelectUpgrade: Bool
    }

    static let shared = FeatureTips()

    private static let diagLog = DiagLog(category: "FeatureTips")

    private(set) var isConfigured = false
    private let apply: @MainActor (Setup) throws -> Void
    private let retireMultiSelectTip: @MainActor () -> Void

    init(
        apply: @escaping @MainActor (Setup) throws -> Void = FeatureTips.applyToTipKit,
        retireMultiSelectTip: @escaping @MainActor () -> Void = FeatureTips.retireMultiSelectTipInTipKit
    ) {
        self.apply = apply
        self.retireMultiSelectTip = retireMultiSelectTip
    }

    /// Configures the shared instance from this process's environment and stored defaults.
    static func configureAtLaunch() {
        shared.configure(
            environment: ProcessInfo.processInfo.environment,
            applicationSupport: URL.applicationSupportDirectory,
            bundleIdentifier: Constants.bundleIdentifier,
            previousVersion: Defaults.string(forKey: .lastWhatsNewVersion)
        )
    }

    /// Records whether this launch upgraded from before multi-select without initializing TipKit eagerly.
    static func prepareAtLaunch() {
        guard isEnabled(environment: ProcessInfo.processInfo.environment) else { return }
        let previousVersion = Defaults.string(forKey: .lastWhatsNewVersion)
        if LayoutMultiSelectTip.isUpgrade(previousVersion: previousVersion) {
            Defaults.set(true, forKey: .pendingMultiSelectTip)
        }
    }

    /// Lazily initializes TipKit when Layout opens only if an upgrade tip may still need to display.
    static func configureIfNeededForLayout() {
        let environment = ProcessInfo.processInfo.environment
        guard !shared.isConfigured, isEnabled(environment: environment) else { return }
        let hasPendingUpgrade = Defaults.bool(forKey: .pendingMultiSelectTip)
        let datastoreExists = FileManager.default.fileExists(
            atPath: datastoreURL(applicationSupport: URL.applicationSupportDirectory, bundleIdentifier: Constants.bundleIdentifier).path
        )
        let hasRetired = Defaults.bool(forKey: .hasRetiredMultiSelectTip)
        guard hasPendingUpgrade || (datastoreExists && !hasRetired) else { return }
        shared.configure(
            environment: environment,
            applicationSupport: URL.applicationSupportDirectory,
            bundleIdentifier: Constants.bundleIdentifier,
            previousVersion: Defaults.string(forKey: .lastWhatsNewVersion),
            forceMultiSelectUpgrade: hasPendingUpgrade
        )
    }

    /// Configures TipKit the first time it is called and ignores later calls. It must run before the What's New
    /// check records the current version, which the entry point guarantees.
    func configure(
        environment: [String: String],
        applicationSupport: URL,
        bundleIdentifier: String,
        previousVersion: String?,
        forceMultiSelectUpgrade: Bool = false
    ) {
        guard !isConfigured, Self.isEnabled(environment: environment) else { return }
        let setup = Setup(
            datastoreURL: Self.datastoreURL(applicationSupport: applicationSupport, bundleIdentifier: bundleIdentifier),
            isMultiSelectUpgrade: forceMultiSelectUpgrade || LayoutMultiSelectTip.isUpgrade(previousVersion: previousVersion)
        )
        do {
            try apply(setup)
            isConfigured = true
        } catch {
            Self.diagLog.error("TipKit configuration failed: \(error)")
        }
    }

    /// Retires the multi-select tip. Does nothing until TipKit is configured, so tests never reach its datastore.
    func noteMultiSelect() {
        if Self.isEnabled(environment: ProcessInfo.processInfo.environment) {
            Defaults.set(false, forKey: .pendingMultiSelectTip)
            Defaults.set(true, forKey: .hasRetiredMultiSelectTip)
        }
        guard isConfigured else { return }
        retireMultiSelectTip()
    }

    /// Tips stay off in unit tests, whose host is the app, and in SwiftUI previews.
    static nonisolated func isEnabled(environment: [String: String]) -> Bool {
        guard !TestHosting.isActive(environment: environment) else { return false }
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }

    /// The datastore lives in the app's own Application Support folder, so the debug build keeps its own tips.
    static nonisolated func datastoreURL(applicationSupport: URL, bundleIdentifier: String) -> URL {
        applicationSupport
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Tips", directoryHint: .isDirectory)
    }

    private static func applyToTipKit(_ setup: Setup) throws {
        try FileManager.default.createDirectory(at: setup.datastoreURL, withIntermediateDirectories: true)
        try Tips.configure([
            .datastoreLocation(.url(setup.datastoreURL)),
            .displayFrequency(.immediate),
        ])
        // Only ever set to true: the Settings process reads defaults after the app has recorded the new version.
        if setup.isMultiSelectUpgrade {
            LayoutMultiSelectTip.isUpgrade = true
        }
    }

    private static func retireMultiSelectTipInTipKit() {
        LayoutMultiSelectTip().invalidate(reason: .actionPerformed)
    }
}
