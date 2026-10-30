//
//  ScratchDefaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Throwaway settings suites, named by paths in the temporary folder so nothing lands in ~/Library/Preferences.
/// Removing is main actor only, since it posts a defaults change the app observes on the main thread.
@MainActor
enum ScratchDefaults {
    /// A new suite name for one test: a path in the temporary folder.
    static nonisolated func name(_ prefix: String) -> String {
        folder.appending(path: "\(prefix).\(UUID().uuidString)").path
    }

    private static nonisolated let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ThawTestDefaults", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static func remove(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(atPath: name + ".plist")
    }

    /// The stores installStore(named:) replaced, most recent last.
    private static var replacedStores: [UserDefaults] = []

    /// Points Defaults at the suite name. On the main actor, since pointing
    /// it somewhere new registers defaults, which the app observes there.
    static func installStore(named name: String) throws {
        guard let store = UserDefaults(suiteName: name) else {
            throw CocoaError(.featureUnsupported)
        }
        replacedStores.append(Defaults.store)
        Defaults.store = store
    }

    /// Puts back the store installStore(named:) replaced and deletes the suite.
    static func restoreStore(removing name: String) {
        if let previous = replacedStores.popLast() {
            Defaults.store = previous
        }
        remove(name)
    }

    /// Runs body with Defaults reading and writing a throwaway suite, then
    /// puts the real store back and deletes the suite.
    static func withStore(named prefix: String, _ body: (UserDefaults) throws -> Void) throws {
        let name = name(prefix)
        try installStore(named: name)
        defer { restoreStore(removing: name) }
        try body(Defaults.store)
    }
}

/// Lets one scratch-store test at a time hold Defaults.store, from install to
/// restore. The trait awaits between those steps, so without it a test in
/// another suite could install its own store in between.
private actor ScratchDefaultsGate {
    static let shared = ScratchDefaultsGate()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Points Defaults at a throwaway suite for each test it covers, then puts the
/// previous store back and deletes the suite. Defaults.store is one global, so
/// tests using this trait run one at a time, across suites too. Profile managers
/// made during the test, including an AppState's, use a throwaway folder too.
nonisolated struct ScratchDefaultsTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase _: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        let name = ScratchDefaults.name(String(test.name.filter { $0.isLetter || $0.isNumber }))
        let gate = ScratchDefaultsGate.shared
        await gate.acquire()
        do {
            try await ScratchDefaults.installStore(named: name)
        } catch {
            await gate.release()
            throw error
        }
        let profiles = FileManager.default.temporaryDirectory
            .appending(path: "ThawTestProfiles/\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: profiles) }
        do {
            try await ProfileManager.$directoryOverride.withValue(profiles) {
                try await function()
            }
        } catch {
            await ScratchDefaults.restoreStore(removing: name)
            await gate.release()
            throw error
        }
        await ScratchDefaults.restoreStore(removing: name)
        await gate.release()
    }
}

extension Trait where Self == ScratchDefaultsTrait {
    /// Runs each test against a throwaway Defaults.store.
    static var scratchDefaults: Self {
        Self()
    }
}

/// Runs body with SettingsURIHandler announcing changes on a private center,
/// so the live settings models never hear a test's writes.
@MainActor
func withPrivateSettingsChangeCenter(_ body: () throws -> Void) rethrows {
    let previousCenter = SettingsURIHandler.settingsChangeNotificationCenter
    SettingsURIHandler.settingsChangeNotificationCenter = NotificationCenter()
    defer { SettingsURIHandler.settingsChangeNotificationCenter = previousCenter }
    try body()
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
        let name = ScratchDefaults.name(prefix)
        names.append(name)
        return UserDefaults(suiteName: name)
    }
}
