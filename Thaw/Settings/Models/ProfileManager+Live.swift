//
//  ProfileManager+Live.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// The live half of ``ProfileManager``: everything whose substance needs a
/// running `AppState` — pushing snapshots into live managers, the spacing
/// relaunch wave, WindowServer display identity via Bridging, Carbon hotkey
/// registration, and Focus Filter intents. None of that can run in a unit
/// test, so this file is excluded from coverage in sonar-project.properties.
///
/// The measured half (ProfileManager.swift) keeps the manifest, file CRUD,
/// capture, and every decision rule. New decision logic belongs there, not
/// here; methods in this file should stay thin orchestration over measured
/// primitives, mirroring the MenuBarItemManager / LayoutSolver split.
extension ProfileManager {
    /// Sets up the manager with the app state and configures auto-switch.
    /// If the current display has an associated profile, it is applied
    /// after the menu bar has settled.
    func performSetup(with appState: AppState) {
        self.appState = appState
        lastActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        rebuildProfileHotkeys()

        // Before anything can apply a profile. Once per build, because each
        // build is the only thing that can widen what pruning recognizes as
        // unmatchable — repeating it within a build would rewrite the same
        // files to the same bytes on every launch.
        repairPersistedLayoutsIfNeeded()

        // Note: profiles' didSet already calls rebuildProfileHotkeys() for
        // every assignment after this class's own init, so no explicit
        // subscription is needed here (see the doc comment on `profiles`).

        startObservationTasks()

        // Check if a Focus Filter is currently active. If so, apply it;
        // otherwise fall back to display-based profile.
        Task { [weak self] in
            guard let self else { return }
            do {
                let current = try await ThawFocusFilter.current
                if current.profile != nil {
                    // Re-run perform() to apply the Focus Filter profile.
                    _ = try await current.perform()
                    await self.applyFocusFilterProfile()
                    return
                }
            } catch {
                diagLog.debug("No active Focus Filter on startup: \(error)")
            }
            // No Focus Filter; fall back to display-based profile.
            // The spacing apply runs unconditionally; its no-op guard
            // skips the relaunch when on-disk values already match the
            // active profile's offset, but if the user is booting on a
            // display whose profile has a different offset than the last
            // session left on-disk, the relaunch must happen here or the
            // apps will continue rendering with the wrong spacing.
            if let currentUUID = lastActiveDisplayUUID {
                await self.applyProfileForDisplay(uuid: currentUUID)
            }
        }
    }

    // MARK: - AppState-Sourced Capture

    /// Captures the current app state and saves it as a named profile.
    func saveProfile(name: String, from appState: AppState) throws {
        try saveProfile(
            name: name,
            settings: appState.settings,
            appearanceManager: appState.appearanceManager,
            itemManager: appState.itemManager
        )
    }

    /// Overwrites an existing profile with the current app state,
    /// keeping its id, name, display association, and creation date.
    func updateProfileWithCurrentState(id: UUID, appState: AppState) throws {
        try updateProfileWithCurrentState(
            id: id,
            settings: appState.settings,
            appearanceManager: appState.appearanceManager,
            itemManager: appState.itemManager
        )
    }

    /// Updates a profile with only the specified scope of current state.
    func updateProfile(id: UUID, scope: ProfileUpdateScope, appState: AppState) throws {
        try updateProfile(
            id: id,
            scope: scope,
            settings: appState.settings,
            appearanceManager: appState.appearanceManager,
            itemManager: appState.itemManager
        )
    }

    // MARK: - Apply

