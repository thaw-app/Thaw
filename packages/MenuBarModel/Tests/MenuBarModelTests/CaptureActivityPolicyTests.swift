//
//  CaptureActivityPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

struct CaptureActivityPolicyTests {
    @Test(arguments: ["AudioVideoModule", "com.apple.menuextra.audiovideo"])
    func captureActivityNeverEntersManagedSections(title: String) {
        let hosts: [MenuBarItemTag.Namespace] = [.menuBarAgent, .controlCenter, .uuid(UUID())]
        for host in hosts {
            let tag = MenuBarItemTag(namespace: host, title: title)
            #expect(tag.sectionManagementPolicy == .excluded)
            #expect(!tag.isMovable)
        }
    }

    @Test(arguments: ["AudioVideoModule", "com.apple.menuextra.audiovideo"])
    func thirdPartyTitleDoesNotExcludeAnOrdinaryItem(title: String) {
        let tag = MenuBarItemTag(namespace: .string("com.example.recorder"), title: title)
        #expect(tag.sectionManagementPolicy == .hideable)
        #expect(tag.isMovable)
    }

    // The agent sorts the module row, so writes to the status row left the
    // indicator hidden; the module key resolves it.
    @Test(arguments: ["AudioVideoModule", "com.apple.menuextra.audiovideo"])
    func indicatorResolvesToItsModuleRow(title: String) {
        #expect(SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: title) == "module:AudioVideoModule")
    }
}
