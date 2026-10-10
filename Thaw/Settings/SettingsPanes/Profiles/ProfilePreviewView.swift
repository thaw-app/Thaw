//
//  ProfilePreviewView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - ProfilePreviewModel

/// Pure data shaping for the profile preview popover, kept separate from the
/// view so identifier parsing and section assembly are unit-testable.
nonisolated enum ProfilePreviewModel {
    struct Item: Identifiable, Equatable {
        /// The item's uniqueIdentifier (namespace:title) from the snapshot.
        let id: String
        /// The namespace half of the identifier, effectively a bundle ID.
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

    /// Splits a namespace:title uniqueIdentifier. Identifiers written by
    /// savedSectionOrder (older profiles) are bare bundle IDs without a
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

    /// Assembles the preview sections from a layout snapshot, preferring the
    /// per-item order and falling back to the legacy bundle-ID order for
    /// profiles saved before itemOrder existed.
    static func sections(for layout: MenuBarLayoutSnapshot) -> [Section] {
        let order = layout.itemOrder ?? layout.savedSectionOrder
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
}

// MARK: - ProfilePreviewView

/// The popover shown from a profile row: what applying it would change about
/// the bar as it stands, then the saved item order per section rendered as app
/// icons, plus the profile's key behavior settings.
///
/// The change list comes first because it is the question asked in front of an
/// Apply button. The saved contents stayed below it: they are what a user
/// looks at to tell two similar profiles apart, which the diff cannot answer
/// once the profile is already active and the diff is empty.
struct ProfilePreviewView: View {
    let profile: Profile

    /// What applying would change, or nil when the caller could not read the
    /// running layout. Passed in rather than computed here so the popover does
    /// not walk the item cache during a view update.
    var diff: ProfileLayoutDiff?

    /// How many icons a section row shows before collapsing into "+N".
    private let maxIconsPerSection = 12

    /// How many changed items are listed before the rest become a count.
    private let maxListedChanges = 6

    private var sections: [ProfilePreviewModel.Section] {
        ProfilePreviewModel.sections(for: profile.menuBarLayout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            Text(profile.name)
                .font(ThawType.heading)

            if let diff {
                changeSummary(diff)
                Divider()
            }

            ForEach(sections, id: \.key) { section in
                sectionRow(section)
            }

            Divider()

            Text(settingsSummary)
                .font(.caption)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }

    private func changeSummary(_ diff: ProfileLayoutDiff) -> some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            Text("What will change")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThawInk.supporting)

            if diff.isEmpty {
                Text("Nothing. This profile matches the current setup.")
                    .font(.caption)
                    .foregroundStyle(ThawInk.supporting)
            } else {
                if let offset = diff.relaunchingSpacingOffset {
                    Label(
                        "Sets item spacing to \(offset), which quits and reopens every menu bar app",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(diff.moves.prefix(maxListedChanges)) { move in
                    HStack(spacing: ThawSpacing.tight) {
                        ItemIcon(bundleID: move.item.bundleID)
                        Text(move.item.title)
                            .font(.caption)
                        Text(sectionTitle(for: move.from))
                            .font(.caption)
                            .foregroundStyle(ThawInk.supporting)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(ThawInk.supporting)
                        Text(sectionTitle(for: move.to))
                            .font(.caption)
                            .foregroundStyle(ThawInk.supporting)
                    }
                }
                if diff.moves.count > maxListedChanges {
                    Text("and \(diff.moves.count - maxListedChanges) more moves")
                        .font(.caption)
                        .foregroundStyle(ThawInk.supporting)
                }

                if !diff.unavailable.isEmpty {
                    Text("\(diff.unavailable.count) saved items are not on the bar right now and will be left alone")
                        .font(.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !diff.unmentioned.isEmpty {
                    Text("\(diff.unmentioned.count) items are not in this profile and keep their current section")
                        .font(.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !diff.settingChanges.isEmpty {
                    Text("Settings: \(diff.settingChanges.map(\.label).formatted(.list(type: .and)))")
                        .font(.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionRow(_ section: ProfilePreviewModel.Section) -> some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            Text(sectionTitle(for: section.key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThawInk.supporting)

            if section.items.isEmpty {
                Text("No items")
                    .font(.caption)
                    .foregroundStyle(ThawInk.supporting)
            } else {
                HStack(spacing: ThawSpacing.tight) {
                    ForEach(section.items.prefix(maxIconsPerSection)) { item in
                        ItemIcon(bundleID: item.bundleID)
                            .help(item.title)
                    }
                    if section.items.count > maxIconsPerSection {
                        Text("+\(section.items.count - maxIconsPerSection)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(ThawInk.supporting)
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
        case "alwaysHidden": "Always Hidden"
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
            profile.generalSettings.useThawBar
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
                    .foregroundStyle(ThawInk.supporting)
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