    /// Applies a profile's settings to the running app state.
    ///
    /// The menu bar item spacing offset is applied after the snapshot is
    /// pushed, driving the per-profile spacing behaviour. The no-op guard
    /// inside applyOffset skips the relaunch when the on-disk values
    /// already match, so identical-offset switches cost nothing.
    ///
    /// previousProfileID is the active profile ID before this apply was
    /// initiated. Callers capture it before they overwrite
    /// self.activeProfileID, so it can be surfaced to hooks via the
    /// THAW_PREVIOUS_PROFILE_ID env var.
    func applyProfile(
        _ profile: Profile,
        to appState: AppState,
        previousProfileID: UUID? = nil
    ) {
        diagLog.debug(
            "applyProfile entered: name=\(profile.name)"
        )

        // Cancel any in-flight layout task before starting a new one.
        // Prevents two profile applies from fighting over item positions.
        layoutTask?.cancel()
        layoutGeneration &+= 1
        let generation = layoutGeneration

        let pinnedHidden = Set(profile.menuBarLayout.pinnedHiddenBundleIDs)
        let pinnedAlwaysHidden = Set(profile.menuBarLayout.pinnedAlwaysHiddenBundleIDs)
        let sectionOrder = profile.menuBarLayout.savedSectionOrder
        let itemSectionMap = profile.menuBarLayout.resolvedItemSectionMap
        let itemOrder = profile.menuBarLayout.resolvedItemOrder

        // Snapshot hook config before entering the task. Resolving
        // global hooks inside the Task would still work; doing it now
        // keeps the read on the main actor with the rest of the prep.
        let globalPre = HookScript.loadGlobal(.pre)
        let globalPost = HookScript.loadGlobal(.post)
        let profilePre = profile.automation?.preHook
        let profilePost = profile.automation?.postHook

        let previousName = previousProfileID.flatMap { id in
            profiles.first(where: { $0.id == id })?.name
        }
        let baseContext = (
            profileID: profile.id,
            profileName: profile.name,
            previousID: previousProfileID,
            previousName: previousName
        )

        layoutTask = Task { [weak self] in
            // 1. Pre-hooks. Global runs first so it can do common setup;
            //    profile-specific runs second so it can override or extend.
            await HookRunner.runIfEnabled(globalPre, context: HookRunner.Context(
                phase: .pre,
                scope: .global,
                profileID: baseContext.profileID,
                profileName: baseContext.profileName,
                previousProfileID: baseContext.previousID,
                previousProfileName: baseContext.previousName
            ))
            if Task.isCancelled {
                return
            }
            await HookRunner.runIfEnabled(profilePre, context: HookRunner.Context(
                phase: .pre,
                scope: .profile,
                profileID: baseContext.profileID,
                profileName: baseContext.profileName,
                previousProfileID: baseContext.previousID,
                previousProfileName: baseContext.previousName
            ))
            if Task.isCancelled {
                return
            }

            // 2. Snapshot apply: push profile settings into the running
            //    app state.
            self?.applySnapshot(profile, to: appState)

            // Take the offset from the configuration the snapshot just
            // installed, rather than trusting whatever spacingManager
            // happens to be holding. The push that normally keeps it in
            // sync lives in configurations.didSet, which guards on
            // oldValue != configurations, so applying a profile whose
            // display configurations already match the live ones — the
            // usual case, since the profile is where they came from —
            // leaves the offset at its launch value of 0. applyOffset()
            // below would then write the system default over the user's
            // spacing and relaunch every menu bar app to do it.
            appState.spacingManager.offset = appState.settings.displaySettings
                .activeDisplaySpacingOffset

            // Run the spacing apply BEFORE the layout pass. Otherwise the
            // two race: applyOffset() kills and relaunches every menu bar
            // app, so any positioning the layout task did up to that
            // point is wiped when items reappear at the OS default
            // insertion point. The no-op guard inside applyOffset()
            // returns immediately when the on-disk values already match,
            // so identical-offset switches add no latency.
            //
            // After the relaunch wave, restart a settling period so
            // applyProfileLayout's wait-for-settling loop blocks until
            // items have actually re-attached. Without this, the settling
            // flag is false (no performSetup to set it), the wait passes
            // through, and applyProfileLayout positions items that
            // haven't come back yet, leaving them at OS-default positions.

            // Preflight settling: flip isInStartupSettling on BEFORE the
            // wave so cacheItemsRegardless skips late-arriver detection
            // and scheduleProfileResort short-circuits while apps are
            // dying and respawning. Without this, on a notch display
            // each intermediate cache cycle triggers a partial full-sort
            // that gets cancelled by the next; only the run after the
            // wave settles produces the correct layout.
            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:preflight")

            let didRelaunch: Bool
            let recovered: Set<String>
            do {
                let outcome = try await appState.spacingManager.applyOffset()
                didRelaunch = outcome.didRelaunch
                recovered = outcome.recoveredBundleIDs
            } catch is CancellationError {
                // The task was cancelled, typically because a newer
                // layoutTask is taking over. Drop the preflight settling
                // and bail out so we don't apply a stale layout pass on
                // top of the new task's work.
                appState.itemManager.cancelSettlingPeriod(reason: "spacingRelaunch:cancelled")
                return
            } catch {
                self?.diagLog.error("spacingRelaunch: applyOffset failed: \(error)")
                didRelaunch = false
                recovered = []
            }
            if didRelaunch {
                appState.itemManager.startSettlingPeriod(
                    reason: "spacingRelaunch",
                    expectedBundleIDs: recovered
                )
            } else {
                // No-op apply: nothing churned, drop the preflight so the
                // following applyProfileLayout proceeds without waiting.
                appState.itemManager.cancelSettlingPeriod(reason: "spacingRelaunch:noOp")
            }
            await appState.itemManager.applyProfileLayout(
                MenuBarItemManager.ProfileLayoutSpec(
                    pinnedHidden: pinnedHidden,
                    pinnedAlwaysHidden: pinnedAlwaysHidden,
                    sectionOrder: sectionOrder,
                    itemSectionMap: itemSectionMap,
                    itemOrder: itemOrder
                )
            )

            // 3. Post-hooks. Profile runs first (mirror of the pre order),
            //    then global teardown. Cancellation skips both, since a
            //    newer apply is taking over.
            if Task.isCancelled {
                if self?.layoutGeneration == generation {
                    self?.layoutTask = nil
                }
                return
            }
            await HookRunner.runIfEnabled(profilePost, context: HookRunner.Context(
                phase: .post,
                scope: .profile,
                profileID: baseContext.profileID,
                profileName: baseContext.profileName,
                previousProfileID: baseContext.previousID,
                previousProfileName: baseContext.previousName
            ))
            // A newer apply may have cancelled this task while the
            // profile post-hook was awaiting (long-running script);
            // skip the global post-hook in that case so the cancelled
            // apply doesn't also fire the outer teardown.
            if Task.isCancelled {
                if self?.layoutGeneration == generation {
                    self?.layoutTask = nil
                }
                return
            }
            await HookRunner.runIfEnabled(globalPost, context: HookRunner.Context(
                phase: .post,
                scope: .global,
                profileID: baseContext.profileID,
                profileName: baseContext.profileName,
                previousProfileID: baseContext.previousID,
                previousProfileName: baseContext.previousName
            ))

            if self?.layoutGeneration == generation {
                self?.layoutTask = nil
            }
        }
    }

