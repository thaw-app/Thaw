//
//  ExtraVisibilityChannel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Hides Thaw's extra and module bundles itself: Control Center's app list may have no record of
/// them, and native hiding never switches off a bundle under Thaw's own identifier.
/// Must match ExtraVisibilityChannel in ThawExtraHelper and WidgetVisibility in the Widgets module.
@MainActor
enum ExtraVisibilityChannel {
    private static let log = DiagLog(category: "SystemExtraStandIn")
    private static var lastHidden: Set<String>?

    static func ownsBundle(_ bundleID: String) -> Bool {
        let own = ThawMenuBarIdentity.bundleIdentifier
        return bundleID.hasPrefix("\(own).extra.") || bundleID.hasPrefix("\(own).module.")
    }

    /// Bundles native hiding must not switch off in the system's Menu Bar list: the extras, which are
    /// hidden through this channel, and Thaw itself, which would lose its icon and both dividers.
    static func keepsOffSystemList(_ bundleID: String) -> Bool {
        bundleID == ThawMenuBarIdentity.bundleIdentifier || ownsBundle(bundleID)
    }

    static var file: URL {
        file(in: ItemStandInSlot.folder)
    }

    static func file(in folder: URL) -> URL {
        folder.appending(path: "hidden-extras.txt")
    }

    static var notification: Notification.Name {
        Notification.Name("\(ThawMenuBarIdentity.bundleIdentifier).extra.visibility")
    }

    static func hide(_ bundleIDs: Set<String>) {
        hide(bundleIDs, folder: ItemStandInSlot.folder, announce: announceChange)
    }

    /// The folder and the announcement are parameters so tests write to a scratch folder and post nothing.
    static func hide(_ requested: Set<String>, folder: URL, announce: () -> Void) {
        let bundleIDs = requested.filter(ownsBundle)
        guard bundleIDs != lastHidden else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bundleIDs.sorted().joined(separator: "\n").write(to: file(in: folder), atomically: true, encoding: .utf8)
        } catch {
            log.error("could not write hidden extras: \(error.localizedDescription)")
            return
        }
        lastHidden = bundleIDs
        announce()
        log.info("hidden extras: \(bundleIDs.sorted())")
    }

    private static func announceChange() {
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
