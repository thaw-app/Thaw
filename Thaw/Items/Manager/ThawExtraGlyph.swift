//
//  ThawExtraGlyph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The picture of one of Thaw's own stand-in items, for surfaces that fall
/// back to an app icon: the stand-in bundles have none.
///
/// A slot shows the icon Thaw handed it; an Apple extra's stand-in shows the
/// symbol its helper draws, read from the helper's own bundle.
@MainActor
enum ThawExtraGlyph {
    static func image(for item: MenuBarItem) -> NSImage? {
        guard case let .string(bundleID) = item.tag.namespace else { return nil }
        if let slot = ItemStandInSlot(bundleIdentifier: bundleID) {
            return slotImage(slot)
        }
        let prefix = "\(ThawMenuBarIdentity.bundleIdentifier).extra."
        guard bundleID.hasPrefix(prefix),
              let standIn = SystemExtraStandIn(rawValue: String(bundleID.dropFirst(prefix.count)))
        else { return nil }
        let image = (standIn == .airDrop ? airDropSymbol() : nil)
            ?? NSImage(systemSymbolName: symbolName(for: standIn), accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// Whether an item is one of Thaw's stand-ins. Their images are bare symbols with
    /// no margin of their own, so previews draw them at their own size, not tile-filling.
    nonisolated static func isStandIn(_ tag: MenuBarItemTag) -> Bool {
        guard case let .string(bundleID) = tag.namespace else { return false }
        return SystemExtraStandIn.owns(bundleIdentifier: bundleID) || ItemStandInSlot(bundleIdentifier: bundleID) != nil
    }

    /// Slot images are capped at the height the menu bar draws them.
    private static let slotImageMaxHeight: CGFloat = 18

    private static func slotImage(_ slot: ItemStandInSlot) -> NSImage? {
        let folder = ItemStandInSlot.folder
        guard let image = NSImage(contentsOf: folder.appending(path: "slot\(slot.number).png")) else { return nil }
        if image.size.height > slotImageMaxHeight {
            image.size = NSSize(width: image.size.width * slotImageMaxHeight / image.size.height, height: slotImageMaxHeight)
        }
        image.isTemplate = FileManager.default.fileExists(atPath: folder.appending(path: "slot\(slot.number).template").path)
        return image
    }

    /// The symbol the helper's own bundle names; see
    /// scripts/assemble-extra-helper.sh.
    private static func symbolName(for standIn: SystemExtraStandIn) -> String {
        Bundle(url: standIn.bundleURL)?.object(forInfoDictionaryKey: "ThawExtraSymbol") as? String
            ?? "questionmark.circle"
    }

    /// AirDrop's own glyph is a private system symbol; see AirDropGlyph in
    /// ThawExtraHelper.
    private static func airDropSymbol() -> NSImage? {
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:accessibilityDescription:")
        guard NSImage.responds(to: selector) else { return nil }
        return NSImage.perform(selector, with: "airdrop", with: nil)?.takeUnretainedValue() as? NSImage
    }
}
