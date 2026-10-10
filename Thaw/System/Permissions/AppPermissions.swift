//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// The slice of AppPermissions views read, so previews can supply stand-ins.
/// The house pattern for views over long-lived subsystems: inject a narrow
/// protocol rather than reaching through AppState.
@MainActor
protocol PermissionsManaging: AnyObject, Observable {
    /// The state of the app's granted permissions.
    var permissionsState: AppPermissions.PermissionsState { get }

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] { get }
}

/// A type that manages the permissions of the app.
@MainActor
@Observable
final class AppPermissions: PermissionsManaging {
    /// Keys to access individual permissions.
    enum PermissionKey {
        /// Identifies AppPermissions.accessibility.
        case accessibility
        /// Identifies AppPermissions.screenRecording.
        case screenRecording
        /// Identifies AppPermissions.fullDiskAccess.
        case fullDiskAccess
        /// Identifies AppPermissions.controlCenterAppList.
        case controlCenterAppList
    }

    /// The state of the app's granted permissions.
    enum PermissionsState: Equatable {
        /// At least one required permission hasn't been granted.
        case missing
        /// Every permission, required or not, has been granted.
        case hasAll
        /// All required permissions are granted, but at least one optional
        /// permission is missing, the app can run in limited mode.
        case hasRequired
    }

    /// The manager's logger.
    let diagLog = DiagLog(category: "Permissions")

    /// The permission for Accessibility features.
    let accessibility = AccessibilityPermission()

    /// The permission for Screen Recording features.
    let screenRecording = ScreenRecordingPermission()

    /// The layout-table grant for cursor-free reordering on macOS 27. Required;
    /// without it Thaw reorders by synthetic Command-drag.
    let fullDiskAccess = FullDiskAccessPermission()

    /// Control Center's app list, for native app hiding. Optional.
    let controlCenterAppList = ControlCenterAppListPermission()

    /// Fired after any permission's granted state transitions, for owners
    /// that must react to a specific grant, e.g. re-arming machinery that
    /// stood down while the permission was missing.
    @ObservationIgnored
    var onPermissionTransition: ((Permission, Bool) -> Void)?

    /// The state of the app's granted permissions.
    private(set) var permissionsState: PermissionsState = .missing

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] {
        // Listing fullDiskAccess here surfaces its row in every permissions UI;
        // it asks via a panel on the layout-table file, FDA being the fallback.
        // Required grants come first.
        [accessibility, fullDiskAccess, screenRecording, controlCenterAppList]
    }

    /// The permissions required for basic app functionality.
    var requiredPermissions: [Permission] {
        allPermissions.filter(\.isRequired)
    }

    /// Creates a new permissions manager.
    init() {
        self.updatePermissionsState()
        // Permission is @Observable, so changes arrive via onChange.
        for permission in allPermissions {
            permission.onChange = { [weak self] in
                guard let self else { return }
                updatePermissionsState()
                onPermissionTransition?(permission, permission.hasPermission)
            }
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

    /// Refreshes permission grants from the system immediately.
    ///
    /// Also re-arms exhausted ungranted polls, since callers are surfaces the
    /// user is looking at.
    func refreshPermissionsState() {
        for permission in allPermissions {
            permission.resumePollingIfNeeded()
            permission.refreshStatus()
        }
        updatePermissionsState()
    }

    /// Refreshes every grant, waiting for asynchronous system probes before
    /// publishing the aggregate state. Re-arms ungranted polls like the
    /// synchronous variant above.
    func refreshPermissionsState() async {
        for permission in allPermissions {
            permission.resumePollingIfNeeded()
            await permission.refreshStatus()
        }
        updatePermissionsState()
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        diagLog.info("Stopping all permissions checks")
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
