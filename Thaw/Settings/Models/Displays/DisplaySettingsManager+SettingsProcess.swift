//
//  DisplaySettingsManager+SettingsProcess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// What keeps the display settings of the app and of its settings process the same, and has the
/// app do what the settings process can't: only the app can restart the menu bar apps.
extension DisplaySettingsManager {
    /// Every display's settings and the template, as one process hands them to the other.
    struct Snapshot: Codable, Equatable {
        var configurations: [String: DisplayThawBarConfiguration]
        var globalConfiguration: DisplayThawBarConfiguration
    }

    var snapshot: Snapshot {
        Snapshot(configurations: configurations, globalConfiguration: globalConfiguration)
    }

    /// Takes the other process's settings. Only a value that differs is assigned, so settings
    /// that stayed the same save and apply nothing.
    func adopt(_ snapshot: Snapshot) {
        if globalConfiguration != snapshot.globalConfiguration {
            globalConfiguration = snapshot.globalConfiguration
        }
        if configurations != snapshot.configurations {
            configurations = snapshot.configurations
        }
    }

    /// Reads the stored display settings again after the other process saved them. A value that differs is
    /// assigned as if the page had set it, so the app applies new spacing; a missing key leaves its value alone.
    func loadStoredValues() {
        let decoder = JSONDecoder()
        func stored<Value: Decodable>(_: Value.Type, _ key: Defaults.Key) -> Value? {
            Defaults.data(forKey: key).flatMap { try? decoder.decode(Value.self, from: $0) }
        }
        // The mode and the confirmation come first: a configuration change applies spacing under them.
        if let mode = Defaults.string(forKey: .spacingApplyMode).flatMap(SpacingApplyMode.init(rawValue:)), mode != spacingApplyMode {
            spacingApplyMode = mode
        }
        if let confirms = Defaults.object(forKey: .confirmSpacingRelaunch) as? Bool, confirms != confirmSpacingRelaunch {
            confirmSpacingRelaunch = confirms
        }
        if let scope = Defaults.string(forKey: .unconfirmedSpacingProfileScope).flatMap(SpacingProfileSaveScope.init(rawValue:)),
           scope != unconfirmedSpacingProfileScope
        {
            unconfirmedSpacingProfileScope = scope
        }
        wideDisplayRule.loadStoredValues()
        if let known = stored([String: KnownDisplay].self, .knownDisplays)?.filter({ !$0.value.name.trimmingCharacters(in: .whitespaces).isEmpty }),
           known != knownDisplays
        {
            knownDisplays = known
        }
        adopt(Snapshot(
            configurations: stored([String: DisplayThawBarConfiguration].self, .displayThawBarConfigurations) ?? configurations,
            globalConfiguration: stored(DisplayThawBarConfiguration.self, .globalDisplayConfiguration) ?? globalConfiguration
        ))
    }

    /// The Reapply Spacing button. In the settings process the question is asked there, and the
    /// app restarts the menu bar apps.
    func requestSpacingReapply(
        forDisplayUUID displayID: String,
        remote: SettingsRemote? = .current,
        confirm: (@MainActor () -> Bool)? = nil
    ) {
        guard let remote else { return reapplySpacing(forDisplayUUID: displayID) }
        guard !isReapplyingSpacing, displayID == activeMenuBarDisplayUUID else { return }
        let asks = Self.needsSpacingRelaunchConfirmation(applyMode: spacingApplyMode, confirmationsEnabled: confirmSpacingRelaunch)
        if asks, !(confirm ?? presentSpacingRelaunchConfirmation)() {
            return
        }
        remote.perform(DisplaysSettingsLink.reapplySpacing, displayID)
    }

    /// Reapplies spacing for the settings process, where the person already answered the question.
    func reapplySpacingConfirmedInSettingsProcess(forDisplayUUID displayID: String) {
        let ask = spacingHost?.confirmRelaunch
        spacingHost?.confirmRelaunch = { true }
        defer { spacingHost?.confirmRelaunch = ask }
        reapplySpacing(forDisplayUUID: displayID)
    }
}

extension WideDisplayRule {
    /// Reads the stored rule again, after the other process saved it.
    func loadStoredValues() {
        let enabled = Defaults.bool(forKey: .showEveryItemOnWideDisplays)
        if enabled != isEnabled {
            isEnabled = enabled
        }
        let width = Defaults.double(forKey: .wideDisplayMinimumWidth)
        if width != minimumWidth {
            minimumWidth = width
        }
    }
}
