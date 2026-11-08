//
//  ProfileExportBuilder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Builds what an export writes: one profile or all of them, each with its
/// current scripts, manifest switches and apply shortcut.
@MainActor
enum ProfileExportBuilder {
    /// Export All's file, and the profiles that could not be read into it.
    struct AllProfiles {
        var bundle: ProfileExportBundle
        var unreadableNames: [String]
    }

    static func entry(for profile: Profile, meta: ProfileMetadata?, shortcuts: ProfileApplyShortcuts = .init()) -> ProfileExportEntry {
        ProfileExportEntry(
            profile: profile.withCurrentScripts(moduleDefaults: .scriptsModule),
            associatedDisplayUUID: meta?.associatedDisplayUUID,
            associatedDisplayName: meta?.associatedDisplayName,
            associatedSpaceKey: meta?.associatedSpaceKey,
            associatedSpaceName: meta?.associatedSpaceName,
            keepsLayoutChanges: meta?.keepsLayoutChangesSetting,
            reappliesAtLaunch: meta?.reappliesAtLaunchSetting,
            applyShortcut: shortcuts.shortcut(for: profile.id)
        )
    }

    /// A profile that fails to load is named, not dropped without a word.
    static func all(
        _ metadata: [ProfileMetadata],
        load: (UUID) throws -> Profile,
        shortcuts: ProfileApplyShortcuts = .init()
    ) -> AllProfiles {
        var entries = [ProfileExportEntry]()
        var unreadable = [String]()
        for meta in metadata {
            guard let profile = try? load(meta.id) else {
                unreadable.append(meta.name)
                continue
            }
            entries.append(entry(for: profile, meta: meta, shortcuts: shortcuts))
        }
        return AllProfiles(bundle: ProfileExportBundle(entries: entries), unreadableNames: unreadable)
    }
}
