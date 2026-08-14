//
//  ProfilePreviewView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ProfilePreviewModel

/// Pure data shaping for the profile preview popover, kept separate from the
/// view so identifier parsing and section assembly are unit-testable.
nonisolated enum ProfilePreviewModel {
    struct Item: Identifiable, Equatable {
        /// The item's uniqueIdentifier (`namespace:title`) from the snapshot.
        let id: String
        /// The namespace half of the identifier — effectively a bundle ID.
        let bundleID: String
        /// The custom name when one was saved, otherwise the identifier title.
        let title: String
    }

    struct Section: Equatable {
        let key: String
        let items: [Item]
    }

    /// The section keys a layout snapshot stores, in menu bar display order.
    static let sectionKeys = ["visible", "hidden", "alwaysHidden"]

    /// Splits a `namespace:title` uniqueIdentifier. Identifiers written by
    /// `savedSectionOrder` (older profiles) are bare bundle IDs without a
    /// colon; those parse as namespace-only with the bundle ID as title.
    static func split(_ uniqueIdentifier: String) -> (namespace: String, title: String) {
        guard let colon = uniqueIdentifier.firstIndex(of: ":") else {
            return (uniqueIdentifier, uniqueIdentifier)
        }
        return (
            String(uniqueIdentifier[..<colon]),
            String(uniqueIdentifier[uniqueIdentifier.index(after: colon)...])
        )
    }

    /// Assembles the preview sections from a layout snapshot.
    ///
    /// Reads through ``MenuBarLayoutSnapshot/resolvedItemOrder`` rather than
    /// picking between `itemOrder` and `savedSectionOrder` here, so the
    /// preview shows what an apply would actually do. That property already
    /// handles the legacy fallback, and it also treats an *empty* `itemOrder`
    /// as absent — a capture taken while the bar was settling writes `[:]`,
    /// which a plain `??` would show as a profile with no items at all.
    static func sections(for layout: MenuBarLayoutSnapshot) -> [Section] {
        let order = layout.resolvedItemOrder
        return sectionKeys.map { key in
            let items = (order[key] ?? []).map { identifier in
                let (namespace, title) = split(identifier)
                return Item(
                    id: identifier,
                    bundleID: namespace,
                    title: layout.customNames[identifier] ?? title
                )
            }
            return Section(key: key, items: items)
        }
    }

    struct SpacingRow: Identifiable, Equatable {
        /// `"global"` for the profile-wide value, otherwise the display UUID.
        let id: String
        /// The resolved display name; nil for the global row.
        let displayName: String?
        /// The stored `itemSpacingOffset`, in points.
        let offset: Double
    }

    /// Assembles the spacing summary #887 asked the preview to include: the
    /// profile-wide offset first, then each stored display override, sorted
    /// by resolved name so the order is stable no matter how the dictionary
    /// iterates. Zero is the default and changes nothing, so zero offsets
    /// add no row.
    static func spacingRows(
        for profile: Profile,
        displayNames: [String: String]
    ) -> [SpacingRow] {
        var rows: [SpacingRow] = []
        let global = profile.globalDisplayConfiguration.itemSpacingOffset
        if global != 0 {
            rows.append(SpacingRow(id: "global", displayName: nil, offset: global))
        }
        let overrides = profile.displayConfigurations
            .filter { $0.value.itemSpacingOffset != 0 }
            .map { (id: $0.key, name: displayNames[$0.key] ?? $0.key, offset: $0.value.itemSpacingOffset) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for override in overrides {
            rows.append(SpacingRow(id: override.id, displayName: override.name, offset: override.offset))
        }
        return rows
    }
}

// MARK: - ProfilePreviewView

/// The popover shown from a profile row: the saved item order per section
/// rendered as app icons, plus the profile's key behavior settings.
struct ProfilePreviewView: View {
    let profile: Profile

    /// Display UUID → user-facing name, for labeling per-display spacing
    /// overrides. Rows for displays not in the map fall back to the UUID.
    var displayNames: [String: String] = [:]

    /// How many icons a section row shows before collapsing into "+N".
    private let maxIconsPerSection = 12

    private var sections: [ProfilePreviewModel.Section] {
        ProfilePreviewModel.sections(for: profile.menuBarLayout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(profile.name)
                .font(.headline)

            ForEach(sections, id: \.key) { section in
                sectionRow(section)
            }

            Divider()

            Text(settingsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let spacingSummary {
                Text(spacingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }

    private func sectionRow(_ section: ProfilePreviewModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sectionTitle(for: section.key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if section.items.isEmpty {
                // Reuses the catalog's existing, fully translated key rather
                // than introducing "No items", which shipped untranslated.
                Text("No items in this section")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 4) {
                    ForEach(section.items.prefix(maxIconsPerSection)) { item in
                        ItemIcon(bundleID: item.bundleID)
                            .help(item.title)
                    }
                    if section.items.count > maxIconsPerSection {
                        Text("+\(section.items.count - maxIconsPerSection)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            }
        }
    }

    private func sectionTitle(for key: String) -> LocalizedStringKey {
        switch key {
        case "visible": "Visible"
        case "hidden": "Hidden"
        case "alwaysHidden": "Always-Hidden"
        default: LocalizedStringKey(key)
        }
    }

    private var settingsSummary: String {
        var parts: [String] = []
        parts.append(
            profile.generalSettings.autoRehide
                ? String(localized: "Auto-rehide on")
                : String(localized: "Auto-rehide off")
        )
        parts.append(
            profile.generalSettings.useIceBar
                ? String(localized: "\(Constants.displayName) Bar on")
                : String(localized: "\(Constants.displayName) Bar off")
        )
        if profile.generalSettings.showOnHover {
            parts.append(String(localized: "Show on hover"))
        }
        if profile.generalSettings.showOnScroll {
            parts.append(String(localized: "Show on scroll"))
        }
        return parts.joined(separator: " · ")
    }

    /// One caption line for the saved spacing, or nil when every offset is
    /// at its default and the profile carries no spacing to preview.
    private var spacingSummary: String? {
        let rows = ProfilePreviewModel.spacingRows(for: profile, displayNames: displayNames)
        guard !rows.isEmpty else {
            return nil
        }
        let parts = rows.map { row in
            let value = row.offset.formatted(.number.sign(strategy: .always()))
            if let name = row.displayName {
                return String(localized: "\(name) \(value) pt")
            }
            return String(localized: "Global \(value) pt")
        }
        return String(localized: "Spacing: \(parts.joined(separator: " · "))")
    }
}

// MARK: - ItemIcon

/// A small app icon resolved from a bundle ID, with a generic fallback for
/// apps that are no longer installed.
private struct ItemIcon: View {
    let bundleID: String

    var body: some View {
        Group {
            if let icon = resolvedIcon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var resolvedIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
