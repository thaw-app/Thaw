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

    init(item: MenuBarItem) {
        let bundleID: String? = if case let .string(id) = item.tag.namespace {
            id
        } else {
            nil
        }
        isPartOfMacOS = bundleID?.hasPrefix("com.apple.") ?? false
        let running = item.sourceApplication.flatMap { $0.isTerminated ? nil : $0 }
        isRunning = running != nil
        url = running?.bundleURL ?? bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        name = running?.localizedName ?? url.map { FileManager.default.displayName(atPath: $0.path) }
    }
}
