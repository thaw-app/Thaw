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

/// The live half of ``DisplaySettingsManager``: everything whose substance
/// needs a running `AppState`, real `NSScreen`/WindowServer display state,
/// the on-disk NSStatusItemSpacing global domain, or an app-modal alert.
/// None of that can run in a unit test, so this file is excluded from
/// coverage in sonar-project.properties.
///
/// The measured half (DisplaySettingsManager.swift) keeps persistence,
/// lookup, mutation, URI handling, and every decision rule — including
/// `shouldSkipSpacingApply`, which this file's observer consults. New
/// decision logic belongs there, not here.
extension DisplaySettingsManager {
    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
        captureCurrentlyConnectedDisplays()
    }

    /// Merges info for currently-connected displays into the knownDisplays
    /// cache. Idempotent and cheap; called on launch and on every
    /// screen-parameters-changed notification so the cache always reflects
    /// the latest known names.
    ///
    /// Skips screens whose localizedName is empty: that can happen for
    /// mirrored slave displays or briefly during GPU/sleep transitions, and
    /// caching such entries pollutes the Displays pane with anonymous rows.
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
            // Seed an entry for newly-detected displays from the current
            // global template so first-time connections inherit the
            // user's chosen defaults instead of falling through to
            // DisplayIceBarConfiguration.defaultConfiguration at read time.
            // Existing entries are left alone so per-display overrides
            // are preserved across reconnects.
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

    /// Default baseline for NSStatusItemSpacing and NSStatusItemSelectionPadding,
    /// kept in sync with MenuBarItemSpacingManager.Key.defaultValue. Used to
    /// translate on-disk system spacing into Thaw's relative offset model.
    private static let systemSpacingDefault = 16

    /// Reads the current system value for NSStatusItemSpacing from the byHost
    /// global domain. Returns nil when the key is unset, letting callers
    /// distinguish "user has explicitly configured spacing" from "macOS
    /// default applies".
    private static func currentSystemSpacing() -> Int? {
        CFPreferencesCopyValue(
            "NSStatusItemSpacing" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int
    }

    /// When the user has manually set NSStatusItemSpacing outside of Thaw
    /// (e.g. via a defaults write in Terminal), seed an entry for each
    /// connected display whose itemSpacingOffset corresponds to that on-disk
    /// value. Without this, applyActiveDisplaySpacing on first launch reads
    /// the default offset of 0, computes target = 16, sees on-disk = N, and
    /// fires a relaunch wave that rewrites the user's manual setting back to
    /// 16. The seeded entries are written to Defaults inline because the
    /// persistence sink is not yet wired at loadInitialState time; without
    /// the explicit save, subsequent launches would re-seed on every start
    /// instead of remembering the adopted value. The padding key is not
    /// consulted because Thaw drives both keys from a single offset; users
    /// whose padding diverges from spacing will see one normalising relaunch
    /// on first launch but no recurring waves thereafter.
    ///
    /// Internal rather than private because `loadInitialState()` — which
    /// stays in the measured file — calls it on first launch.
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

    /// Configures the manager's non-persistence internal observers: the
    /// debounced screen-parameters watcher and the Settings-URI notification
    /// subscription. Property persistence is now driven by `didSet` on each
    /// property (see the property declarations in the measured file),
    /// replacing the previous `$property.persistToDefaults`/manual
    /// `.dropFirst()` sinks.
    private func configureObservers() {
        var c = Set<AnyCancellable>()

        // Listen for display connect/disconnect to log changes, refresh the
        // known-display cache, and re-derive the active display's spacing.
        //
        // Debounced because didChangeScreenParametersNotification fires
        // repeatedly during a single user action: docking, lid close,
        // monitor sleep/wake, KVM switch, Sidecar handshake, and external
        // display flicker can each post several notifications within a
        // few hundred milliseconds. Without the debounce, every flap
        // could trigger a relaunch wave (the no-op guard catches the
        // common case but does not cover oscillating values during the
        // flap window). One second coalesces a single docking event into
        // one apply.
        //
        // First swift-async-algorithms adoption site: a NotificationCenter
        // observer feeds an AsyncStream that `.debounce(for:)` coalesces,
        // replacing Combine's `.debounce(for:scheduler:)`. Behaviour is
        // identical — the two per-event skips are `continue` (skip this
        // notification), not loop exit.
        let (screenParameterEvents, screenParameterContinuation) = AsyncStream<Void>.makeStream()
        // A repeated setup must not leave the previous task — and the
        // NotificationCenter observer its defer owns — running.
        screenParametersTask?.cancel()
        screenParametersTask = Task { @MainActor [weak self] in
            // The observer is owned by this task: added when it starts and
            // removed when it ends (cancellation ends the for-await loop, which
            // runs the defer). This keeps the non-Sendable observer token off
            // the class so the nonisolated deinit only needs to cancel the task.
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in screenParameterContinuation.yield(()) }
            defer { NotificationCenter.default.removeObserver(observer) }
            for await _ in screenParameterEvents.debounce(for: .seconds(1)) {
                guard let self else { break }
                diagLog.info("Screen parameters changed — \(NSScreen.screens.count) screen(s) connected")
                captureCurrentlyConnectedDisplays()
                let currentUUID = Bridging.getActiveMenuBarDisplayUUID()
                if Self.shouldSkipSpacingApply(
                    currentActiveDisplayUUID: currentUUID,
                    lastAppliedActiveDisplayUUID: lastAppliedActiveDisplayUUID
                ) {
                    diagLog.info("Active menu bar display unchanged (\(currentUUID ?? "nil")); skipping spacing apply")
                    continue
                }
                applyActiveDisplaySpacing(reason: "screenParametersChanged")
            }
        }

        // Re-deriving the active display's spacing whenever per-display
        // configurations change (user edit, profile load) is now handled by
        // `configurations`'s `didSet`. The no-op guard inside applyOffset()
        // makes this free when on-disk already matches.

        // Listen for external per-display settings changes via Settings URI
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

    /// Reads the active display's spacing offset, syncs it into
    /// spacingManager.offset, and triggers applyOffset. The no-op guard
    /// inside applyOffset skips when on-disk values already match, so this
    /// is safe to call on every configurations change. On a real relaunch
    /// wave, kicks off a settling period so a subsequent applyProfileLayout
    /// (e.g. from a profile switch) waits for items to re-attach before
    /// moving them.
    ///
    /// Internal rather than private because `configurations`'s `didSet` —
    /// which stays in the measured file — re-derives spacing through it.
    func applyActiveDisplaySpacing(reason: String) {
        guard let appState else { return }
        let desired = Int(configurationForActiveDisplay().itemSpacingOffset.rounded())
        // A display transition can fire the relaunch wave with no warning.
        // When confirmations are enabled and this apply would actually
        // relaunch apps, ask the user first. Declining keeps the current
        // on-disk spacing and leaves lastAppliedActiveDisplayUUID untouched
        // so the next genuine transition re-prompts. The in-pane Apply and
        // global broadcast carry their own confirmations, so only the
        // automatic path is gated here.
        if reason == "screenParametersChanged",
           confirmSpacingRelaunch,
           appState.spacingManager.willRelaunch(forOffset: desired),
           !presentSpacingRelaunchConfirmation()
        {
            diagLog.info("User declined the spacing relaunch confirmation for a display transition; skipping apply")
            return
        }
        let previousAppliedUUID = lastAppliedActiveDisplayUUID
        let appliedUUID = Bridging.getActiveMenuBarDisplayUUID()
        lastAppliedActiveDisplayUUID = appliedUUID
        appState.spacingManager.offset = desired
        Task { [weak self] in
            guard let self else { return }
            // Preflight settling so intermediate late-arriver re-sorts and
            // restore logic are suppressed while the wave runs. Cancelled
            // below if applyOffset turns out to be a no-op.
            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:\(reason):preflight")
            do {
                let outcome = try await appState.spacingManager.applyOffset()
                if outcome.didRelaunch {
                    appState.itemManager.startSettlingPeriod(
                        reason: "spacingRelaunch:\(reason)",
                        expectedBundleIDs: outcome.recoveredBundleIDs
                    )
                    // The relaunched apps reattach at OS-default positions.
                    // Drive the active profile's layout pass so they end up
                    // in the saved order. Auto-switch doesn't fire when the
                    // associated profile is unchanged, so without this call
                    // the post-settle path would only run cross-section
                    // restore and leave within-section ordering untouched.
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
                // Roll back the bookkeeping so the next screen-parameter
                // notification is not skipped as a same-display fire and can
                // retry the failed apply. A newer apply may have overwritten
                // it while applyOffset was in flight; its bookkeeping wins.
                if lastAppliedActiveDisplayUUID == appliedUUID {
                    lastAppliedActiveDisplayUUID = previousAppliedUUID
                }
                diagLog.error("applyActiveDisplaySpacing(\(reason)) failed: \(error)")
            }
        }
    }

    /// Presents an app-modal confirmation before a display transition fires
    /// the relaunch wave. Returns true when the user approves the relaunch,
    /// false when they cancel. Runs modally so it surfaces even with the
    /// Settings window closed; ticking the suppression checkbox while pressing
    /// Apply turns confirmSpacingRelaunch off so future transitions apply
    /// silently. Cancelling never changes that setting.
    private func presentSpacingRelaunchConfirmation() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Apply menu bar spacing change?")
        alert.informativeText = String(localized: "When a display transition requires Thaw to apply a different menu bar spacing, Thaw relaunches apps with menu bar items. Relaunching apps may cause unsaved input, progress, or transient app state to be lost.")
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
