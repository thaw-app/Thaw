//
//  ProfileManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine
import Foundation
import MenuBarModel

@MainActor
@Observable
final class ProfileManager {
    /// loadManifest() fires didSet during construction because only direct init assignments are exempt.
    /// rebuildProfileHotkeys() safely no-ops until appState is wired.
    private(set) var profiles: [ProfileMetadata] = [] {
        didSet {
            rebuildProfileHotkeys()
        }
    }

    /// The ID of the currently active profile, or nil.
    var activeProfileID: UUID?

    /// The last manifest write that failed in a non-throwing path, or nil.
    private(set) var lastManifestError: String?

    /// Returns and clears the pending manifest failure, so the pane that asked
    /// for the change reports it once.
    func takeManifestError() -> String? {
        defer { lastManifestError = nil }
        return lastManifestError
    }

    private let diagLog = DiagLog(category: "ProfileManager")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let profilesDirectory: URL
    private let manifestURL: URL
    private(set) weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    /// Tracks the last seen active display UUID for auto-switch debouncing.
    private var lastActiveDisplayUUID: String?
    /// Tracks the last seen active Space key for auto-switch debouncing.
    private var lastActiveSpaceKey: String?
    /// Whether a Focus Filter profile is currently applied.
    private var focusFilterActive = false
    /// The in-flight layout apply task. Exposed for callers that need to
    /// wait for the layout to finish (e.g. the Apply button).
    private(set) var layoutTask: Task<Void, Never>?

    /// Callers awaiting layoutTask use this to report an unavailable layout engine, even when profile settings applied.
    /// Cleared at the start of each apply.
    private(set) var layoutDidNotRun = false

    /// Generation counter to prevent older layout tasks from clearing newer ones.
    private var layoutGeneration: UInt = 0

    /// Clear the verdict and issue a reporting generation; separate from app relaunches so tests need no AppState.
    func beginLayoutApply() -> UInt {
        layoutDidNotRun = false
        layoutGeneration &+= 1
        return layoutGeneration
    }

    /// Ignore superseded failures so late tasks cannot overwrite a newer apply's clean verdict.
    func recordLayoutDidNotRun(generation: UInt) {
        guard layoutGeneration == generation else { return }
        layoutDidNotRun = true
    }

    /// Hotkeys for switching to each profile, keyed by profile ID.
    private(set) var profileHotkeys: [UUID: Hotkey] = [:]
    /// Maps Hotkey identity to profile ID for the perform() lookup.
    var hotkeyProfileMap: [ObjectIdentifier: UUID] = [:]
    /// Observers for profile hotkey changes.
    private var profileHotkeyCancellables = Set<AnyCancellable>()

