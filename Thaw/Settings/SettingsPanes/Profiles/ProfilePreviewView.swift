//
//  ProfilePreviewView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
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
        MenuBarItemTag.persistentIdentifierParts(uniqueIdentifier) ?? (uniqueIdentifier, uniqueIdentifier)
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

    /// Pictures of the items in the bar now, keyed by canonical identifier.
    var liveImages: [String: MenuBarItemDisplayImage] = [:]

    /// Inline on the Profiles page, under the selected profile's name, the
    /// preview leaves out the name and takes the page's width.
    var isInline = false

    /// How many icons a section row shows before collapsing into "+N".
    private let maxIconsPerSection = 12

    /// How many changed items are listed before the rest become a count.
    private let maxListedChanges = 6

    private var sections: [ProfilePreviewModel.Section] {
        ProfilePreviewModel.sections(for: profile.menuBarLayout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            if !isInline {
                Text(profile.name)
                    .font(ThawType.heading)
            }

            if let diff {
                changeSummary(diff)
                Divider()
            }

            ForEach(sections, id: \.key) { section in
                sectionRow(section)
            }

            Divider()

            Text(settingsSummary)
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isInline ? 0 : 14)
        .frame(width: isInline ? nil : 360, alignment: .leading)
        .frame(maxWidth: isInline ? .infinity : nil, alignment: .leading)
    }

    private func changeSummary(_ diff: ProfileLayoutDiff) -> some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            Text("What will change")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThawInk.supporting)

            if diff.isEmpty {
                Text("Nothing. This profile matches the current setup.")
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            } else {
                if let offset = diff.relaunchingSpacingOffset {
                    Label(
                        "Sets item spacing to \(offset), which quits and reopens every menu bar app",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(ThawType.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(diff.moves.prefix(maxListedChanges)) { move in
                    HStack(spacing: ThawSpacing.tight) {
                        ItemIcon(identifier: move.item.id, liveImages: liveImages)
                        Text(move.item.title)
                            .font(ThawType.caption)
                        Text(sectionTitle(for: move.from))
                            .font(ThawType.caption)
                            .foregroundStyle(ThawInk.supporting)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(ThawInk.supporting)
                        Text(sectionTitle(for: move.to))
                            .font(ThawType.caption)
                            .foregroundStyle(ThawInk.supporting)
                    }
                }
                if diff.moves.count > maxListedChanges {
                    Text("and \(diff.moves.count - maxListedChanges) more moves")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
                reorderedSections(diff)

                if !diff.unavailable.isEmpty {
                    Text("\(diff.unavailable.count) saved items are not on the bar right now and will be left alone")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !diff.unmentioned.isEmpty {
                    Text("\(diff.unmentioned.count) items are not in this profile and keep their current section")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !diff.settingChanges.isEmpty {
                    Text("Settings: \(diff.settingChanges.map(\.label).formatted(.list(type: .and)))")
                        .font(ThawType.caption)
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
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            } else {
                HStack(spacing: ThawSpacing.tight) {
                    ForEach(section.items.prefix(maxIconsPerSection)) { item in
                        ItemIcon(identifier: item.id, liveImages: liveImages)
                            .help(item.title)
                    }
                    if section.items.count > maxIconsPerSection {
                        Text("+\(section.items.count - maxIconsPerSection)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(ThawInk.supporting)
                            .padding(.horizontal, 5)
                            .padding(.vertical, ThawSpacing.hairline)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            }
        }
    }

    private func reorderedSections(_ diff: ProfileLayoutDiff) -> some View {
        ForEach(diff.reorderedSections, id: \.self) { key in
            Text("Reorders items in \(Text(sectionTitle(for: key)))")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
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
        let general = profile.generalSettings
        parts.append(
            SimpleRehideChoice(
                autoRehide: general.autoRehide,
                strategy: RehideStrategy(rawValue: general.rehideStrategyRawValue) ?? Defaults.DefaultValue.rehideStrategy,
                interval: general.rehideInterval
            ).summaryLine
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

/// A saved item's live picture, else its symbol or app icon, else a placeholder.
private struct ItemIcon: View {
    /// The saved uniqueIdentifier (namespace:title).
    let identifier: String
    let liveImages: [String: MenuBarItemDisplayImage]

    /// Keeps a wide capture, such as a stats readout, from crowding the row.
    private static let maxWidth: CGFloat = 40

    var body: some View {
        if let liveImage = liveImages[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] {
            MenuBarItemGlyph(
                image: liveImage,
                fittingHeight: 18,
                reinksCaptures: true,
                drawnSize: Self.size(for: liveImage)
            )
        } else {
            Group {
                if let icon = ProfilePreviewModel.savedItemIcon(for: identifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(icon.isTemplate ? ThawInk.supporting : .primary)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .foregroundStyle(ThawInk.supporting)
                        .padding(ThawSpacing.hairline)
                }
            }
            .frame(width: 18, height: 18)
        }
    }

    private static func size(for image: MenuBarItemDisplayImage) -> CGSize {
        let fitted = image.targetSize(fittingHeight: 18)
        guard fitted.width > maxWidth, fitted.width > 0 else { return fitted }
        let scale = maxWidth / fitted.width
        return CGSize(width: maxWidth, height: fitted.height * scale)
    }
}

@MainActor
extension ProfilePreviewModel {
    /// Each bar item's picture as Layout picks it, keyed by canonical identifier.
    static func liveImages(in appState: AppState) -> [String: MenuBarItemDisplayImage] {
        var images = [String: MenuBarItemDisplayImage]()
        for section in MenuBarSection.Name.allCases {
            for item in appState.itemManager.managedItems(for: section) {
                let key = item.canonicalIdentifier
                images[key] = OverflowFallbackIcon.resolvedImage(
                    for: item,
                    section: section,
                    appState: appState,
                    capturedImage: appState.imageCache.image(for: item.tag)
                )
            }
        }
        return images
    }

    /// For an item not in the bar: its module symbol, Control Center's icon or its app's icon.
    /// Nil when nothing on this Mac matches.
    static func savedItemIcon(for identifier: String) -> NSImage? {
        let (namespace, title) = split(identifier)
        switch MenuBarItemTag.Namespace.string(namespace) {
        case .menuBarAgent:
            return SystemModuleGlyph.image(forItemTitle: title)
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return ControlCenterIcon.image
        default:
            return OverflowFallbackIcon.cachedAppIcon(forBundleIdentifier: namespace)
        }
    }
}
