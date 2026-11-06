//
//  MenuBarItemManager+OpenMethods.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

extension MenuBarItemManager {
    func openMethodIdentity(for item: MenuBarItem) -> OpenMethodIdentity {
        let bundleURL = NSRunningApplication(processIdentifier: resolvedPID(for: item))?.bundleURL
        let version = bundleURL
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleVersion"] as? String } ?? ""
        return OpenMethodIdentity(
            key: MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier),
            appVersion: version
        )
    }
}
