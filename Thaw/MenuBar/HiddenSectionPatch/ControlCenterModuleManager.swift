//
//  ControlCenterModuleManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Governs the menu-bar visibility of Apple Control Center modules that the
/// macOS 27 Assessment Mode allowlist *cannot* individually hide.
///
/// The 2026-06-18 investigation proved Assessment Mode is all-or-nothing for
/// system items: its allowlist keeps the core modules (raw values 0...8 — Wi-Fi,
/// Bluetooth, Sound, …) and collateral-hides the rest (AirDrop, Focus, User,
/// Now Playing) as a group, with no per-item control either way. So the *only*
/// way to hide any one CC module on demand is Control Center's own **per-host**
/// preference:
///
///     defaults -currentHost write com.apple.controlcenter <Key> -int <2|8>
///
/// where `2` shows the module in the menu bar and `8` hides it (empirically
/// confirmed via a reversible AirDrop flip-test). The change only takes effect
/// after Control Center is relaunched (it reads the preference at launch), so
/// this manager restarts it whenever it mutates a value.
///
/// This is a *separate subsystem* from ``AssessmentModeBackend``: governed
/// modules are stripped from the assessment allowlist input and handled here.
///
/// **Inherent limitation (the residual collateral):** while *any* assessment
/// restriction is active — i.e. whenever a non-CC (third-party) item is hidden —
/// the non-core extras (AirDrop / Focus / User / Now Playing) are collateral-
/// hidden by the OS regardless of their preference, and nothing in the API can
/// keep them (`MBAssessmentModeConfiguration` exposes only systemItems +
/// bundleIdentifiers). They self-heal when the restriction lifts. The core
/// modules (Wi-Fi / Bluetooth) are unaffected by that collateral, so per-item
/// CC-pref hiding is fully reliable for them.
@MainActor
final class ControlCenterModuleManager {
    /// Injectable side effects used to read and mutate Control Center state.
    /// Keeping these operations actor-isolated makes the production manager
    /// Swift 6-safe while allowing tests to use an in-memory preference domain.
    @MainActor
    struct Environment {
        let readValue: @MainActor (String) -> Int?
        let writeValue: @MainActor (Int?, String) -> Bool
        let synchronize: @MainActor () -> Void
        let restartControlCenter: @MainActor () -> Void

        static var live: Environment {
            Environment(
                readValue: { ControlCenterModuleManager.readValue(forKey: $0) },
                writeValue: { ControlCenterModuleManager.writeValue($0, forKey: $1) },
                synchronize: { ControlCenterModuleManager.synchronize() },
                restartControlCenter: { ControlCenterModuleManager.restartControlCenter() }
            )
        }
    }

    /// An exact snapshot of a preference before Thaw changes it. Absence is
    /// distinct from an explicit value so teardown can remove keys that did not
    /// exist before Thaw started managing the module.
    private enum OriginalPreference {
        case absent
        case value(Int)

        init(_ value: Int?) {
            self = value.map(Self.value) ?? .absent
        }

        var value: Int? {
            switch self {
            case .absent:
                nil
            case let .value(value):
                value
            }
        }
    }

    /// Maps a MenuBarAgent extra's AX title to its Control Center per-host
    /// preference key.
    ///
    /// AirDrop / NowPlaying / UserSwitcher / Bluetooth / WiFi are confirmed keys
    /// present in the live `com.apple.controlcenter` per-host domain. Focus has
    /// no key until the module is customized; `FocusModes` is the conventional
    /// name and is written speculatively (a wrong key is an inert no-op, never
    /// harmful).
    static nonisolated let moduleKeysByMenuExtraTitle: [String: String] = [
        "com.apple.menuextra.airdrop": "AirDrop",
        "com.apple.menuextra.bluetooth": "Bluetooth",
        "com.apple.menuextra.wifi": "WiFi",
        "com.apple.menuextra.now-playing": "NowPlaying",
        "com.apple.menuextra.user": "UserSwitcher",
        "com.apple.menuextra.focusmode": "FocusModes",
    ]

    /// The per-host preference value that shows a module in the menu bar.
    static nonisolated let shownValue = 2

    /// The per-host preference value that hides a module from the menu bar.
    static nonisolated let hiddenValue = 8

    private static let domain = "com.apple.controlcenter" as CFString
    private static let controlCenterBundleID = "com.apple.controlcenter"

