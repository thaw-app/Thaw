//
//  NativeAppHidingExperiment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import PlatformRuntimeKit

/// Follows the Lab switch for native app hiding, supplying the file grant and
/// turning the switch off when NativeAppHidingController cannot start.
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
            ownsBundle: ExtraVisibilityChannel.ownsBundle,
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
            for await enabled in Observations({ settings.enableNativeAppHiding }) {
                guard !Task.isCancelled, let self else { return }
                if enabled {
                    if !controller.enable() {
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