    /// Pushes the profile snapshot into the live app state. Split out so
    /// applyProfile's task body stays readable.
    private func applySnapshot(_ profile: Profile, to appState: AppState) {
        profile.generalSettings.apply(to: appState.settings.general)
        profile.advancedSettings.apply(to: appState.settings.advanced)

        // Apply hotkeys
        Defaults.set(profile.hotkeys, forKey: .hotkeys)
        for hotkey in appState.settings.hotkeys.hotkeys {
            guard let data = profile.hotkeys[hotkey.action.rawValue] else {
                hotkey.keyCombination = nil
                continue
            }
            do {
                let keyCombination = try decoder.decode(
                    KeyCombination?.self,
                    from: data
                )
                hotkey.keyCombination = keyCombination
            } catch {
                diagLog.error(
                    "Failed to decode hotkey for \(hotkey.action.rawValue): \(error)"
                )
            }
        }

        // configurations.didSet derives active-display spacing synchronously,
        // so install its global fallback before the per-display overrides.
        appState.settings.displaySettings.globalConfiguration = profile.globalDisplayConfiguration

        // Apply display configurations.
        appState.settings.displaySettings.configurations = profile.displayConfigurations

        // Apply the spacing-relaunch confirmation preferences
        appState.settings.displaySettings.confirmSpacingRelaunch = profile.confirmSpacingRelaunch
        appState.settings.displaySettings.unconfirmedSpacingProfileScope = profile.unconfirmedSpacingProfileScope

        // Apply appearance configuration
        appState.appearanceManager.configuration = profile.appearanceConfiguration

        // Apply custom names to UserDefaults.
        Defaults.set(
            profile.menuBarLayout.customNames,
            forKey: .menuBarItemCustomNames
        )

        // Apply per-item hotkeys to UserDefaults, then rebuild the live hotkey
        // objects so the restored bindings register immediately.
        Defaults.set(
            profile.menuBarLayout.itemHotkeys ?? [:],
            forKey: .menuBarItemHotkeys
        )
        appState.menuBarManager.rebuildItemHotkeys()

        // Apply the New Items badge placement before starting the layout
        // task, so late-arriving items land in the profile-defined spot.
        if let placement = profile.menuBarLayout.newItemsPlacement {
            appState.itemManager.applyNewItemsPlacement(placement)
        }
    }

