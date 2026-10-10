//
//  FullDiskAccessPermission.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import PlatformRuntimeKit

/// The grant that lets Thaw write the menu bar layout table
/// (TrailingItemPreferredPositions) directly, instantly and cursor-free.
/// Without it Thaw falls back to synthetic Command-drags.
///
/// The table sits in MenuBarAgent's group container, which macOS refuses
/// silently with no consent prompt. Picking the file in an open panel grants
/// that file alone and is offered first; Full Disk Access (settingsURL) is
/// offered once a dismissed panel sets wasDeclined.
///
/// Required: without it, AppState.launch(withPermissions:) shows the
/// permissions window instead of launching normally.
final class FullDiskAccessPermission: Permission {
    /// The legacy Privacy_AllFiles link still opens Full Disk Access on macOS 27.
    private static let settingsPane = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )

    init() {
        super.init(
            title: String(localized: "Menu Bar Layout Access"),
            iconName: "checkmark.shield",
            iconColor: .indigo,
            details: [
                String(localized: "Lets \(Constants.displayName) update macOS's saved menu bar layout directly, so items move into place without your pointer moving."),
                String(localized: "macOS keeps that layout in one protected file (~/Library/Group Containers/com.apple.MenuBar). \(Constants.displayName) reads it to place items and writes it only when you reorder."),
                String(localized: "Choosing that file gives \(Constants.displayName) access to it alone. Without it, \(Constants.displayName) moves items with the pointer, which takes over your cursor while it works."),
            ],
            shortDetails: [
                String(localized: "Items move into place without your pointer moving, because \(Constants.displayName) updates macOS's saved menu bar layout. It touches only that one file."),
            ],
            isRequired: true,
            settingsURL: Self.settingsPane,
            check: {
                // Re-take a grant stored on an earlier launch before probing.
                MenuBarLayoutTableAccess.shared.activateIfNeeded()
                // .absent counts as fulfilled: a missing file is writable, and
                // the host creates it once any item is positioned.
                return RuntimePreferenceStore.positionsDomainAccess() != .denied
            },
            request: { completion in
                let granted = MenuBarLayoutTableAccess.shared.requestAccessViaOpenPanel()
                // Report the panel as a prompt, or the base class would open the
                // Full Disk Access pane behind it. A dismissal sets wasDeclined.
                completion(granted, true)
            }
        )
    }
}

/// Access to Control Center's list of apps allowed in the menu bar. Native app
/// hiding switches apps off there instead of holding the assertion, leaving
/// camera, microphone and Notification Center to macOS. Optional.
final class ControlCenterAppListPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Control Center App List"),
            iconName: "switch.2",
            iconColor: .teal,
            details: [
                String(localized: "Lets \(Constants.displayName) keep Live Activities and the camera indicator on the menu bar while apps are hidden."),
                String(localized: "It also stops hidden items from flashing when Notification Center opens. Choosing the file gives \(Constants.displayName) access to it alone."),
            ],
            shortDetails: [
                String(localized: "Keeps Live Activities and the camera indicator visible while apps are hidden, and helps with hidden items flashing when Notification Center opens."),
            ],
            isRequired: false,
            settingsURL: nil,
            check: {
                PickedFileAccess.controlCenterAppList.hasAccess
            },
            request: { completion in
                completion(PickedFileAccess.controlCenterAppList.requestAccessViaOpenPanel(), true)
            }
        )
    }
}
