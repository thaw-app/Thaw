//
//  ProfileManager+Live.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// The live half of ProfileManager: everything that needs a running AppState.
/// Excluded from coverage in sonar-project.properties.
///
/// Decision logic belongs in ProfileManager.swift; keep methods here as thin
/// orchestration over it.
extension ProfileManager {
    /// Sets up the manager with the app state and configures auto-switch.
    /// If the current display has an associated profile, it is applied
    /// after the menu bar has settled.
    func performSetup(with appState: AppState) {
        self.appState = appState
        lastActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        rebuildProfileHotkeys()

        // Before anything can apply a profile. Once per build, since only a
        // new build can widen what pruning recognizes as unmatchable.
        repairPersistedLayoutsIfNeeded()

        // Note: profiles' didSet already calls rebuildProfileHotkeys() for
        // every assignment after this class's own init, so no explicit
        // subscription is needed here (see the doc comment on profiles).

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
            // The spacing apply runs unconditionally. It no-ops when on-disk
            // values match, but booting on a display whose profile has a
            // different offset needs the relaunch here.
            // A Space association wins over the display one at startup
            // for the same reason it does on a live switch.
            let startupSpaceKey = SpaceInfo.activeSpace().persistentKey
            self.lastActiveSpaceKey = startupSpaceKey
            if let startupSpaceKey, self.profile(forSpaceKey: startupSpaceKey) != nil {
                await self.applyProfileForSpace(key: startupSpaceKey)
                return
            }
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
    /// previousProfileID is the active ID before this apply, captured by
    /// callers and passed to hooks as THAW_PREVIOUS_PROFILE_ID.
    func applyProfile(
        _ profile: Profile,
        to appState: AppState,
        previousProfileID: UUID? = nil,
        enforceConcealedSectionOrder: Bool = false
    ) {
        diagLog.debug(
            "applyProfile entered: name=\(profile.name)"
        )

        // Cancel any in-flight layout task before starting a new one.
        // Prevents two profile applies from fighting over item positions.
        layoutTask?.cancel()
        layoutGeneration &+= 1
        let generation = layoutGeneration
        guard let batchLease = appState.itemManager.beginLayoutBatch(.explicitProfile) else {
            return
        }

        let pinnedHidden = Set(profile.menuBarLayout.pinnedHiddenBundleIDs)
        let pinnedAlwaysHidden = Set(profile.menuBarLayout.pinnedAlwaysHiddenBundleIDs)
        let sectionOrder = profile.menuBarLayout.savedSectionOrder
        let itemSectionMap = profile.menuBarLayout.resolvedItemSectionMap
        let itemOrder = profile.menuBarLayout.resolvedItemOrder

        // Read hook config before the task to keep it on the main actor.
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
            defer { appState.itemManager.finishLayoutBatch(batchLease) }

            // Pre-hooks: global first for common setup, then the profile's
            // own so it can override or extend.
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

            self?.applySnapshot(profile, to: appState)

            // Read the offset from the configuration just installed, not
            // spacingManager. configurations.didSet skips unchanged values,
            // so a matching profile leaves the offset at its launch value of
            // 0 and applyOffset() would relaunch every app to the default.
            let desiredOffset = appState.settings.displaySettings
                .activeDisplaySpacingOffset

            // A profile switch asks before relaunching, like any apply not confirmed
            // in the Displays pane. Declining keeps the current spacing.
            // An unknown display resolves to the global template, so the
            // spacing waits for a known display; the rest still applies.
            let isDisplayKnown = Bridging.getActiveMenuBarDisplayUUID() != nil
            let relaunchApproved = isDisplayKnown && appState.settings.displaySettings
                .confirmSpacingRelaunchIfNeeded(forOffset: desiredOffset)
            if relaunchApproved {
                appState.spacingManager.offset = desiredOffset
            } else if isDisplayKnown {
                appState.settings.displaySettings
                    .keepEffectiveSpacing(offset: appState.spacingManager.offset)
                self?.diagLog.info("User declined the spacing relaunch confirmation for profile \(profile.name); keeping current spacing")
            } else {
                self?.diagLog.info("Active menu bar display unknown; deferring spacing for profile \(profile.name)")
            }

            // Apply spacing before the layout pass: applyOffset() relaunches
            // every menu bar app, wiping any positioning done before it.
            //
            // After a relaunch, restart settling so applyProfileLayout waits
            // for items to re-attach instead of positioning absent ones.

            // Enter settling before the wave so late-arriver detection and
            // profile re-sorts stand down while apps respawn. Otherwise, on a
            // notch display, each intermediate cache cycle starts a sort.
            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:preflight")

            let didRelaunch: Bool
            let recovered: Set<String>
            if !relaunchApproved {
                didRelaunch = false
                recovered = []
            } else {
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
                ),
                enforceConcealedSectionOrder: enforceConcealedSectionOrder,
                shouldBegin: {
                    appState.itemManager.layoutBatchIsCurrent(batchLease)
                }
            )

            // Post-hooks: profile first, then global teardown. Cancellation
            // skips both, since a newer apply is taking over.
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

    /// Pushes the profile snapshot into the live app state.
    private func applySnapshot(_ profile: Profile, to appState: AppState) {
        profile.generalSettings.apply(to: appState.settings.general)
        profile.advancedSettings.apply(to: appState.settings.advanced)

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

        // Install the global fallback first, so anything resolving the active
        // display in between reads the profile's template.
        appState.settings.displaySettings.globalConfiguration = profile.globalDisplayConfiguration

        // applyProfile drives spacing after the snapshot, so hold back the
        // configurations reaction.
        appState.settings.displaySettings.withSpacingReactionSuspended {
            appState.settings.displaySettings.configurations = profile.displayConfigurations
        }

        appState.settings.displaySettings.confirmSpacingRelaunch = profile.confirmSpacingRelaunch
        appState.settings.displaySettings.unconfirmedSpacingProfileScope = profile.unconfirmedSpacingProfileScope

        appState.appearanceManager.configuration = profile.appearanceConfiguration

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

            if let data = saved[meta.id.uuidString],
               let combo = try? dec.decode(KeyCombination?.self, from: data)
            {
                hotkey.keyCombination = combo
            }

            // Map this hotkey to its profile ID for the perform() lookup.
            hotkeyProfileMap[ObjectIdentifier(hotkey)] = profileID

            // Assigned after the initial keyCombination is set, so only later
            // changes are persisted.
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
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
    /// Internal because startObservationTasks(), in the measured file,
    /// installs the closure that calls it.
    func checkDisplayAndAutoSwitch() async {
        guard let currentUUID = Bridging.getActiveMenuBarDisplayUUID() else { return }
        guard currentUUID != lastActiveDisplayUUID else { return }
        lastActiveDisplayUUID = currentUUID

        // Don't override a Focus Filter profile with a display switch.
        guard !focusFilterActive else { return }

        // A Space association is a deliberate choice about the Space the
        // user is looking at; a display change often is not (docking,
        // waking, a resolution change). Let the Space keep the bar it
        // asked for rather than having the display overwrite it.
        if let spaceKey = SpaceInfo.activeSpace().persistentKey,
           profile(forSpaceKey: spaceKey) != nil
        {
            diagLog.debug("Display auto-switch yielding to Space association \(spaceKey)")
            return
        }

        await applyProfileForDisplay(uuid: currentUUID)
    }

    /// Applies the profile associated with the active Space, if any.
    ///
    /// Runs on every Space switch, so it leans on the same
    /// already-active guard the display path uses: switching between two
    /// Spaces that share a profile costs nothing.
    func checkSpaceAndAutoSwitch() async {
        guard let key = SpaceInfo.activeSpace().persistentKey else {
            // The window server can answer with a Space it has not
            // published in its managed-display list yet, most often
            // mid-animation. Leaving the bar alone is the safe response;
            // the next switch will resolve.
            diagLog.debug("Space auto-switch: active Space has no persistent key yet")
            return
        }
        guard key != lastActiveSpaceKey else { return }
        lastActiveSpaceKey = key

        // Focus outranks a Space switch, same as it outranks a display one.
        guard !focusFilterActive else { return }

        await applyProfileForSpace(key: key)
    }

    /// Applies the profile associated with the given Space key, if any.
    private func applyProfileForSpace(key: String) async {
        guard let meta = profile(forSpaceKey: key) else { return }
        guard meta.id != activeProfileID else { return }
        guard let appState else { return }

        diagLog.info("Auto-switching to profile \(meta.name) for Space \(key)")
        do {
            let profile = try loadProfile(id: meta.id)
            let previousID = activeProfileID
            activeProfileID = meta.id
            applyProfile(profile, to: appState, previousProfileID: previousID)
        } catch {
            diagLog.error("Space auto-switch failed: \(error)")
        }
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
    /// Internal for the same reason as checkDisplayAndAutoSwitch().
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
    /// Used after a relaunch wave reattaches items at OS-default positions.
    /// Auto-switch doesn't fire when the display keeps its profile, so
    /// without this the layout would never run.
    func reapplyActiveProfile(enforceConcealedSectionOrder: Bool = false) {
        guard let appState else { return }
        guard let activeID = activeProfileID else { return }
        do {
            let profile = try loadProfile(id: activeID)
            // No previous-vs-new transition here; pass the active id as
            // both previous and current so a hook can see the apply was a
            // refresh of the same profile rather than a switch.
            applyProfile(
                profile,
                to: appState,
                previousProfileID: activeID,
                enforceConcealedSectionOrder: enforceConcealedSectionOrder
            )
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
