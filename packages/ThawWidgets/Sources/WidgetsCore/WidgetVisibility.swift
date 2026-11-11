//
//  WidgetVisibility.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Whether Thaw wants the widget icon hidden. Native hiding never switches off a bundle under
/// Thaw's own identifier, so Thaw lists the ones to hide in a file and announces each change.
/// Must match ExtraVisibilityChannel in Thaw.
enum WidgetVisibility {
    static func folder(host: String) -> URL {
        URL.applicationSupportDirectory.appending(path: host).appending(path: "StandIns")
    }

    static func notification(host: String) -> Notification.Name {
        Notification.Name("\(host).extra.visibility")
    }

    /// Whether bundleID is listed in the folder's file. A missing file hides nothing.
    static func isHidden(_ bundleID: String, in folder: URL) -> Bool {
        guard let text = try? String(contentsOf: folder.appending(path: "hidden-extras.txt"), encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { $0 == bundleID }
    }
}