    // MARK: - Profile Hotkeys

    /// Creates hotkeys for all profiles and observes their changes.
    /// Called during setup and whenever the profile list changes.
    func rebuildProfileHotkeys() {
        guard let appState else { return }

        // Disable existing profile hotkeys and clear state.
        for (_, hotkey) in profileHotkeys {
            hotkey.disable()
        }
        hotkeyProfileMap.removeAll()

        // Clean up orphaned hotkey entries for deleted profiles.
        let profileIDs = Set(profiles.map(\.id.uuidString))
        if var saved = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] {
            let before = saved.count
            saved = saved.filter { profileIDs.contains($0.key) }
            if saved.count != before {
                Defaults.set(saved, forKey: .profileHotkeys)
            }
        }

        // Load saved key combinations.
        let saved = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
        let dec = JSONDecoder()
        let enc = JSONEncoder()

        var newHotkeys: [UUID: Hotkey] = [:]
        for meta in profiles {
            let profileID = meta.id

            // Create a hotkey with .profileApply (no-op action) so the
            // default Listener doesn't trigger unwanted side effects.
            let hotkey = Hotkey(action: .profileApply)
            hotkey.performSetup(with: appState)

            // Load saved key combination.
            if let data = saved[meta.id.uuidString],
               let combo = try? dec.decode(KeyCombination?.self, from: data)
            {
                hotkey.keyCombination = combo
            }

            // Map this hotkey to its profile ID for the perform() lookup.
            hotkeyProfileMap[ObjectIdentifier(hotkey)] = profileID

            // Observe future changes from HotkeyRecorder. Assigned after the
            // initial keyCombination is set above, so — like the previous
            // dropFirst() Combine pipeline — the initial value is never
            // redundantly persisted.
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
                // Persist.
                var dict = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
                if let combo = hotkey.keyCombination, let data = try? enc.encode(combo) {
                    dict[profileID.uuidString] = data
                } else {
                    dict.removeValue(forKey: profileID.uuidString)
                }
                Defaults.set(dict, forKey: .profileHotkeys)
                // Update the hotkey→profile mapping.
                self.hotkeyProfileMap[ObjectIdentifier(hotkey)] = hotkey.keyCombination != nil ? profileID : nil
            }

