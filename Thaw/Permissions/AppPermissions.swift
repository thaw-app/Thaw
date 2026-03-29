//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// A type that manages the permissions of the app.
@MainActor
final class AppPermissions: ObservableObject {
    /// The state of the app's granted permissions.
    enum PermissionsState {
        case missing
        case hasAll
        case hasRequired
    }

    /// The manager's logger.
    let diagLog = DiagLog(category: "Permissions")

    /// The permission for Accessibility features.
    let accessibility = AccessibilityPermission()

    /// The state of the app's granted permissions.
    @Published private(set) var permissionsState: PermissionsState = .missing

    /// Storage for internal observers.
    private var cancellable: AnyCancellable?

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] {
        [accessibility]
    }

    /// The permissions required for basic app functionality.
    var requiredPermissions: [Permission] {
        allPermissions.filter { $0.isRequired }
    }

    /// Creates a new permissions manager.
    init() {
        self.updatePermissionsState()
        self.cancellable = Publishers.MergeMany(allPermissions.map { $0.$hasPermission })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePermissionsState()
            }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        if allPermissions.allSatisfy({ $0.hasPermission }) {
            permissionsState = .hasAll
        } else if requiredPermissions.allSatisfy({ $0.hasPermission }) {
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
