//
//  SettingsURIHandler+Launcher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

// MARK: - Launcher Operations

extension SettingsURIHandler {
    /// What the launcher operations read and do, narrowed so they run without an AppState.
    struct LauncherEnvironment {
        var hasAccessibilityPermission: () -> Bool
        var items: () -> [LauncherURIPayload.Item]
        var appearance: () -> SharedAppearance
        var profiles: () -> [ProfileMetadata]
        var activeProfileID: () -> UUID?
        var activateItem: (String) async -> MenuBarItemActivationOutcome
        /// Applies a saved profile and reports whether its layout half ran.
        var applyProfile: (UUID) async throws -> Bool
    }

    /// Handles the four launcher operations; the caller has already passed the whitelist gate.
    /// Lists need a response mechanism. The two actions run without one, as other thaw:// actions do.
    static func handleLauncherRequest(
        _ request: LauncherURIRequest,
        sender: String?,
        appState: AppState
    ) async {
        await handleLauncherRequest(request, sender: sender, environment: LauncherEnvironment(appState: appState))
    }

    static func handleLauncherRequest(
        _ request: LauncherURIRequest,
        sender: String?,
        environment: LauncherEnvironment
    ) async {
        let requestId = request.requestId ?? UUID().uuidString
        let operation = request.operation
        diagLog.debug("Launcher URI: \(operation.rawValue) from \(sender ?? "unknown")")

        let response: [String: Any]
        switch operation {
        case .listItems, .listProfiles, .getAppearance:
            guard request.hasResponseMechanism else {
                diagLog.warning("Launcher URI \(operation.rawValue): provide callback=<url> or broadcast=true")
                return
            }
            response = queryResponse(for: operation, environment: environment, requestId: requestId)
        case .activateItem, .applyProfile:
            if let identifier = request.identifier {
                response = operation == .activateItem
                    ? await activateItemResponse(identifier: identifier, environment: environment, requestId: requestId)
                    : await applyProfileResponse(identifier: identifier, environment: environment, requestId: requestId)
            } else {
                let parameter = operation.identifierParameter ?? "identifier"
                diagLog.warning("Launcher URI \(operation.rawValue): missing \(parameter)")
                response = LauncherURIResponse.failure(
                    LauncherURIResponse.invalidRequest,
                    details: "Provide \(parameter)=<id>",
                    operation: operation,
                    requestId: requestId
                )
            }
        }

        deliverLauncherResponse(response, for: request, requestId: requestId)
    }

    /// The answer to an operation that only reads state.
    private static func queryResponse(
        for operation: LauncherURIOperation,
        environment: LauncherEnvironment,
        requestId: String
    ) -> [String: Any] {
        switch operation {
        case .listItems:
            listItemsResponse(environment: environment, requestId: requestId)
        case .getAppearance:
            LauncherURIResponse.success(environment.appearance(), operation: .getAppearance, requestId: requestId)
        case .listProfiles, .activateItem, .applyProfile:
            listProfilesResponse(environment: environment, requestId: requestId)
        }
    }

    private static func listItemsResponse(environment: LauncherEnvironment, requestId: String) -> [String: Any] {
        // An empty list would read as an empty menu bar, so say why instead.
        guard environment.hasAccessibilityPermission() else {
            return LauncherURIResponse.failure(
                LauncherURIResponse.permissionMissing,
                details: "Accessibility permission is not granted",
                operation: .listItems,
                requestId: requestId
            )
        }
        return LauncherURIResponse.success(
            LauncherURIPayload.ItemList(items: environment.items()),
            operation: .listItems,
            requestId: requestId
        )
    }

    /// The same filter the Shortcuts item picker uses, so every listed
    /// identifier is one activate-item resolves.
    static func launcherItems(
        from items: [MenuBarItem],
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> [LauncherURIPayload.Item] {
        items
            .filter(\.isUserActionable)
            .map { item in
                LauncherURIPayload.Item(
                    id: item.uniqueIdentifier,
                    name: MenuBarItemDisplayName.displayName(for: item),
                    section: section(item).rawValue,
                    bundleId: (item.sourceApplication ?? item.owningApplication)?.bundleIdentifier
                )
            }
    }

    private static func listProfilesResponse(environment: LauncherEnvironment, requestId: String) -> [String: Any] {
        LauncherURIResponse.success(
            LauncherURIPayload.ProfileList(
                profiles: environment.profiles(),
                activeProfileID: environment.activeProfileID()
            ),
            operation: .listProfiles,
            requestId: requestId
        )
    }

    private static func activateItemResponse(
        identifier: String,
        environment: LauncherEnvironment,
        requestId: String
    ) async -> [String: Any] {
        let outcome = await environment.activateItem(identifier)
        diagLog.info("Launcher URI activate-item: \(identifier) -> \(outcome)")
        return LauncherURIResponse.activation(itemId: identifier, outcome: outcome, requestId: requestId)
    }

    private static func applyProfileResponse(
        identifier: String,
        environment: LauncherEnvironment,
        requestId: String
    ) async -> [String: Any] {
        let outcome: LauncherProfileApplyOutcome
        if let profileID = UUID(uuidString: identifier), environment.profiles().contains(where: { $0.id == profileID }) {
            do {
                outcome = try await environment.applyProfile(profileID) ? .applied : .appliedWithoutLayout
            } catch {
                diagLog.error("Launcher URI apply-profile: \(identifier) failed to load: \(error)")
                outcome = .applyFailed
            }
        } else {
            outcome = .profileUnavailable
        }
        diagLog.info("Launcher URI apply-profile: \(identifier) -> \(outcome.rawValue)")
        return LauncherURIResponse.profileApplication(profileId: identifier, outcome: outcome, requestId: requestId)
    }

    /// Same split as thaw://get: the full response goes only to the callback;
    /// a broadcast, which any process can hear, gets an acknowledgement.
    private static func deliverLauncherResponse(
        _ response: [String: Any],
        for request: LauncherURIRequest,
        requestId: String
    ) {
        if let callback = request.callback {
            _ = sendCallbackResponse(response: response, callback: callback)
        } else if request.broadcast {
            _ = sendBroadcastResponse(response: [
                "requestId": requestId,
                "operation": request.operation.rawValue,
                "status": "ack",
                "message": "Use callback URL to receive the full response",
            ])
        }
    }
}

// MARK: - Live Environment

extension SettingsURIHandler.LauncherEnvironment {
    init(appState: AppState) {
        self.init(
            hasAccessibilityPermission: { appState.permissions.accessibility.hasPermission },
            items: {
                let controller = appState.menuBarManager.sectionController
                return SettingsURIHandler.launcherItems(from: appState.itemManager.managedItems) {
                    controller.section(for: $0)
                }
            },
            appearance: {
                let configuration = appState.appearanceManager.effectiveConfiguration
                return SharedAppearance(
                    configuration: configuration.current,
                    shapeKind: configuration.shapeKind,
                    hasRoundedShape: configuration.hasRoundedShape,
                    isDark: SystemAppearance.current == .dark
                )
            },
            profiles: { appState.profileManager.profiles },
            activeProfileID: { appState.profileManager.activeProfileID },
            activateItem: { await appState.itemManager.activateItem(withIdentifier: $0) },
            applyProfile: { profileID in
                let manager = appState.profileManager
                try await manager.applyProfileAwaitingLayout(id: profileID, to: appState)
                return !manager.layoutDidNotRun
            }
        )
    }
}
