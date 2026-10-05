//
//  LauncherURI.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The thaw:// operations a launcher drives: it queries, ranks and picks an
/// identifier; Thaw resolves it, acts, and reports what happened.
nonisolated enum LauncherURIOperation: String, CaseIterable, Sendable {
    case listItems = "list-items"
    case activateItem = "activate-item"
    case listProfiles = "list-profiles"
    case applyProfile = "apply-profile"
    case getAppearance = "get-appearance"

    /// The query parameter carrying the identifier the operation acts on.
    var identifierParameter: String? {
        switch self {
        case .listItems, .listProfiles, .getAppearance: nil
        case .activateItem: "item-id"
        case .applyProfile: "profile-id"
        }
    }
}

/// A parsed launcher URL. The response parameters are the ones thaw://get
/// already takes, so a client has one convention to implement.
nonisolated struct LauncherURIRequest: Equatable, Sendable {
    let operation: LauncherURIOperation
    /// The item or profile identifier, nil when absent or empty.
    let identifier: String?
    let callback: String?
    let broadcast: Bool
    let requestId: String?

    /// Whether the caller gave Thaw anywhere to send a response.
    var hasResponseMechanism: Bool {
        callback != nil || broadcast
    }

    /// Returns nil when the URL's host is not a launcher operation.
    init?(url: URL) {
        guard let operation = LauncherURIOperation(rawValue: url.host?.lowercased() ?? "") else {
            return nil
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let value = queryItems.first(where: { $0.name == name })?.value, !value.isEmpty else {
                return nil
            }
            return value
        }

        self.operation = operation
        self.identifier = operation.identifierParameter.flatMap(value)
        self.callback = value("callback")
        self.broadcast = value("broadcast") == "true"
        self.requestId = value("requestId")
    }
}

/// What became of thaw://apply-profile.
nonisolated enum LauncherProfileApplyOutcome: String, Sendable {
    case applied
    /// Settings applied, but the layout engine was unavailable.
    case appliedWithoutLayout
    /// The identifier is not a UUID or names no saved profile.
    case profileUnavailable
    /// The profile exists but its file could not be read.
    case applyFailed

    var isSuccess: Bool {
        self == .applied || self == .appliedWithoutLayout
    }
}

/// The data a launcher receives: enough to name and pick things, not Thaw's item model.
/// Every payload carries version; additive changes keep it, anything else bumps it.
nonisolated enum LauncherURIPayload {
    static let version = 1

    struct Item: Codable, Equatable, Sendable {
        /// MenuBarItem.uniqueIdentifier, the value activate-item takes back.
        let id: String
        let name: String
        /// A MenuBarSectionName raw value.
        let section: String
        /// The app that created the item, omitted when unknown.
        let bundleId: String?
    }

    struct ItemList: Codable, Equatable, Sendable {
        var version = LauncherURIPayload.version
        let items: [Item]
    }

    struct Profile: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let isActive: Bool
    }

    struct ProfileList: Codable, Equatable, Sendable {
        var version = LauncherURIPayload.version
        /// Omitted when no profile is active.
        let activeProfileId: String?
        let profiles: [Profile]

        init(profiles: [ProfileMetadata], activeProfileID: UUID?) {
            // An active ID with no manifest entry is a deleted profile, not one a launcher can show.
            let activeID = profiles.contains { $0.id == activeProfileID } ? activeProfileID : nil
            self.activeProfileId = activeID?.uuidString
            self.profiles = profiles.map {
                Profile(id: $0.id.uuidString, name: $0.name, isActive: $0.id == activeID)
            }
        }
    }

    struct Activation: Codable, Equatable, Sendable {
        var version = LauncherURIPayload.version
        let itemId: String
        let outcome: String
        /// Present only when outcome is completed.
        let reactionObserved: Bool?

        init(itemId: String, outcome: MenuBarItemActivationOutcome) {
            self.itemId = itemId
            switch outcome {
            case let .completed(reactionObserved):
                self.outcome = "completed"
                self.reactionObserved = reactionObserved
            case .itemUnavailable:
                self.outcome = "itemUnavailable"
                self.reactionObserved = nil
            case .permissionMissing:
                self.outcome = "permissionMissing"
                self.reactionObserved = nil
            case .activationFailed:
                self.outcome = "activationFailed"
                self.reactionObserved = nil
            }
        }
    }

    struct ProfileApplication: Codable, Equatable, Sendable {
        var version = LauncherURIPayload.version
        let profileId: String
        let outcome: String

        init(profileId: String, outcome: LauncherProfileApplyOutcome) {
            self.profileId = profileId
            self.outcome = outcome.rawValue
        }
    }
}

/// Builds launcher responses in the envelope thaw://get uses, plus the operation
/// so a receiver can check a callback against the request it sent.
nonisolated enum LauncherURIResponse {
    /// Stable error codes for requests that never reached an outcome.
    static let invalidRequest = "invalidRequest"
    static let permissionMissing = "permissionMissing"

    static func success(
        _ payload: some Encodable,
        operation: LauncherURIOperation,
        requestId: String
    ) -> [String: Any] {
        var response = envelope(operation: operation, requestId: requestId, status: "success")
        response["data"] = jsonObject(payload)
        return response
    }

    /// error is a stable code; details is for a human reading a log.
    static func failure(
        _ error: String,
        details: String,
        payload: (some Encodable)? = String?.none,
        operation: LauncherURIOperation,
        requestId: String
    ) -> [String: Any] {
        var response = envelope(operation: operation, requestId: requestId, status: "error")
        response["error"] = error
        response["details"] = details
        if let payload {
            response["data"] = jsonObject(payload)
        }
        return response
    }

    static func activation(
        itemId: String,
        outcome: MenuBarItemActivationOutcome,
        requestId: String
    ) -> [String: Any] {
        let payload = LauncherURIPayload.Activation(itemId: itemId, outcome: outcome)
        let details: String
        switch outcome {
        case .completed:
            return success(payload, operation: .activateItem, requestId: requestId)
        case .itemUnavailable:
            details = "No actionable menu bar item has this identifier"
        case .permissionMissing:
            details = "Accessibility permission is not granted"
        case .activationFailed:
            details = "The item did not respond to any activation method"
        }
        return failure(
            payload.outcome,
            details: details,
            payload: payload,
            operation: .activateItem,
            requestId: requestId
        )
    }

    static func profileApplication(
        profileId: String,
        outcome: LauncherProfileApplyOutcome,
        requestId: String
    ) -> [String: Any] {
        let payload = LauncherURIPayload.ProfileApplication(profileId: profileId, outcome: outcome)
        let details: String
        switch outcome {
        case .applied, .appliedWithoutLayout:
            return success(payload, operation: .applyProfile, requestId: requestId)
        case .profileUnavailable:
            details = "No saved profile has this identifier"
        case .applyFailed:
            details = "The profile could not be loaded"
        }
        return failure(
            payload.outcome,
            details: details,
            payload: payload,
            operation: .applyProfile,
            requestId: requestId
        )
    }

    private static func envelope(
        operation: LauncherURIOperation,
        requestId: String,
        status: String
    ) -> [String: Any] {
        [
            "requestId": requestId,
            "operation": operation.rawValue,
            "status": status,
        ]
    }

    /// The payload as a JSONSerialization object, so it can sit in the same
    /// dictionary envelope the settings responses use.
    private static func jsonObject(_ payload: some Encodable) -> Any {
        guard let data = try? JSONEncoder().encode(payload),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return [String: Any]()
        }
        return object
    }
}
