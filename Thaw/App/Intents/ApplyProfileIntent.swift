//
//  ApplyProfileIntent.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Reuse the Focus filter's ProfileEntity and ProfileEntityQuery so profile names and manifest reads stay shared.
// Unlike hotkeys, intents carry a profile ID; call ProfileManager directly to share the settings pane's hooks, spacing, and layout path.

import AppIntents
import AppKit

/// Failure modes worth naming to the user. Anything else (a corrupt profile
/// file, a disk error) surfaces as the underlying ProfileManager error.
enum ThawIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    /// Thaw is not running, or is still coming up, so there is no app state.
    case appNotReady
    /// The entity identifier is not a UUID, possibly from a stale shortcut.
    case profileNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            "Thaw isn't running yet. Open Thaw and try again."
        case .profileNotFound:
            "That menu bar profile no longer exists."
        }
    }
}

/// Awaits the profile's layout task so the next Shortcuts action does not run while items are moving.
struct ApplyProfileIntent: AppIntent {
    // AppIntent reflects these mutable static properties off-actor; set them once and never reassign.
    static nonisolated(unsafe) var title: LocalizedStringResource = "Apply Menu Bar Profile"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Apply a saved Thaw menu bar profile, restoring its layout and settings.",
        categoryName: "Profiles"
    )

    @Parameter(title: "Profile")
    var profile: ProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appState = thawAppState() else {
            throw ThawIntentError.appNotReady
        }
        guard let profileID = UUID(uuidString: profile.id) else {
            throw ThawIntentError.profileNotFound
        }

        let loaded = try await appState.profileManager.applyProfileAwaitingLayout(id: profileID, to: appState)

        // Keyboard and Stream Deck workflows have no visible dialog, so acknowledge them with the HUD.
        // Skip it when settings is key, since the Profiles pane already marks the active profile.
        if !isSettingsWindowKey {
            ThawHUD.show(symbol: "person.crop.rectangle.stack", text: "Profile applied")
        }

        return .result(dialog: IntentDialog("Applied \(loaded.name)."))
    }

    /// A cheap key-window check; a false negative costs only a redundant HUD.
    /// Match the prefix because SwiftUI adds non-contractual identifier suffixes; Thaw panels are never key.
    @MainActor
    private var isSettingsWindowKey: Bool {
        guard let identifier = NSApp?.keyWindow?.identifier?.rawValue else {
            return false
        }
        return identifier.hasPrefix(ThawWindowIdentifier.settings.rawValue)
    }
}
