//
//  ItemStandInSlot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// One of the fixed stand-in bundles for third-party items macOS won't draw.
///
/// macOS 27 hides and orders items per bundle, and a bundle identifier cannot
/// be made up at runtime without breaking the signature, so a fixed set of
/// slot bundles ships inside the app. Must match ExtraRole and
/// SlotStandInChannel in ThawExtraHelper.
nonisolated struct ItemStandInSlot: Hashable, Comparable {
    static let all = (1 ... 6).map(ItemStandInSlot.init(number:))

    let number: Int

    var bundleIdentifier: String {
        "\(ThawMenuBarIdentity.bundleIdentifier).extra.slot\(number)"
    }

    var autosaveName: String {
        "Thaw.Extra.Slot\(number)"
    }

    /// The persistent identifier the stand-in's item gets in the layout.
    var itemIdentifier: String {
        MenuBarItemTag.canonicalPersistentIdentifier("\(bundleIdentifier):\(autosaveName)")
    }

    var bundleURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/Extras/Thaw Stand-In \(number).app")
    }

    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: ThawMenuBarIdentity.bundleIdentifier).appending(path: "StandIns")
    }

    var updateNotification: Notification.Name {
        Notification.Name("\(ThawMenuBarIdentity.bundleIdentifier).extra.slot\(number).update")
    }

    static var clickNotification: Notification.Name {
        Notification.Name("\(ThawMenuBarIdentity.bundleIdentifier).extra.slot.clicked")
    }

    static func < (lhs: ItemStandInSlot, rhs: ItemStandInSlot) -> Bool {
        lhs.number < rhs.number
    }

    /// The slot a bundle identifier belongs to, if it is one.
    init?(bundleIdentifier: String) {
        let prefix = "\(ThawMenuBarIdentity.bundleIdentifier).extra.slot"
        guard bundleIdentifier.hasPrefix(prefix), let number = Int(bundleIdentifier.dropFirst(prefix.count)),
              (1 ... 6).contains(number)
        else { return nil }
        self.number = number
    }

    /// The slot a menu bar item belongs to, if it is a stand-in.
    init?(tag: MenuBarItemTag) {
        guard case let .string(bundleIdentifier) = tag.namespace else { return nil }
        self.init(bundleIdentifier: bundleIdentifier)
    }

    /// The name of the item a stand-in draws, for MenuBarItem.displayName.
    static func label(for tag: MenuBarItemTag) -> String? {
        guard let slot = ItemStandInSlot(tag: tag) else { return nil }
        let labels = UserDefaults.standard.dictionary(forKey: "MenuBarItemManager.itemStandInLabels") as? [String: String]
        return labels?[slot.bundleIdentifier]
    }

    private init(number: Int) {
        self.number = number
    }
}