            newHotkeys[meta.id] = hotkey
        }
        profileHotkeys = newHotkeys
    }

    // MARK: - Auto-Switch

    /// Called when the active menu bar display changes. Finds a profile
    /// associated with the new active display and applies it.
    /// Skipped when a Focus Filter profile is currently active.
    ///
    /// Internal rather than private because `startObservationTasks()` — which
    /// stays in the measured file so its wiring remains testable — installs
    /// the closure that calls it.
    func checkDisplayAndAutoSwitch() async {
        guard let currentUUID = Bridging.getActiveMenuBarDisplayUUID() else { return }
        guard currentUUID != lastActiveDisplayUUID else { return }
        lastActiveDisplayUUID = currentUUID

        // Don't override a Focus Filter profile with a display switch.
        guard !focusFilterActive else { return }

        await applyProfileForDisplay(uuid: currentUUID)
    }

    /// Applies the profile requested by a Focus Filter activation.
    func applyFocusFilterProfile() async {
        guard let idString = Defaults.string(forKey: .focusFilterRequestedProfileID),
              let profileID = UUID(uuidString: idString)
        else { return }

        guard profileID != activeProfileID else {
            focusFilterActive = true
            return
        }
        guard let appState else { return }

        diagLog.info("Focus Filter: applying profile \(idString)")
        do {
            let profile = try loadProfile(id: profileID)
            let previousID = activeProfileID
            activeProfileID = profileID
            focusFilterActive = true
            applyProfile(profile, to: appState, previousProfileID: previousID)
        } catch {
            diagLog.error("Focus Filter apply failed: \(error)")
        }
    }

    /// Called when the Focus Filter deactivates (Focus mode turned off).
    /// Reverts to the display-based profile.
    ///
    /// Internal for the same reason as ``checkDisplayAndAutoSwitch()``.
    func handleFocusFilterDeactivated() async {
        guard focusFilterActive else { return }
        focusFilterActive = false
        diagLog.info("Focus Filter deactivated; reverting to display profile")
        if let uuid = Bridging.getActiveMenuBarDisplayUUID() {
            await applyProfileForDisplay(uuid: uuid)
        }
    }

    /// Re-applies the currently active profile, driving its layout pass
    /// without changing which profile is active.
    ///
    /// Used by DisplaySettingsManager.applyActiveDisplaySpacing after it
    /// fires a relaunch wave whose menu bar items reattach at OS-default
    /// positions: the auto-switch path doesn't fire when the active display
    /// keeps the same associated profile, so without an explicit re-apply
    /// the layout would never run and the items would stay where macOS put
    /// them. The applyOffset inside layoutTask no-ops (the on-disk values
    /// were just written), and the subsequent applyProfileLayout awaits
    /// the in-flight expected-set settling before running.
    func reapplyActiveProfile() {
        guard let appState else { return }
        guard let activeID = activeProfileID else { return }
        do {
            let profile = try loadProfile(id: activeID)
            // No previous-vs-new transition here; pass the active id as
            // both previous and current so a hook can see the apply was a
            // refresh of the same profile rather than a switch.
            applyProfile(profile, to: appState, previousProfileID: activeID)
        } catch {
            diagLog.error("reapplyActiveProfile failed: \(error)")
        }
    }

    /// Applies the profile associated with the given display UUID, if any.
    private func applyProfileForDisplay(uuid: String) async {
        guard let meta = profiles.first(where: { $0.associatedDisplayUUID == uuid }) else {
            return
        }
        guard meta.id != activeProfileID else { return }
        guard let appState else { return }

        diagLog.info("Auto-switching to profile \(meta.name) for display \(uuid)")
        do {
            let profile = try loadProfile(id: meta.id)
            let previousID = activeProfileID
            activeProfileID = meta.id
            applyProfile(profile, to: appState, previousProfileID: previousID)
        } catch {
            diagLog.error("Auto-switch failed: \(error)")
        }
    }
}
