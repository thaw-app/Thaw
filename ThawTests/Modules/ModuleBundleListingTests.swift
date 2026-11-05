//
//  ModuleBundleListingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// What the live host lists as installed modules: the apps in each Modules folder.
@Suite("Module bundle listing")
struct ModuleBundleListingTests {
    @Test("Each folder's visible .app bundles are listed, and a missing folder adds nothing")
    func listsAppBundles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let user = root.appending(path: "user", directoryHint: .isDirectory)
        let bundled = root.appending(path: "bundled", directoryHint: .isDirectory)
        for folder in [user, bundled] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for path in ["user/Scripts.app", "user/.Hidden.app", "user/notes.txt", "bundled/Widgets.app"] {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        let missing = root.appending(path: "missing", directoryHint: .isDirectory)

        let names = ModuleHost.appBundles(in: [user, missing, bundled]).map(\.lastPathComponent)

        #expect(names.sorted() == ["Scripts.app", "Widgets.app"])
    }
}
