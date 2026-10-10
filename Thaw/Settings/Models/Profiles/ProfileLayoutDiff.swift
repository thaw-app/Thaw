//
//  ProfileLayoutDiff.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Compare the running bar with the profile using the apply pipeline's snapshot representation so the preview reflects actual changes.
nonisolated struct ProfileLayoutDiff: Equatable {
    /// An item named the way the preview should show it.
    struct Item: Equatable, Identifiable {
        /// The namespace:title uniqueIdentifier both snapshots key on.
        let id: String
        /// The namespace half of the identifier, which is a bundle ID for
        /// everything an app publishes.
        let bundleID: String
        /// The profile's custom name when it saved one, otherwise the title
        /// carried by the identifier.
        let title: String
    }

    /// An item the apply would move, and where it would move it.
    struct Move: Equatable, Identifiable {
        let item: Item
        let from: String
        let to: String

        var id: String {
            item.id
        }
    }

    /// One setting whose value differs between the profile and the app.
    struct SettingChange: Equatable, Identifiable {
        /// The coding key, used as the identity and as the fallback label.
        let key: String
        /// A readable name when one is known for key.
        let label: String

        var id: String {
            key
        }
    }

    /// Items that would change section, ordered visible to always-hidden so
    /// the list reads down the bar.
    var moves: [Move] = []

    /// Profile items absent from the bar, often quit or uninstalled apps; nothing to move is not an apply failure.
    var unavailable: [Item] = []

    /// Current items absent from the profile follow new-item placement rather than profile-determined sections.
    var unmentioned: [Item] = []

    /// Compare encoded snapshots so newly added settings appear without updating this type.
    var settingChanges: [SettingChange] = []

    /// A spacing offset differing from disk relaunches every menu bar app; the preview must warn about it.
    var relaunchingSpacingOffset: Int?

    /// Whether applying would leave the setup as it stands.
    var isEmpty: Bool {
        moves.isEmpty
            && unavailable.isEmpty
            && settingChanges.isEmpty
            && relaunchingSpacingOffset == nil
    }

    /// The section keys a layout snapshot stores, in menu bar display order.
    static let sectionKeys = ProfilePreviewModel.sectionKeys

    /// Fall back to savedSectionOrder on both sides, like ProfilePreviewModel, so profiles lacking itemOrder do not imply bar-wide moves.
    static func between(
        current: MenuBarLayoutSnapshot,
        profile: MenuBarLayoutSnapshot
    ) -> ProfileLayoutDiff {
        let currentSections = sectionAssignments(in: current)
        let profileSections = sectionAssignments(in: profile)

        var diff = ProfileLayoutDiff()

        for key in sectionKeys {
            let identifiers = (profile.itemOrder ?? profile.savedSectionOrder)[key] ?? []
            for identifier in identifiers {
                let item = item(identifier, named: profile.customNames)
                guard let from = currentSections[identifier] else {
                    diff.unavailable.append(item)
                    continue
                }
                if from != key {
                    diff.moves.append(Move(item: item, from: from, to: key))
                }
            }
        }

        for key in sectionKeys {
            let identifiers = (current.itemOrder ?? current.savedSectionOrder)[key] ?? []
            for identifier in identifiers where profileSections[identifier] == nil {
                diff.unmentioned.append(item(identifier, named: current.customNames))
            }
        }

        return diff
    }

    /// The section each identifier sits in, preferring the per-item map the
    /// apply pipeline treats as authoritative.
    private static func sectionAssignments(
        in layout: MenuBarLayoutSnapshot
    ) -> [String: String] {
        if let map = layout.itemSectionMap, !map.isEmpty {
            return map
        }
        var assignments = [String: String]()
        let order = layout.itemOrder ?? layout.savedSectionOrder
        for key in sectionKeys {
            for identifier in order[key] ?? [] {
                assignments[identifier] = key
            }
        }
        return assignments
    }

    private static func item(
        _ identifier: String,
        named customNames: [String: String]
    ) -> Item {
        let (namespace, title) = ProfilePreviewModel.split(identifier)
        return Item(
            id: identifier,
            bundleID: namespace,
            title: customNames[identifier] ?? title
        )
    }
}

// MARK: - Setting comparison

extension ProfileLayoutDiff {
    /// Unlisted keys fall back to word-split names so new settings remain visible without extending this table.
    private static let settingLabels: [String: String] = [
        "enableAlwaysHiddenSection": "Always-Hidden section",
        "hideApplicationMenus": "Hide application menus",
        "showOnHover": "Show on hover",
        "showOnClick": "Show on click",
        "showOnScroll": "Show on scroll",
        "autoRehide": "Auto-rehide",
        "rehideInterval": "Rehide interval",
        "useThawBar": "Thaw Bar",
        "thawBarLocation": "Thaw Bar location",
        "showThawIcon": "Show the Thaw icon",
        "thawIcon": "Thaw icon",
        "iconRefreshInterval": "Icon refresh interval",
        "enableMenuBarItemOverflow": "Menu bar item overflow",
        "enableExperimentalSystemItemHiding": "System item hiding",
        "sectionDividerStyle": "Section divider style",
    ]

    /// Compare encoded fields rather than a curated list so the preview cannot silently omit newly added settings.
    static func settingChanges(
        current: some Encodable,
        profile: some Encodable
    ) -> [SettingChange] {
        guard let currentFields = encodedFields(current),
              let profileFields = encodedFields(profile)
        else {
            return []
        }

        var changes = [SettingChange]()
        for key in Set(currentFields.keys).union(profileFields.keys).sorted() {
            let before = currentFields[key]
            let after = profileFields[key]
            guard !areEqual(before, after) else { continue }
            changes.append(SettingChange(key: key, label: label(for: key)))
        }
        return changes
    }

    private static func encodedFields(_ value: some Encodable) -> [String: Any]? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any]
        else {
            return nil
        }
        return fields
    }

    private static func areEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            (lhs as? NSObject)?.isEqual(rhs as? NSObject) ?? false
        default:
            false
        }
    }

    private static func label(for key: String) -> String {
        if let known = settingLabels[key] {
            return known
        }
        // Split camel case to give unlabelled settings readable names.
        var words = ""
        for character in key {
            if character.isUppercase, !words.isEmpty {
                words.append(" ")
                words.append(Character(character.lowercased()))
            } else {
                words.append(character)
            }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
