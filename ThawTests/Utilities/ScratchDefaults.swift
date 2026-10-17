//
//  ScratchDefaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Removing a throwaway suite's domain leaves an empty plist in ~/Library/Preferences, so this deletes the file too.
/// Main actor only, since removing a domain posts a defaults change the app observes on the main thread.
@MainActor
enum ScratchDefaults {
    static func remove(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(at: URL.libraryDirectory.appending(path: "Preferences/\(name).plist"))
    }
}

/// Throwaway suites made for one test, removed when the test lets go of them.
@MainActor
final class ScratchSuites {
    private let prefix: String
    private var names = [String]()

    init(prefix: String) {
        self.prefix = prefix
    }

    isolated deinit {
        names.forEach(ScratchDefaults.remove)
    }

    func make() -> UserDefaults? {
        let name = "\(prefix).\(UUID().uuidString)"
        names.append(name)
        return UserDefaults(suiteName: name)
    }
}
