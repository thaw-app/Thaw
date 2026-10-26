//
//  NativeAppHidingExperiment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation
import PlatformRuntimeKit

/// What happens to the user's choice of native hiding when it cannot start.
nonisolated enum NativeHidingStart {
    /// A start that fails at launch keeps the choice. The read can fail then for reasons the user did
    /// nothing to cause, such as a grant that did not resume after an update, and switching the choice
    /// off silently loses it. The session falls back to the usual hiding and Settings says why.
    /// A start the user just asked for goes back to off, so the switch shows what is running.
    static func keepsChoice(afterFailedStartAtLaunch isLaunch: Bool) -> Bool {
        isLaunch
    }

    /// What Settings says after a start the user asked for fails. The choice going back to Standard
    /// would otherwise look like the picker ignoring the click.
    static func failureNotice(reason: String?) -> String {
        let reason = reason ?? String(localized: "macOS gave no reason.")
        return String(localized: "Native didn't start, so \(Constants.displayName) is using Standard: \(reason)")
    }

    /// Why this session uses Standard while Native stays chosen, or nil when Native is running.
    /// An unreadable record has its own notice with the way out, so it gives no reason here.
    static func fallbackReason(
        nativeChosen: Bool,
        isActive: Bool,
        journalNeedsAttention: Bool,
        lastError: String?
    ) -> String? {
        guard nativeChosen, !isActive, !journalNeedsAttention else { return nil }
        return lastError
    }

    /// The hiding method can change only while native hiding is able to act on the change.
    static func allowsMethodChange(journalNeedsAttention: Bool) -> Bool {
        !journalNeedsAttention
    }
}

/// Follows the switch for native app hiding, supplying the file grant and
/// turning the switch off when the user turns it on and NativeAppHidingController cannot start.
@MainActor
@Observable
final class NativeAppHidingExperiment {
    var isActive: Bool {
        controller.isActive
    }

    var lastError: String? {
        controller.lastError
    }

    /// Why the last start the user asked for failed, until they try Native again.
    private(set) var failedStartNotice: String?

    /// Apps the user switched off in System Settings, as of the last refresh.
    private(set) var userSwitchedOffBundleIDs: Set<String> = []

    /// Reads which of these items' apps are switched off in System Settings without being in
    /// Thaw's record. Named explicitly, so the read works with either hiding method; one that
    /// fails, as without access to the system list, keeps the last answer.
    func refreshUserSwitchedOffApps(among items: [MenuBarItem]) {
        guard let switchedOff = try? controller.unjournaledHiddenApps(among: UserSwitchedOffApps.bundleIDs(of: items)) else { return }
        let bundleIDs = UserSwitchedOffApps.bundleIDs(switchedOff: switchedOff, ownedByThaw: ExtraVisibilityChannel.keepsOffSystemList)
        if bundleIDs != userSwitchedOffBundleIDs {
            userSwitchedOffBundleIDs = bundleIDs
        }
    }

    /// True while apps hidden in an earlier session could not be shown again at launch.
    var previousSessionRecoveryFailed: Bool {
        controller.previousSessionRecoveryFailed
    }

    /// True while Thaw's record of the apps it hid exists but can't be read.
    /// Native hiding changes nothing until the user sets the record aside, so
    /// the hiding method stays as it is until then.
    var journalNeedsAttention: Bool {
        controller.journalNeedsAttention
    }

    @ObservationIgnored private let controller: NativeAppHidingController

    /// Offers apps an older version may have left switched off.
    let restoreOffer: HiddenAppsRestoreOffer

    init() {
        let appListAccess = PickedFileAccess.controlCenterAppList
        let controller = NativeAppHidingController(environment: .init(
            activateAccess: { appListAccess.activateIfNeeded() },
            requestAccess: { appListAccess.requestAccessViaOpenPanel() },
            ownsBundle: ExtraVisibilityChannel.keepsOffSystemList,
            hideOwnedBundles: ExtraVisibilityChannel.hide
        ))
        self.controller = controller
        restoreOffer = HiddenAppsRestoreOffer(environment: .init(
            findCandidates: { (try? controller.unjournaledHiddenApps()) ?? [] },
            showApps: { try controller.showApps($0) },
            isAnswered: { Defaults.bool(forKey: .hasAnsweredHiddenAppsRestoreOffer) },
            markAnswered: { Defaults.set(true, forKey: .hasAnsweredHiddenAppsRestoreOffer) }
        ))
    }

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private weak var settings: AdvancedSettings?

    deinit {
        observationTask?.cancel()
    }

    /// Run before the section engine starts, even when the experiment is off.
    func recoverPreviousSession() {
        controller.recoverPreviousSession()
    }

    func start(controller sectionController: RuntimeSectionController, settings: AdvancedSettings) {
        controller.attach(to: sectionController)
        self.settings = settings
        // Before the first start, which takes over the apps it hides.
        restoreOffer.captureCandidates()
        observationTask?.cancel()
        observationTask = Task { [weak self, weak settings] in
            guard let settings else { return }
            // The first value is the stored choice as the app starts; later ones are the user's.
            var isLaunch = true
            for await enabled in Observations({ settings.enableNativeAppHiding }) {
                guard !Task.isCancelled, let self else { return }
                defer { isLaunch = false }
                if enabled {
                    enable(settings: settings, isLaunch: isLaunch)
                } else {
                    controller.disable()
                }
            }
        }
    }

    /// Moves the unreadable record aside after the user agreed, then starts
    /// Native again when it is chosen. Apps hidden under the old record stay
    /// switched off until the user picks them in the restore offer.
    func setAsideUnreadableRecord() throws {
        try controller.discardUnreadableJournal()
        restoreOffer.offerAfterSettingRecordAside()
        guard let settings, settings.enableNativeAppHiding, !controller.isActive else { return }
        enable(settings: settings, isLaunch: false)
    }

    private func enable(settings: AdvancedSettings, isLaunch: Bool) {
        failedStartNotice = nil
        if !controller.enable(), !NativeHidingStart.keepsChoice(afterFailedStartAtLaunch: isLaunch) {
            failedStartNotice = NativeHidingStart.failureNotice(reason: controller.lastError)
            settings.enableNativeAppHiding = false
        }
    }

    func prepareForTermination() {
        observationTask?.cancel()
        controller.prepareForTermination()
    }
}
