//
//  DisplaySettingsManager+Live.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine

/// The live half of ``DisplaySettingsManager``, excluded from coverage
/// because it needs real display state, defaults, or modal alerts. New
/// decision logic belongs in DisplaySettingsManager.swift, not here.
extension DisplaySettingsManager {
    func performSetup(with appState: AppState) {
        self.appState = appState
        // Mirror the persisted mode first: capturing displays can apply
        // spacing, and that apply must see the user's mode, not the default.
        appState.spacingManager.spacingApplyMode = spacingApplyMode
        configureObservers()
        captureCurrentlyConnectedDisplays()
        seedSpacingOffsetFromActiveDisplay()
    }

    /// Copies the active display's offset into the spacing manager at launch.
    ///
    /// Otherwise the offset stays 0 on a plain launch while disk holds the
    /// user's value, so `applyProfile` would reset it and the notch overflow
    /// budget would mis-measure. Seeds only: `applyOffset()` would fire a
    /// relaunch wave for a value already in effect.
    private func seedSpacingOffsetFromActiveDisplay() {
        guard let appState else { return }
        let offset = activeDisplaySpacingOffset
        appState.spacingManager.offset = offset
        // Record the display as applied only when its spacing is really on
        // disk; a mismatch stays unrecorded so the next notification applies it.
        if appState.spacingManager.isOnDisk(offset: offset) {
            lastAppliedActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        }
        diagLog.debug("Seeded spacingManager.offset=\(offset) from the active display at setup")
    }

