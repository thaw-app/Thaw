//
//  ScratchSuites.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Throwaway settings for one test. Suites are named by paths in the temporary folder, so neither they
/// nor the empty file the preferences daemon leaves after a delete land in ~/Library/Preferences.
@MainActor
public final class ScratchSuites {
    private let prefix: String
    private var names = [String]()

    public init(prefix: String) {
        self.prefix = prefix
    }

    isolated deinit {
        names.forEach(Self.remove)
    }

    public func make() -> UserDefaults? {
        let name = Self.name(prefix)
        names.append(name)
        return UserDefaults(suiteName: name)
    }

    /// A new suite name for one test: a path in the temporary folder.
    public static nonisolated func name(_ prefix: String) -> String {
        folder.appending(path: "\(prefix).\(UUID().uuidString)").path
    }

    private static nonisolated let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ThawTestDefaults", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    public static func remove(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(atPath: name + ".plist")
    }
}
