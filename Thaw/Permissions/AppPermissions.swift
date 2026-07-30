//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// An abstraction over ``AppPermissions`` that lets views depend on just the
/// pieces they read, so previews can supply lightweight stand-ins instead of
/// the real manager and its associated app machinery.
@MainActor
protocol PermissionsManaging: ObservableObject {
    /// The state of the app's granted permissions.
    var permissionsState: AppPermissions.PermissionsState { get }

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] { get }
}

/// A type that manages the permissions of the app.
@MainActor
final class AppPermissions: ObservableObject, PermissionsManaging {
    /// Keys to access individual permissions.
    enum PermissionKey {
        /// Identifies ``AppPermissions/accessibility``.
        case accessibility
        /// Identifies ``AppPermissions/screenRecording``.
        case screenRecording
    }

    /// The state of the app's granted permissions.
    enum PermissionsState {
        /// At least one required permission hasn't been granted.
        case missing
        /// Every permission, required or not, has been granted.
        case hasAll
        /// All required permissions are granted, but at least one optional
        /// permission is missing — the app can run in limited mode.
        case hasRequired
    }

    /// The manager's logger.
    let diagLog = DiagLog(category: "Permissions")

    /// The permission for Accessibility features.
    let accessibility = AccessibilityPermission()

    /// The permission for Screen Recording features.
    let screenRecording = ScreenRecordingPermission()

    /// The state of the app's granted permissions.
    @Published private(set) var permissionsState: PermissionsState = .missing

    /// Storage for internal observers.
    private var cancellable: AnyCancellable?

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] {
        [accessibility, screenRecording]
    }

    /// The permissions required for basic app functionality.
    var requiredPermissions: [Permission] {
        allPermissions.filter(\.isRequired)
    }

    /// Creates a new permissions manager.
    init() {
        self.updatePermissionsState()
        self.cancellable = Publishers.MergeMany(allPermissions.map(\.$hasPermission))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePermissionsState()
            }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        if allPermissions.allSatisfy(\.hasPermission) {
            permissionsState = .hasAll
        } else if requiredPermissions.allSatisfy(\.hasPermission) {
            permissionsState = .hasRequired
        } else {
            permissionsState = .missing
        }
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        diagLog.info("Stopping all permissions checks")
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