    /// Merges connected displays into the knownDisplays cache. Idempotent.
    ///
    /// Skips empty localizedName (mirrored displays, GPU/sleep transitions),
    /// which would add anonymous rows to the Displays pane.
    private func captureCurrentlyConnectedDisplays() {
        var updated = knownDisplays
        var changed = false
        var seededConfigurations = configurations
        var configurationsChanged = false
        for screen in NSScreen.screens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                continue
            }
            let trimmed = screen.localizedName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let entry = KnownDisplay(name: trimmed, hasNotch: screen.hasNotch)
            if updated[uuid] != entry {
                updated[uuid] = entry
                changed = true
            }
            // New displays inherit the global template; existing entries keep
            // their per-display overrides.
            if seededConfigurations[uuid] == nil {
                seededConfigurations[uuid] = globalConfiguration
                configurationsChanged = true
            }
        }
        if changed {
            knownDisplays = updated
        }
        if configurationsChanged {
            configurations = seededConfigurations
        }
    }

    // MARK: - System Spacing Seed

    /// Must match MenuBarItemSpacingManager.Key.defaultValue.
    private static let systemSpacingDefault = 16

    /// Reads NSStatusItemSpacing from the byHost global domain; nil when unset.
    private static func currentSystemSpacing() -> Int? {
        CFPreferencesCopyValue(
            "NSStatusItemSpacing" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int
    }

    /// Adopts a NSStatusItemSpacing set outside Thaw, so first launch doesn't
    /// fire a relaunch wave that resets it to 16. Saves to Defaults inline
    /// because persistence isn't wired yet at loadInitialState time.
    func seedConfigurationsFromSystemSpacing() {
        guard let onDisk = Self.currentSystemSpacing(),
              onDisk != Self.systemSpacingDefault
        else {
            return
        }
        let offset = Double(onDisk - Self.systemSpacingDefault)
        var seeded = configurations
        for screen in NSScreen.screens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                continue
            }
            if seeded[uuid] != nil {
                continue
            }
            seeded[uuid] = globalConfiguration.withItemSpacingOffset(offset)
        }
        guard seeded != configurations else { return }
        configurations = seeded
        do {
            let data = try encoder.encode(seeded)
            Defaults.set(data, forKey: .displayIceBarConfigurations)
            diagLog.info(
                "Seeded itemSpacingOffset=\(offset) from external NSStatusItemSpacing=\(onDisk) for \(seeded.count) display(s)"
            )
        } catch {
            diagLog.error("Failed to persist seeded per-display configurations: \(error)")
        }
    }

    // MARK: - Observers

    /// Persistence is handled by each property's `didSet`, not here.
    private func configureObservers() {
        var c = Set<AnyCancellable>()

        // Debounced: docking, lid close, KVM switches and the like post
        // several notifications within milliseconds, and each flap could
        // otherwise fire a relaunch wave. Cancel any previous setup's task.
        screenParametersTask?.cancel()
        screenParametersTask = debouncedNotificationTask(
            center: .default,
            name: NSApplication.didChangeScreenParametersNotification,
            interval: .seconds(1)
        ) { [weak self] in
            guard let self else { return }
            diagLog.info("Screen parameters changed — \(NSScreen.screens.count) screen(s) connected")
            captureCurrentlyConnectedDisplays()
            let currentUUID = Bridging.getActiveMenuBarDisplayUUID()
            if Self.shouldSkipSpacingApply(
                currentActiveDisplayUUID: currentUUID,
                lastAppliedActiveDisplayUUID: lastAppliedActiveDisplayUUID
            ) {
                diagLog.info("Active menu bar display unchanged (\(currentUUID ?? "nil")); skipping spacing apply")
                return
            }
            applyActiveDisplaySpacing(reason: "screenParametersChanged")
        }

        // External per-display settings changes via Settings URI.
        NotificationCenter.default
            .publisher(for: .perDisplaySettingsDidChangeViaURI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleExternalPerDisplaySettingsChange(notification)
            }
            .store(in: &c)

        cancellables = c
    }

    // MARK: - Spacing Apply

    /// Syncs the active display's offset and applies it. Safe on every change,
    /// since applyOffset no-ops when disk already matches. A real relaunch
    /// wave starts a settling period so layout waits for items to reattach.
    func applyActiveDisplaySpacing(reason: String) {
        guard let appState else { return }
        // A nil display resolves to the global template, not this display's spacing.
        guard Bridging.getActiveMenuBarDisplayUUID() != nil else {
            diagLog.info("Active menu bar display unknown; skipping spacing apply (\(reason))")
            return
        }
        let desired = activeDisplaySpacingOffset
        // Every apply except a Displays pane commit asks first. A declined display
        // transition marks the display as handled so it doesn't ask again; any
        // other decline writes the spacing still in effect back to the display.
        guard confirmSpacingRelaunchIfNeeded(forOffset: desired) else {
            if reason == "screenParametersChanged" {
                lastAppliedActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
            } else {
                keepEffectiveSpacing(offset: appState.spacingManager.offset)
            }
            diagLog.info("User declined the spacing relaunch confirmation (\(reason)); skipping apply")
            return
        }
        let previousAppliedUUID = lastAppliedActiveDisplayUUID
        let appliedUUID = Bridging.getActiveMenuBarDisplayUUID()
        lastAppliedActiveDisplayUUID = appliedUUID
        appState.spacingManager.offset = desired
        Task { [weak self] in
            guard let self else { return }
            // Suppress late-arriver re-sorts during the wave. Cancelled below
            // if applyOffset is a no-op.
            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:\(reason):preflight")
            do {
                let outcome = try await appState.spacingManager.applyOffset()
                if outcome.didRelaunch {
                    appState.itemManager.startSettlingPeriod(
                        reason: "spacingRelaunch:\(reason)",
                        expectedBundleIDs: outcome.recoveredBundleIDs
                    )
                    // Relaunched apps reattach at default positions, and
                    // auto-switch won't fire for an unchanged profile.
                    appState.profileManager.reapplyActiveProfile()
                } else {
                    appState.itemManager.cancelSettlingPeriod(
                        reason: "spacingRelaunch:\(reason):noOp"
                    )
                }
            } catch {
                appState.itemManager.cancelSettlingPeriod(
                    reason: "spacingRelaunch:\(reason):error"
                )
                // Roll back so the next notification retries, unless a newer
                // apply overwrote the bookkeeping meanwhile.
                if lastAppliedActiveDisplayUUID == appliedUUID {
                    lastAppliedActiveDisplayUUID = previousAppliedUUID
                }
                diagLog.error("applyActiveDisplaySpacing(\(reason)) failed: \(error)")
            }
        }
    }

    /// Returns false when the user declines a relaunch they should be asked
    /// about, true when the apply can go ahead.
    ///
    /// Internal so the profile apply goes through the same gate.
    func confirmSpacingRelaunchIfNeeded(forOffset offset: Int) -> Bool {
        guard let appState else { return true }
        guard Self.needsSpacingRelaunchConfirmation(
            isUserInitiated: isCommittingUserSpacingChange,
            confirmationsEnabled: confirmSpacingRelaunch,
            willRelaunch: appState.spacingManager.willRelaunch(forOffset: offset)
        ) else {
            return true
        }
        return presentSpacingRelaunchConfirmation()
    }

    /// App-modal so it shows with Settings closed. Returns whether the user
    /// approved. The suppression checkbox only takes effect on Apply.
    private func presentSpacingRelaunchConfirmation() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Apply menu bar spacing change?")
        alert.informativeText = String(localized: "Applying this spacing change will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost.")
        alert.addButton(withTitle: String(localized: "Apply"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let apply = alert.runModal() == .alertFirstButtonReturn
        if apply, alert.suppressionButton?.state == .on {
            confirmSpacingRelaunch = false
        }
        return apply
    }
}
