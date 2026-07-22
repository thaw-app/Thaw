//
//  ProfileManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Foundation

@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [ProfileMetadata] = []

    /// The ID of the currently active profile, or `nil`.
    @Published var activeProfileID: UUID?

    private let diagLog = DiagLog(category: "ProfileManager")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let profilesDirectory: URL
    private let manifestURL: URL
    private(set) weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    /// Tracks the last seen active display UUID for auto-switch debouncing.
    private var lastActiveDisplayUUID: String?
    /// Whether a Focus Filter profile is currently applied.
    private var focusFilterActive = false
    /// The in-flight layout apply task. Exposed for callers that need to
    /// wait for the layout to finish (e.g. the Apply button).
    private(set) var layoutTask: Task<Void, Never>?

    /// Generation counter to prevent older layout tasks from clearing newer ones.
    private var layoutGeneration: UInt = 0

    /// Hotkeys for switching to each profile, keyed by profile ID.
    @Published private(set) var profileHotkeys: [UUID: Hotkey] = [:]
    /// Maps Hotkey identity to profile ID for the perform() lookup.
    var hotkeyProfileMap: [ObjectIdentifier: UUID] = [:]
    /// Observers for profile hotkey changes.
    private var profileHotkeyCancellables = Set<AnyCancellable>()

    /// - Parameter profilesDirectory: Where profile JSON and the manifest
    ///   live. Defaults to Application Support in production; tests pass a
    ///   temporary directory to exercise the real load/save paths in isolation
    ///   without touching the user's profiles.
    init(profilesDirectory: URL? = nil) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec

        if let profilesDirectory {
            self.profilesDirectory = profilesDirectory
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                fatalError("Application Support directory not found")
            }
            self.profilesDirectory = appSupport
                .appendingPathComponent("Thaw/Profiles", isDirectory: true)
        }
        manifestURL = self.profilesDirectory
            .appendingPathComponent("profiles.json")

        ensureDirectoryExists()
        loadManifest()
    }

    /// Sets up the manager with the app state and configures auto-switch.
    /// If the current display has an associated profile, it is applied
    /// after the menu bar has settled.
    func performSetup(with appState: AppState) {
        self.appState = appState
        lastActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        rebuildProfileHotkeys()

        // Rebuild profile hotkeys when the profile list changes.
        $profiles
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildProfileHotkeys()
            }
            .store(in: &cancellables)

        // Listen for display changes to trigger auto-switch.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.checkDisplayAndAutoSwitch()
                }
            }
            .store(in: &cancellables)

        // Listen for Focus Filter activation from the system.
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.stonerl.Thaw.focusFilterActivated"))
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.applyFocusFilterProfile()
                }
            }
            .store(in: &cancellables)

        // Listen for Focus Filter deactivation (Focus mode turned off).
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.stonerl.Thaw.focusFilterDeactivated"))
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleFocusFilterDeactivated()
                }
            }
            .store(in: &cancellables)

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

    // MARK: - Private Helpers

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: profilesDirectory.path) {
            do {
                try fm.createDirectory(
                    at: profilesDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                diagLog.error("Failed to create profiles directory: \(error)")
            }
        }
    }

    private func loadManifest() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestURL.path) else {
            profiles = []
            return
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            profiles = try decoder.decode([ProfileMetadata].self, from: data)
        } catch {
            diagLog.error("Failed to load profiles manifest: \(error)")
            profiles = []
        }
    }

    private func saveManifest() {
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            diagLog.error("Failed to save profiles manifest: \(error)")
        }
    }

    private func profileURL(for id: UUID) -> URL {
        profilesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Public API

    /// Captures the current app state and saves it as a named profile.
    func saveProfile(name: String, from appState: AppState) throws {
        let profile = Profile(
            name: name,
            content: ProfileContent(
                generalSettings: GeneralSettingsSnapshot.capture(from: appState.settings.general),
                advancedSettings: AdvancedSettingsSnapshot.capture(from: appState.settings.advanced),
                hotkeys: Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:],
                displayConfigurations: appState.settings.displaySettings.configurations,
                globalDisplayConfiguration: appState.settings.displaySettings.globalConfiguration,
                confirmSpacingRelaunch: appState.settings.displaySettings.confirmSpacingRelaunch,
                unconfirmedSpacingProfileScope: appState.settings.displaySettings.unconfirmedSpacingProfileScope,
                appearanceConfiguration: appState.appearanceManager.configuration,
                menuBarLayout: captureCurrentLayout(from: appState.itemManager)
            )
        )

        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: profile.id), options: .atomic)

        let metadata = ProfileMetadata(
            id: profile.id,
            name: profile.name,
            createdAt: profile.createdAt,
            modifiedAt: profile.modifiedAt
        )
        profiles.append(metadata)
        saveManifest()
    }

    /// Loads a full profile from disk by its identifier.
    func loadProfile(id: UUID) throws -> Profile {
        let url = profileURL(for: id)
        let data = try Data(contentsOf: url)
        return try decoder.decode(Profile.self, from: data)
    }

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
        let itemSectionMap = profile.menuBarLayout.itemSectionMap ?? [:]
        let itemOrder = profile.menuBarLayout.itemOrder ?? [:]

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
            if Task.isCancelled { return }
            await HookRunner.runIfEnabled(profilePre, context: HookRunner.Context(
                phase: .pre,
                scope: .profile,
                profileID: baseContext.profileID,
                profileName: baseContext.profileName,
                previousProfileID: baseContext.previousID,
                previousProfileName: baseContext.previousName
            ))
            if Task.isCancelled { return }

            // 2. Snapshot apply: push profile settings into the running
            //    app state.
            self?.applySnapshot(profile, to: appState)

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
                pinnedHidden: pinnedHidden,
                pinnedAlwaysHidden: pinnedAlwaysHidden,
                sectionOrder: sectionOrder,
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder
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

        // Apply display configurations
        appState.settings.displaySettings.configurations = profile.displayConfigurations

        // Apply global display configuration template
        appState.settings.displaySettings.globalConfiguration = profile.globalDisplayConfiguration

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

    /// Deletes a profile by its identifier.
    func deleteProfile(id: UUID) throws {
        let url = profileURL(for: id)
        try FileManager.default.removeItem(at: url)
        profiles.removeAll { $0.id == id }
        saveManifest()
    }

    /// Renames a profile.
    func renameProfile(id: UUID, to newName: String) throws {
        var profile = try loadProfile(id: id)
        profile = Profile(
            id: profile.id,
            name: newName,
            createdAt: profile.createdAt,
            modifiedAt: Date(),
            content: profile.content
        )

        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: id), options: .atomic)

        if let index = profiles.firstIndex(where: { $0.id == id }) {
            var updated = profiles[index]
            updated.name = newName
            updated.modifiedAt = profile.modifiedAt
            profiles[index] = updated
        }
        saveManifest()
    }

    /// Duplicates an existing profile with a new name.
    func duplicateProfile(id: UUID, newName: String) throws {
        let original = try loadProfile(id: id)
        let duplicate = Profile(
            name: newName,
            content: original.content
        )

        let data = try encoder.encode(duplicate)
        try data.write(to: profileURL(for: duplicate.id), options: .atomic)

        let metadata = ProfileMetadata(
            id: duplicate.id,
            name: duplicate.name,
            createdAt: duplicate.createdAt,
            modifiedAt: duplicate.modifiedAt
        )
        profiles.append(metadata)
        saveManifest()
    }

    /// Exports a profile to a file, including display associations.
    func exportProfile(id: UUID, to url: URL) throws {
        let profile = try loadProfile(id: id)
        let meta = profiles.first { $0.id == id }
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: meta?.associatedDisplayUUID,
            associatedDisplayName: meta?.associatedDisplayName
        )
        let bundle = ProfileExportBundle(entries: [entry])
        let data = try encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
    }

    /// Overwrites an existing profile with the current app state,
    /// keeping its id, name, display association, and creation date.
    func updateProfileWithCurrentState(id: UUID, appState: AppState) throws {
        guard let old = profiles.first(where: { $0.id == id }) else { return }

        // Save as new profile first (captures all current state).
        let tempName = "__temp_update__"
        try saveProfile(name: tempName, from: appState)
        guard let tempMeta = profiles.last, tempMeta.name == tempName else { return }

        // Load the temp profile and re-save with original identity.
        var updated = try loadProfile(id: tempMeta.id)
        updated = Profile(
            id: id,
            name: old.name,
            createdAt: old.createdAt,
            modifiedAt: Date(),
            content: updated.content
        )

        let data = try encoder.encode(updated)
        try data.write(to: profileURL(for: id), options: .atomic)

        // Remove temp profile.
        try? FileManager.default.removeItem(at: profileURL(for: tempMeta.id))
        profiles.removeAll { $0.id == tempMeta.id }

        // Update metadata.
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].modifiedAt = updated.modifiedAt
        }
        saveManifest()

        // The live arrangement is unchanged by this save, so re-capturing it
        // yields the same layout that was just persisted. Re-arm the cache from
        // it when this is the active profile so a later late-arrival re-sort
        // honours the update instead of reverting to the pre-update spec.
        rearmActiveLayoutIfNeeded(
            updatedID: id,
            scope: .all,
            layout: captureCurrentLayout(from: appState.itemManager),
            itemManager: appState.itemManager
        )
    }

    // MARK: - Capture Helpers

    /// Captures the current menu bar layout. Depends only on the item manager
    /// (and UserDefaults), not the full app state, so the capture and re-arm
    /// paths can be exercised in tests without standing up an AppState.
    private func captureCurrentLayout(from itemManager: MenuBarItemManager) -> MenuBarLayoutSnapshot {
        let savedSectionOrder = UserDefaults.standard.dictionary(
            forKey: "MenuBarItemManager.savedSectionOrder"
        ) as? [String: [String]] ?? [:]
        let pinnedHiddenBundleIDs = UserDefaults.standard.array(
            forKey: "MenuBarItemManager.pinnedHiddenBundleIDs"
        ) as? [String] ?? []
        let pinnedAlwaysHiddenBundleIDs = UserDefaults.standard.array(
            forKey: "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs"
        ) as? [String] ?? []
        let customNames = Defaults.dictionary(
            forKey: .menuBarItemCustomNames
        ) as? [String: String] ?? [:]
        let itemHotkeys = Defaults.dictionary(
            forKey: .menuBarItemHotkeys
        ) as? [String: Data] ?? [:]

        // itemOrder must agree with savedSectionOrder; they are two
        // representations of the same "where does each item belong?"
        // question, and the apply pipeline assumes they are consistent.
        // Deriving itemOrder by iterating itemCache directly produced
        // a drift bug: closed apps preserved in savedSectionOrder
        // (via planSectionOrder's closed-app merge) did not appear in
        // itemOrder, and transient Control Center widgets did the
        // opposite. On profile re-apply that drift caused
        // closed-but-saved apps like jetbrains to be treated as
        // unmanaged and routed through planUnmanagedPlacement instead
        // of landing at their saved section. Delegating to
        // MenuBarItemManager.computeSectionOrder runs the same filter
        // and closed-app preservation, so the profile's itemOrder is
        // a curated snapshot consistent with savedSectionOrder.
        let itemOrder = itemManager.computeSectionOrder(
            from: itemManager.itemCache
        )
        var itemSectionMap = [String: String]()
        for (sectionKey, uids) in itemOrder {
            for uid in uids {
                itemSectionMap[uid] = sectionKey
            }
        }

        return MenuBarLayoutSnapshot(
            savedSectionOrder: savedSectionOrder,
            pinnedHiddenBundleIDs: pinnedHiddenBundleIDs,
            pinnedAlwaysHiddenBundleIDs: pinnedAlwaysHiddenBundleIDs,
            customNames: customNames,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder,
            newItemsPlacement: itemManager.newItemsPlacement,
            itemHotkeys: itemHotkeys
        )
    }

    /// Applies the current configuration (settings, hotkeys, appearance) to a profile.
    private func applyCurrentConfiguration(to profile: inout Profile, from appState: AppState) {
        profile.generalSettings = GeneralSettingsSnapshot.capture(
            from: appState.settings.general
        )
        profile.advancedSettings = AdvancedSettingsSnapshot.capture(
            from: appState.settings.advanced
        )
        profile.hotkeys = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:]
        profile.displayConfigurations = appState.settings.displaySettings.configurations
        profile.globalDisplayConfiguration = appState.settings.displaySettings.globalConfiguration
        profile.confirmSpacingRelaunch = appState.settings.displaySettings.confirmSpacingRelaunch
        profile.unconfirmedSpacingProfileScope = appState.settings.displaySettings.unconfirmedSpacingProfileScope
        profile.appearanceConfiguration = appState.appearanceManager.configuration
    }

    /// Saves a profile to disk and updates the manifest.
    private func saveProfileAndUpdateManifest(_ profile: Profile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: profile.id), options: .atomic)

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].modifiedAt = profile.modifiedAt
        }
        saveManifest()
    }

    // MARK: - Scoped Updates

    /// What parts of a profile to update.
    enum ProfileUpdateScope {
        case all
        case layoutOnly
        case configurationOnly
    }

    /// Decides whether updating profile updatedID under scope should
    /// refresh MenuBarItemManager's in-memory active-profile layout cache.
    /// True only when the updated profile is the currently-active one and the
    /// update captured a fresh layout (.all or .layoutOnly): a
    /// configuration-only update changes no layout, and updating an inactive
    /// profile must never touch live state. Without re-arming, an update writes
    /// the new layout to disk but leaves the cache pointing at the pre-update
    /// spec, so the next late-arrival re-sort reverts the bar until the profile
    /// is manually re-applied.
    static nonisolated func shouldRearmActiveLayout(
        updatedID: UUID,
        activeID: UUID?,
        scope: ProfileUpdateScope
    ) -> Bool {
        guard updatedID == activeID else { return false }
        switch scope {
        case .all, .layoutOnly:
            return true
        case .configurationOnly:
            return false
        }
    }

    /// Updates a profile with only the specified scope of current state.
    func updateProfile(id: UUID, scope: ProfileUpdateScope, appState: AppState) throws {
        switch scope {
        case .all:
            try updateProfileWithCurrentState(id: id, appState: appState)
        case .layoutOnly:
            try updateProfileLayout(id: id, itemManager: appState.itemManager)
        case .configurationOnly:
            try updateProfileConfiguration(id: id, appState: appState)
        }
    }

    /// Updates only the menu bar layout of an existing profile. Takes the item
    /// manager rather than the full app state: layout capture and re-arm need
    /// nothing else, and the narrower dependency lets this be exercised in
    /// tests without an AppState. Internal so the integration test can drive it
    /// directly through the injected profiles directory.
    func updateProfileLayout(id: UUID, itemManager: MenuBarItemManager) throws {
        var profile = try loadProfile(id: id)
        let layout = captureCurrentLayout(from: itemManager)
        profile.menuBarLayout = layout
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
        rearmActiveLayoutIfNeeded(updatedID: id, scope: .layoutOnly, layout: layout, itemManager: itemManager)
    }

    /// Refreshes MenuBarItemManager's cached active-profile layout after an
    /// update that captured a fresh layout, so a later late-arrival re-sort
    /// honours the new layout without a manual re-apply. No-op unless the
    /// updated profile is the active one (see shouldRearmActiveLayout). The
    /// captured layout already matches the live arrangement, so this only syncs
    /// the in-memory spec and moves nothing.
    private func rearmActiveLayoutIfNeeded(
        updatedID: UUID,
        scope: ProfileUpdateScope,
        layout: MenuBarLayoutSnapshot,
        itemManager: MenuBarItemManager
    ) {
        guard Self.shouldRearmActiveLayout(
            updatedID: updatedID,
            activeID: activeProfileID,
            scope: scope
        ) else { return }
        itemManager.rearmActiveProfileLayout(
            pinnedHidden: Set(layout.pinnedHiddenBundleIDs),
            pinnedAlwaysHidden: Set(layout.pinnedAlwaysHiddenBundleIDs),
            sectionOrder: layout.savedSectionOrder,
            itemSectionMap: layout.itemSectionMap ?? [:],
            itemOrder: layout.itemOrder ?? [:]
        )
    }

    /// Updates only the configuration (settings, hotkeys, appearance) of an existing profile.
    private func updateProfileConfiguration(id: UUID, appState: AppState) throws {
        var profile = try loadProfile(id: id)
        applyCurrentConfiguration(to: &profile, from: appState)
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
    }

    /// Writes the given itemSpacingOffset into every profile's stored
    /// displayConfigurations entry for the specified display UUID. Creates
    /// a default entry when a profile has no prior configuration for that
    /// display. Used by the spacing-apply confirmation in DisplaySettingsPane
    /// so a freshly applied spacing change is not reverted by the next
    /// profile reapply.
    func updateAllProfilesItemSpacingOffset(displayUUID: String, offset: Double) throws {
        let now = Date()
        var pending: [Profile] = []
        pending.reserveCapacity(profiles.count)
        for meta in profiles {
            var profile = try loadProfile(id: meta.id)
            let base = profile.displayConfigurations[displayUUID] ?? .defaultConfiguration
            profile.displayConfigurations[displayUUID] = base.withItemSpacingOffset(offset)
            profile.modifiedAt = now
            pending.append(profile)
        }
        for profile in pending {
            let data = try encoder.encode(profile)
            try data.write(to: profileURL(for: profile.id), options: .atomic)
        }
        for profile in pending {
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index].modifiedAt = profile.modifiedAt
            }
        }
        saveManifest()
    }

    /// Writes the given configuration into every profile's
    /// globalDisplayConfiguration field. When propagateToDisplays is true,
    /// every per-display entry in each profile is also overwritten so a
    /// later profile reapply does not revert the broadcast. Mirrors the
    /// load-all-first, single-manifest-write shape of
    /// updateAllProfilesItemSpacingOffset so partial writes do not leave
    /// some profiles updated and others not.
    func updateAllProfilesGlobalConfiguration(
        _ config: DisplayIceBarConfiguration,
        propagateToDisplays: Bool
    ) throws {
        let now = Date()
        var pending: [Profile] = []
        pending.reserveCapacity(profiles.count)
        for meta in profiles {
            var profile = try loadProfile(id: meta.id)
            profile.globalDisplayConfiguration = config
            if propagateToDisplays {
                for uuid in profile.displayConfigurations.keys {
                    profile.displayConfigurations[uuid] = config
                }
            }
            profile.modifiedAt = now
            pending.append(profile)
        }
        for profile in pending {
            let data = try encoder.encode(profile)
            try data.write(to: profileURL(for: profile.id), options: .atomic)
        }
        for profile in pending {
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index].modifiedAt = profile.modifiedAt
            }
        }
        saveManifest()
    }

    // MARK: - Profile Hooks

    /// Returns the automation config (pre/post hooks) attached to the
    /// given profile. Returns an empty container when the profile has
    /// no hooks or cannot be loaded.
    func hooks(forProfileID id: UUID) -> ProfileAutomation {
        guard let profile = try? loadProfile(id: id) else {
            return ProfileAutomation()
        }
        return profile.automation ?? ProfileAutomation()
    }

    /// Sets the hook for the given phase on the given profile. Passing
    /// nil clears the hook. The profile JSON is rewritten in place; the
    /// manifest's modifiedAt is bumped so the UI reflects the change.
    func setHook(_ hook: HookScript?, phase: HookPhase, forProfileID id: UUID) throws {
        var profile = try loadProfile(id: id)
        var automation = profile.automation ?? ProfileAutomation()
        switch phase {
        case .pre: automation.preHook = hook
        case .post: automation.postHook = hook
        }
        profile.automation = automation.isEmpty ? nil : automation
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
    }

    /// Exports all profiles as a single JSON file including metadata.
    func exportAllProfiles() -> String? {
        var entries = [ProfileExportEntry]()
        for meta in profiles {
            guard let profile = try? loadProfile(id: meta.id) else { continue }
            entries.append(ProfileExportEntry(
                profile: profile,
                associatedDisplayUUID: meta.associatedDisplayUUID,
                associatedDisplayName: meta.associatedDisplayName
            ))
        }
        let bundle = ProfileExportBundle(entries: entries)
        guard let data = try? encoder.encode(bundle) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Display Association

    /// Sets the associated display UUID for a profile, clearing it from any
    /// other profile that previously had it (enforces uniqueness).
    /// Also caches the display name so it can be shown when disconnected.
    func setAssociatedDisplay(uuid: String?, displayName: String? = nil, forProfileID profileID: UUID) {
        if let uuid {
            for index in profiles.indices where profiles[index].associatedDisplayUUID == uuid {
                profiles[index].associatedDisplayUUID = nil
                profiles[index].associatedDisplayName = nil
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].associatedDisplayUUID = uuid
            profiles[index].associatedDisplayName = uuid != nil ? displayName : nil
        }
        saveManifest()
    }

    /// Clears the display association from whichever profile currently holds it.
    func setAssociatedDisplay(uuid _: String?, forDisplayUUID displayUUID: String) {
        for index in profiles.indices where profiles[index].associatedDisplayUUID == displayUUID {
            profiles[index].associatedDisplayUUID = nil
            profiles[index].associatedDisplayName = nil
        }
        saveManifest()
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
        profileHotkeyCancellables.removeAll()

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

            // Observe future changes from HotkeyRecorder.
            hotkey.$keyCombination
                .dropFirst() // Skip the initial value we just set.
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newCombo in
                    guard let self else { return }
                    // Persist.
                    var dict = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
                    if let combo = newCombo, let data = try? enc.encode(combo) {
                        dict[profileID.uuidString] = data
                    } else {
                        dict.removeValue(forKey: profileID.uuidString)
                    }
                    Defaults.set(dict, forKey: .profileHotkeys)
                    // Update the hotkey→profile mapping.
                    self.hotkeyProfileMap[ObjectIdentifier(hotkey)] = newCombo != nil ? profileID : nil
                }
                .store(in: &profileHotkeyCancellables)

            newHotkeys[meta.id] = hotkey
        }
        profileHotkeys = newHotkeys
    }

    // MARK: - Auto-Switch

    /// Called when the active menu bar display changes. Finds a profile
    /// associated with the new active display and applies it.
    /// Skipped when a Focus Filter profile is currently active.
    private func checkDisplayAndAutoSwitch() async {
        guard let currentUUID = Bridging.getActiveMenuBarDisplayUUID() else { return }
        guard currentUUID != lastActiveDisplayUUID else { return }
        lastActiveDisplayUUID = currentUUID

        // Don't override a Focus Filter profile with a display switch.
        guard !focusFilterActive else { return }

        await applyProfileForDisplay(uuid: currentUUID)
    }

    /// Applies the profile requested by a Focus Filter activation.
    func applyFocusFilterProfile() async {
        guard let idString = UserDefaults.standard.string(
            forKey: "FocusFilterRequestedProfileID"
        ),
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
    private func handleFocusFilterDeactivated() async {
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

    /// Imports profiles from a file.
    func importProfile(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let bundle = try decoder.decode(ProfileExportBundle.self, from: data)

        for entry in bundle.entries {
            let imported = Profile(
                name: entry.profile.name,
                content: entry.profile.content
            )

            let importedData = try encoder.encode(imported)
            try importedData.write(
                to: profileURL(for: imported.id),
                options: .atomic
            )

            let metadata = ProfileMetadata(
                id: imported.id,
                name: imported.name,
                createdAt: imported.createdAt,
                modifiedAt: imported.modifiedAt
            )
            profiles.append(metadata)

            // Reconcile display ownership through the setter so any existing
            // profile that owns this display has its association cleared first.
            if let displayUUID = entry.associatedDisplayUUID {
                setAssociatedDisplay(
                    uuid: displayUUID,
                    displayName: entry.associatedDisplayName,
                    forProfileID: imported.id
                )
            }
        }
        saveManifest()
    }
}