    private let diagLog = DiagLog(category: "ControlCenterModuleManager")
    private let environment: Environment

    /// The menu-extra titles currently hidden by this manager.
    private var appliedHidden: Set<String> = []

    /// The exact pre-hide preference to restore for each hidden module.
    private var originalValues: [String: OriginalPreference] = [:]

    /// Retains the block-based termination observer for the app's lifetime (this
    /// manager is owned by `SimpleItemHider`, which lives the whole session).
    private var terminationObserver: NSObjectProtocol?

    init(
        environment: Environment = .live,
        notificationCenter: NotificationCenter = .default
    ) {
        self.environment = environment

        // Restore the user's modules if Thaw quits while it has any hidden, so a
        // CC-pref hide never outlives the app that applied it.
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreAll() }
        }
    }

    isolated deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: Identifier helpers

    /// The governable menu-extra title embedded in an item `uniqueIdentifier`
    /// such as `com.apple.MenuBarAgent:com.apple.menuextra.airdrop`, or `nil` if
    /// the identifier is not one of the Control Center modules this manager owns.
    static nonisolated func governableMenuExtraTitle(forItemIdentifier identifier: String) -> String? {
        for title in moduleKeysByMenuExtraTitle.keys
            where identifier == title || identifier.hasSuffix(":\(title)")
        {
            return title
        }
        return nil
    }

    /// Whether the given item `uniqueIdentifier` is a Control Center module this
    /// manager governs (and therefore should be kept out of the assessment-mode
    /// allowlist input).
    static nonisolated func isGovernable(itemIdentifier identifier: String) -> Bool {
        governableMenuExtraTitle(forItemIdentifier: identifier) != nil
    }

    // MARK: Apply

    /// Hides exactly the given set of governable menu-extra titles via their
    /// Control Center preference, restoring any module no longer in the set.
    ///
    /// Restarts Control Center only when a preference value actually changes, so
    /// the steady-state 1s refresh is a no-op once the desired set is applied.
    ///
    /// - Returns: `true` if any preference changed (and Control Center was
    ///   restarted), `false` otherwise.
    @discardableResult
    func apply(hiddenMenuExtraTitles titles: Set<String>) -> Bool {
        let desired = titles.filter { Self.moduleKeysByMenuExtraTitle[$0] != nil }
        guard desired != appliedHidden else {
            return false
        }

        var changed = false

        for title in desired.subtracting(appliedHidden) {
            guard let key = Self.moduleKeysByMenuExtraTitle[title] else { continue }
            originalValues[title] = OriginalPreference(environment.readValue(key))
            if environment.writeValue(Self.hiddenValue, key) {
                changed = true
            }
        }

        for title in appliedHidden.subtracting(desired) {
            guard let key = Self.moduleKeysByMenuExtraTitle[title] else { continue }
            let restore = originalValues.removeValue(forKey: title) ?? .value(Self.shownValue)
            if environment.writeValue(restore.value, key) {
                changed = true
            }
        }

        appliedHidden = desired

        if changed {
            environment.synchronize()
            environment.restartControlCenter()
            diagLog.info("applied CC module visibility; hidden=\(desired.sorted())")
        }
        return changed
    }

    /// Restores every module this manager has hidden to its pre-hide value. Used
    /// on teardown / app termination so a CC-pref hide never persists past Thaw.
    func restoreAll() {
        apply(hiddenMenuExtraTitles: [])
    }

    // MARK: Preference I/O

    private static func readValue(forKey key: String) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (value as? NSNumber)?.intValue
    }

    @discardableResult
    private static func writeValue(_ value: Int?, forKey key: String) -> Bool {
        if readValue(forKey: key) == value {
            return false
        }
        if let value {
            CFPreferencesSetValue(
                key as CFString,
                value as CFNumber,
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        } else {
            CFPreferencesSetValue(
                key as CFString,
                nil,
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        return true
    }

    private static func synchronize() {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// Sends SIGTERM to the running Control Center so it relaunches and re-reads
    /// the preference. Control Center is a managed launch agent and restarts
    /// itself automatically within ~1-2s.
    private static func restartControlCenter() {
        for app in NSWorkspace.shared.runningApplications
            where app.bundleIdentifier == controlCenterBundleID
        {
            kill(app.processIdentifier, SIGTERM)
        }
    }
}
