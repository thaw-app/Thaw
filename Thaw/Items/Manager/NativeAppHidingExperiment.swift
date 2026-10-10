//
//  NativeAppHidingExperiment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
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

    /// True while apps hidden in an earlier session could not be shown again at launch.
    var previousSessionRecoveryFailed: Bool {
        controller.previousSessionRecoveryFailed
    }

    @ObservationIgnored private let controller: NativeAppHidingController = {
        let appListAccess = PickedFileAccess.controlCenterAppList
        return NativeAppHidingController(environment: .init(
            activateAccess: { appListAccess.activateIfNeeded() },
            requestAccess: { appListAccess.requestAccessViaOpenPanel() },
            ownsBundle: ExtraVisibilityChannel.keepsOffSystemList,
            hideOwnedBundles: ExtraVisibilityChannel.hide
        ))
    }()

    @ObservationIgnored private var observationTask: Task<Void, Never>?

    deinit {
        observationTask?.cancel()
    }

    /// Run before the section engine starts, even when the experiment is off.
    func recoverPreviousSession() {
        controller.recoverPreviousSession()
    }

    func start(controller sectionController: RuntimeSectionController, settings: AdvancedSettings) {
        controller.attach(to: sectionController)
        observationTask?.cancel()
        observationTask = Task { [weak self, weak settings] in
            guard let settings else { return }
            // The first value is the stored choice as the app starts; later ones are the user's.
            var isLaunch = true
            for await enabled in Observations({ settings.enableNativeAppHiding }) {
                guard !Task.isCancelled, let self else { return }
                defer { isLaunch = false }
                if enabled {
                    if !controller.enable(), !NativeHidingStart.keepsChoice(afterFailedStartAtLaunch: isLaunch) {
                        settings.enableNativeAppHiding = false
                    }
                } else {
                    controller.disable()
                }
            }
        }
    }

    func prepareForTermination() {
        observationTask?.cancel()
        controller.prepareForTermination()
    }
}