    /// - Parameter profilesDirectory: Profile and manifest directory; defaults to Application Support. Tests use temporary directories to protect user profiles.
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
            // The search API is documented to return a URL but nothing
            // enforces it; derive the same directory from the home URL.
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
                ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.profilesDirectory = appSupport
                .appendingPathComponent("Thaw/Profiles", isDirectory: true)
        }
        manifestURL = self.profilesDirectory
            .appendingPathComponent("profiles.json")

        ensureDirectoryExists()
        loadManifest()
    }

    /// Apply the current display's associated profile only after the menu bar settles.
    func performSetup(with appState: AppState) {
        self.appState = appState
        lastActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        rebuildProfileHotkeys()

        let (screenParameterEvents, screenParameterContinuation) = AsyncStream<Void>.makeStream()
        let displaySwitchTask = Task { @MainActor [weak self] in
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in screenParameterContinuation.yield(()) }
            defer { NotificationCenter.default.removeObserver(observer) }
            for await _ in screenParameterEvents.debounce(for: .seconds(1.5)) {
                guard let self else { return }
                await self.checkDisplayAndAutoSwitch()
            }
        }
        cancellables.insert(AnyCancellable { displaySwitchTask.cancel() })

        // Debounce beyond the Space animation so rapid swipes apply only the final profile.
        let (spaceEvents, spaceContinuation) = AsyncStream<Void>.makeStream()
        let spaceSwitchTask = Task { @MainActor [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            let observer = center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in spaceContinuation.yield(()) }
            defer { center.removeObserver(observer) }
            for await _ in spaceEvents.debounce(for: .seconds(0.75)) {
                guard let self else { return }
                await self.checkSpaceAndAutoSwitch()
            }
        }
        cancellables.insert(AnyCancellable { spaceSwitchTask.cancel() })

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
                    _ = try await current.perform()
                    await self.applyFocusFilterProfile()
                    return
                }
            } catch {
                diagLog.debug("No active Focus Filter on startup: \(error)")
            }
            // Without Focus, prefer Space over display; always apply spacing to correct offsets left by another display's session.
            // Matching on-disk offsets no-op without relaunching.
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

    /// Throw manifest failures so profile edits cannot appear saved in the pane but disappear on relaunch.
    private func saveManifest() throws {
        let data = try encoder.encode(profiles)
        try data.write(to: manifestURL, options: .atomic)
    }

    /// Binding-driven association setters cannot throw; expose save failures through lastManifestError for the pane.
    private func persistManifest() {
        do {
            try saveManifest()
        } catch {
            diagLog.error("Failed to save profiles manifest: \(error)")
            lastManifestError = error.localizedDescription
        }
    }

    private func profileURL(for id: UUID) -> URL {
        profilesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Public API

    /// Captures the current app state and saves it as a named profile.
    ///
    /// - Returns: The identifier of the newly created profile.
    @discardableResult
    func saveProfile(name: String, from appState: AppState) throws -> UUID {
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
                spacingApplyMode: appState.settings.displaySettings.spacingApplyMode,
                appearanceConfiguration: appState.appearanceManager.configuration,
                menuBarLayout: captureCurrentLayout(
                    from: appState.itemManager,
                    groups: appState.itemGroupManager.snapshot()
                )
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
        try saveManifest()

        return profile.id
    }

    func loadProfile(id: UUID) throws -> Profile {
        let url = profileURL(for: id)
        let data = try Data(contentsOf: url)
        return try decoder.decode(Profile.self, from: data)
    }

    /// Apply spacing after settings; applyOffset avoids relaunches for matching on-disk offsets.
    /// Capture previousProfileID before changing activeProfileID so hooks receive THAW_PREVIOUS_PROFILE_ID.
    func applyProfile(
        _ profile: Profile,
        to appState: AppState,
        previousProfileID: UUID? = nil
    ) {
        diagLog.debug(
            "applyProfile entered: name=\(profile.name)"
        )

        // The profile names both groups outright, so whichever way round a
        // swap left them stops meaning anything here.
        appState.menuBarManager.clearSwapState()

        // Cancel any in-flight layout task before starting a new one.
        // Prevents two profile applies from fighting over item positions.
        layoutTask?.cancel()
        let generation = beginLayoutApply()

        let pinnedHidden = Set(profile.menuBarLayout.pinnedHiddenBundleIDs)
        let pinnedAlwaysHidden = Set(profile.menuBarLayout.pinnedAlwaysHiddenBundleIDs)
        let sectionOrder = profile.menuBarLayout.savedSectionOrder
        let itemSectionMap = profile.menuBarLayout.itemSectionMap ?? [:]
        let itemOrder = profile.menuBarLayout.itemOrder ?? [:]

        // Snapshot hook configuration on MainActor with the other apply preparation.
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
            // Global pre-hooks provide common setup; profile pre-hooks can override or extend it.
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

            // Apply spacing before layout: relaunches reset item positions; matching offsets no-op.
            // Arm settling before relaunch to suppress partial cache restores, then wait for reattachment before layout.

            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:preflight")

            let didRelaunch: Bool
            let recovered: Set<String>
            do {
                // An unstructured wave survives superseding layout-task cancellation; see sleepIgnoringCancellation(for:).
                let outcome = try await Task {
                    try await appState.spacingManager.applyOffset()
                }.value
                didRelaunch = outcome.didRelaunch
                recovered = outcome.recoveredBundleIDs
            } catch is CancellationError {
                // Drop preflight settling on cancellation so stale layout work cannot overwrite a newer apply.
                appState.itemManager.cancelSettlingPeriod(reason: "spacingRelaunch:cancelled")
                return
            } catch {
                self?.diagLog.error("spacingRelaunch: applyOffset failed: \(error)")
                didRelaunch = false
                recovered = []
            }
            // The wave ignores this task's cancellation; recheck now and clean up rather than lay out a superseded profile.
            if Task.isCancelled {
                appState.itemManager.cancelSettlingPeriod(reason: "spacingRelaunch:cancelled")
                return
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
            let layoutDidRun = await appState.itemManager.applyProfileLayout(
                pinnedHidden: pinnedHidden,
                pinnedAlwaysHidden: pinnedAlwaysHidden,
                sectionOrder: sectionOrder,
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder
            )
            if !layoutDidRun {
                self?.recordLayoutDidNotRun(generation: generation)
            }

            // Reverse pre-hook order for teardown; skip post-hooks when a newer apply cancels this task.
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
            // Recheck cancellation after a long profile script to avoid firing global teardown for a superseded apply.
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

        // Install the fallback template before per-display entries. Profiles
        // created on another machine may not contain this display's UUID.
        appState.settings.displaySettings.globalConfiguration = profile.globalDisplayConfiguration

        // Set before the configurations, whose change applies spacing under this mode.
        if let spacingApplyMode = profile.spacingApplyMode {
            appState.settings.displaySettings.spacingApplyMode = spacingApplyMode
        }
        appState.settings.displaySettings.configurations = profile.displayConfigurations
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

        // Resolve layout against this profile's groups, not the outgoing profile's.
        appState.itemGroupManager.apply(profile.menuBarLayout.itemGroups)

        // Set badge placement before layout so late arrivals use the profile-defined spot.
        if let placement = profile.menuBarLayout.newItemsPlacement {
            appState.itemManager.applyNewItemsPlacement(placement)
        }
    }

    func deleteProfile(id: UUID) throws {
        let url = profileURL(for: id)
        try FileManager.default.removeItem(at: url)
        profiles.removeAll { $0.id == id }
        try saveManifest()
    }

    /// Undo restores the same identity and manifest position, not a copy.
    /// Reclaim display and Space associations by clearing competing owners, as association setters do.
    func restoreProfile(
        _ profile: Profile,
        metadata: ProfileMetadata,
        at index: Int,
        wasActive: Bool
    ) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: metadata.id), options: .atomic)

        if let displayUUID = metadata.associatedDisplayUUID {
            for i in profiles.indices where profiles[i].associatedDisplayUUID == displayUUID {
                profiles[i].associatedDisplayUUID = nil
                profiles[i].associatedDisplayName = nil
            }
        }
        if let spaceKey = metadata.associatedSpaceKey {
            for i in profiles.indices where profiles[i].associatedSpaceKey == spaceKey {
                profiles[i].associatedSpaceKey = nil
                profiles[i].associatedSpaceName = nil
            }
        }

        if let existing = profiles.firstIndex(where: { $0.id == metadata.id }) {
            profiles[existing] = metadata
        } else {
            profiles.insert(metadata, at: min(max(index, 0), profiles.count))
        }
        try saveManifest()

        if wasActive {
            activeProfileID = metadata.id
        }
    }

    /// Undo saved content without applying it; reverting a saved copy must not rearrange the live bar.
    func replaceProfile(_ profile: Profile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: profile.id), options: .atomic)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].modifiedAt = profile.modifiedAt
        }
        try saveManifest()
    }

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
        try saveManifest()
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
        try saveManifest()
    }

    /// Exports a profile to a file, including display associations.
    func exportProfile(id: UUID, to url: URL) throws {
        let profile = try loadProfile(id: id)
        let meta = profiles.first { $0.id == id }
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: meta?.associatedDisplayUUID,
            associatedDisplayName: meta?.associatedDisplayName,
            associatedSpaceKey: meta?.associatedSpaceKey,
            associatedSpaceName: meta?.associatedSpaceName
        )
        let bundle = ProfileExportBundle(entries: [entry])
        let data = try encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
    }

    /// Overwrites an existing profile with the current app state,
    /// keeping its id, name, display association, and creation date.
    func updateProfileWithCurrentState(id: UUID, appState: AppState) throws {
        guard let old = profiles.first(where: { $0.id == id }) else { return }

        let tempName = "__temp_update__"
        try saveProfile(name: tempName, from: appState)
        guard let tempMeta = profiles.last, tempMeta.name == tempName else { return }

        // Preserve the original identity when replacing captured content.
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

        try? FileManager.default.removeItem(at: profileURL(for: tempMeta.id))
        profiles.removeAll { $0.id == tempMeta.id }

        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].modifiedAt = updated.modifiedAt
        }
        try saveManifest()

        // Rearm the active layout cache without moving items so New Items placement uses the newly saved order.
        rearmActiveLayoutIfNeeded(
            updatedID: id,
            scope: .all,
            layout: captureCurrentLayout(
                from: appState.itemManager,
                groups: appState.itemGroupManager.snapshot()
            ),
            itemManager: appState.itemManager
        )
    }

    // MARK: - Capture Helpers

    /// Share profile capture with preview diffs so closed apps and transient widgets do not produce promised but unapplied moves.
    func currentLayoutSnapshot(from appState: AppState) -> MenuBarLayoutSnapshot {
        captureCurrentLayout(
            from: appState.itemManager,
            groups: appState.itemGroupManager.snapshot()
        )
    }

    /// Depend only on the item manager and defaults so capture and rearm tests need no AppState.
    func captureCurrentLayout(
        from itemManager: MenuBarItemManager,
        groups: MenuBarItemGroupSet
    ) -> MenuBarLayoutSnapshot {
        let computedItemOrder = itemManager.computeSectionOrder(
            from: itemManager.itemCache
        )
        let persistedSectionOrder = UserDefaults.standard.dictionary(
            forKey: "MenuBarItemManager.savedSectionOrder"
        ) as? [String: [String]] ?? [:]

        // An empty cache without a display ID is not meaningful; preserve mirrored assignments rather than erase the profile.
        let itemOrder: [String: [String]] = if computedItemOrder.isEmpty,
                                               itemManager.itemDisplayID == nil,
                                               !persistedSectionOrder.isEmpty
        {
            persistedSectionOrder
        } else {
            computedItemOrder
        }
        // macOS 27 membership lives in RuntimeSectionController; mirror curated cache order for complete visible/hidden profile snapshots.
        let savedSectionOrder: [String: [String]] = itemOrder
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

        // Apply requires itemOrder and savedSectionOrder to agree; computeSectionOrder preserves closed apps and filters transient widgets.
        // Direct cache iteration would route closed saved apps through unmanaged placement instead of their saved section.
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
            itemHotkeys: itemHotkeys,
            itemGroups: groups
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
        profile.spacingApplyMode = appState.settings.displaySettings.spacingApplyMode
        profile.appearanceConfiguration = appState.appearanceManager.configuration
    }

    /// Saves a profile to disk and updates the manifest.
    private func saveProfileAndUpdateManifest(_ profile: Profile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: profile.id), options: .atomic)

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].modifiedAt = profile.modifiedAt
        }
        try saveManifest()
    }

    // MARK: - Scoped Updates

    /// What parts of a profile to update.
    enum ProfileUpdateScope {
        case all
        case layoutOnly
        case configurationOnly
    }

    /// Rearm only fresh layout updates to the active profile; configuration-only or inactive edits must not touch live layout state.
    /// Otherwise New Items placement would use stale cached order until manual reapply.
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
            try updateProfileLayout(
                id: id,
                itemManager: appState.itemManager,
                groups: appState.itemGroupManager.snapshot()
            )
        case .configurationOnly:
            try updateProfileConfiguration(id: id, appState: appState)
        }
    }

    /// Narrow the dependency to the item manager so integration tests can update layout through an injected directory without AppState.
    func updateProfileLayout(
        id: UUID,
        itemManager: MenuBarItemManager,
        groups: MenuBarItemGroupSet? = nil
    ) throws {
        var profile = try loadProfile(id: id)
        // Preserve existing groups when no fresh snapshot is supplied; defaulting to none would silently erase them.
        let layout = captureCurrentLayout(
            from: itemManager,
            groups: groups ?? profile.menuBarLayout.itemGroups ?? .empty
        )
        profile.menuBarLayout = layout
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
        rearmActiveLayoutIfNeeded(updatedID: id, scope: .layoutOnly, layout: layout, itemManager: itemManager)
    }

    /// Sync the active profile's cached spec after fresh layout capture so New Items placement uses it without reapply.
    /// The captured layout already matches the bar; move nothing and no-op for inactive profiles.
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

    /// Broadcast spacing to every profile's display entry, creating missing entries from the global template.
    /// DisplaySettingsPane uses this to prevent the next profile reapply from reverting confirmed spacing.
    func updateAllProfilesItemSpacingOffset(displayUUID: String, offset: Double) throws {
        let now = Date()
        var pending: [Profile] = []
        pending.reserveCapacity(profiles.count)
        for meta in profiles {
            var profile = try loadProfile(id: meta.id)
            let base = profile.displayConfigurations[displayUUID] ?? profile.globalDisplayConfiguration
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
        try saveManifest()
    }

    /// Broadcast global configuration and optionally every display entry so profile reapply cannot revert it.
    /// Load all profiles before writing and update the manifest once, as in spacing broadcasts, to limit partial-update failures.
    func updateAllProfilesGlobalConfiguration(
        _ config: DisplayThawBarConfiguration,
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
        try saveManifest()
    }

    // MARK: - Profile Hooks

    /// Return empty automation when a profile has no hooks or cannot be loaded.
    func hooks(forProfileID id: UUID) -> ProfileAutomation {
        guard let profile = try? loadProfile(id: id) else {
            return ProfileAutomation()
        }
        return profile.automation ?? ProfileAutomation()
    }

    /// nil clears the hook; rewrite profile JSON and bump manifest modifiedAt for UI updates.
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
                associatedDisplayName: meta.associatedDisplayName,
                associatedSpaceKey: meta.associatedSpaceKey,
                associatedSpaceName: meta.associatedSpaceName
            ))
        }
        let bundle = ProfileExportBundle(entries: entries)
        guard let data = try? encoder.encode(bundle) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Space Association

    /// Enforce unique Space ownership and cache the display label.
    func setAssociatedSpace(key: String?, spaceName: String? = nil, forProfileID profileID: UUID) {
        if let key {
            for index in profiles.indices where profiles[index].associatedSpaceKey == key {
                profiles[index].associatedSpaceKey = nil
                profiles[index].associatedSpaceName = nil
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].associatedSpaceKey = key
            profiles[index].associatedSpaceName = key != nil ? spaceName : nil
        }
        persistManifest()
    }

    /// Returns the profile associated with the given Space key, if any.
    func profile(forSpaceKey key: String) -> ProfileMetadata? {
        profiles.first { $0.associatedSpaceKey == key }
    }

    // MARK: - Display Association

    /// Enforce unique display ownership and retain its name for disconnected displays.
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
        persistManifest()
    }

    /// Clears the display association from whichever profile currently holds it.
    func setAssociatedDisplay(uuid _: String?, forDisplayUUID displayUUID: String) {
        for index in profiles.indices where profiles[index].associatedDisplayUUID == displayUUID {
            profiles[index].associatedDisplayUUID = nil
            profiles[index].associatedDisplayName = nil
        }
        persistManifest()
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

            hotkeyProfileMap[ObjectIdentifier(hotkey)] = profileID

            // Assign after loading so the callback persists only future recorder changes.
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
                let newCombo = hotkey.keyCombination
                var dict = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
                if let combo = newCombo, let data = try? enc.encode(combo) {
                    dict[profileID.uuidString] = data
                } else {
                    dict.removeValue(forKey: profileID.uuidString)
                }
                Defaults.set(dict, forKey: .profileHotkeys)
                hotkeyProfileMap[ObjectIdentifier(hotkey)] = newCombo != nil ? profileID : nil
            }

            newHotkeys[meta.id] = hotkey
        }
        profileHotkeys = newHotkeys
    }

    // MARK: - Auto-Switch

    /// Apply the new display's profile unless Focus or a Space association takes priority.
    private func checkDisplayAndAutoSwitch() async {
        guard let currentUUID = Bridging.getActiveMenuBarDisplayUUID() else { return }
        guard currentUUID != lastActiveDisplayUUID else { return }
        lastActiveDisplayUUID = currentUUID

        // Don't override a Focus Filter profile with a display switch.
        guard !focusFilterActive else { return }

        // Explicit Space associations outrank incidental display changes such as docking, wake, or resolution changes.
        if let spaceKey = SpaceInfo.activeSpace().persistentKey,
           profile(forSpaceKey: spaceKey) != nil
        {
            diagLog.debug("Display auto-switch yielding to Space association \(spaceKey)")
            return
        }

        await applyProfileForDisplay(uuid: currentUUID)
    }

    /// Already-active guards make switches between Spaces sharing a profile no-ops.
    private func checkSpaceAndAutoSwitch() async {
        guard let key = SpaceInfo.activeSpace().persistentKey else {
            // Mid-animation Spaces may not have published keys yet; leave the bar unchanged until a later switch resolves.
            diagLog.debug("Space auto-switch: active Space has no persistent key yet")
            return
        }
        guard key != lastActiveSpaceKey else { return }
        lastActiveSpaceKey = key

        // Focus outranks a Space switch, same as it outranks a display one.
        guard !focusFilterActive else { return }

        await applyProfileForSpace(key: key)
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

    /// Reapply after spacing relaunch resets positions, since auto-switch does not fire for the same active profile.
    /// applyOffset no-ops and layout waits for expected-set settling; the active profile remains unchanged.
    func reapplyActiveProfile() {
        guard let appState else { return }
        guard let activeID = activeProfileID else { return }
        do {
            let profile = try loadProfile(id: activeID)
            // Identical previous and current IDs let hooks distinguish refresh from profile switching.
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

            // Reconcile Space ownership too; foreign-Mac keys remain inert when no local Space matches.
            if let spaceKey = entry.associatedSpaceKey {
                setAssociatedSpace(
                    key: spaceKey,
                    spaceName: entry.associatedSpaceName,
                    forProfileID: imported.id
                )
            }
        }
        try saveManifest()
    }
}
