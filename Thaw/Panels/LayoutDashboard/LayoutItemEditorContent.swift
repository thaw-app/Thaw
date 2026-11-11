//
//  LayoutItemEditorContent.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// What the Layout window's item editor shows for the current selection.
enum LayoutItemEditorContent {
    case empty
    case single(MenuBarItem, section: MenuBarSectionName)
    /// The shared section, or nil when the items are in different ones.
    case several(count: Int, section: MenuBarSectionName?)

    /// Reads the items and their sections from the cache the bars and the list read.
    @MainActor
    static func make(selectedIDs: [String], itemCache: MenuBarItemManager.ItemCache) -> Self {
        var found = [(MenuBarItem, MenuBarSectionName)]()
        for id in selectedIDs {
            for section in MenuBarSectionName.allCases {
                if let item = itemCache[section].first(where: { $0.uniqueIdentifier == id }) {
                    found.append((item, section))
                    break
                }
            }
        }
        switch found.count {
        case 0:
            return .empty
        case 1:
            return .single(found[0].0, section: found[0].1)
        default:
            let sections = Set(found.map(\.1))
            return .several(count: found.count, section: sections.count == 1 ? sections.first : nil)
        }
    }
}

/// The owning app as the editor shows it.
@MainActor
struct LayoutItemAppDetails {
    let name: String?
    let url: URL?
    let isRunning: Bool
    /// Apple's items name an internal process such as MenuBarAgent, so the editor says "macOS" instead.
    let isPartOfMacOS: Bool
    /// Thaw's own modules, such as Widgets, run in helpers that have no icon or app to open.
    let isPartOfThaw: Bool

    init(item: MenuBarItem) {
        let bundleID: String? = if case let .string(id) = item.tag.namespace {
            id
        } else {
            nil
        }
        isPartOfMacOS = bundleID?.hasPrefix("com.apple.") ?? false
        isPartOfThaw = bundleID.map { Self.isThawModule($0) } ?? false
        let running = item.sourceApplication.flatMap { $0.isTerminated ? nil : $0 }
        isRunning = running != nil
        url = running?.bundleURL ?? bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        name = running?.localizedName ?? url.map { FileManager.default.displayName(atPath: $0.path) }
    }

    /// Thaw's modules name their items under Thaw's own identifier, such as "<Thaw's ID>.module.widgets".
    static func isThawModule(_ bundleID: String, thawIdentifier: String = Constants.bundleIdentifier) -> Bool {
        bundleID.hasPrefix(thawIdentifier + ".")
    }
}

/// The editor's Name field against the stored name, kept apart so tests can read the rules.
@MainActor
enum LayoutItemNameDraft {
    static let fieldWidth: CGFloat = 220

    /// The item's stored custom name, or empty. Reading the revision redraws a view when it changes.
    static func stored(for item: MenuBarItem) -> String {
        _ = MenuBarItemCustomNamesRevision.shared.value
        return item.customName ?? ""
    }

    /// The draft after the stored name changed: the new name, unless the person is typing one of their own.
    static func following(draft: String, oldStored: String, newStored: String, isEditing: Bool) -> String {
        isEditing && draft != oldStored ? draft : newStored
    }

    /// The name to save, or nil when the draft says what is stored already.
    static func commit(draft: String, stored: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        return trimmed == stored ? nil : trimmed
    }
}
