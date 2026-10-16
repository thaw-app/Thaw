//
//  ProfileManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Foundation

@MainActor
@Observable
final class ProfileManager {
    /// The manager's list of profile metadata.
    ///
    /// `didSet` doesn't fire in `init`. Before ``performSetup(with:)``,
    /// ``rebuildProfileHotkeys()`` no-ops on its `appState` guard.
    private(set) var profiles: [ProfileMetadata] = [] {
        didSet {
            rebuildProfileHotkeys()
        }
    }

    /// The ID of the currently active profile, or `nil`.
    var activeProfileID: UUID?

    // Not private only because ProfileManager+Live.swift extends this class.
    // None of these are part of the intended surface.
    let diagLog = DiagLog(category: "ProfileManager")
    private let encoder: JSONEncoder
    let decoder: JSONDecoder
    private let profilesDirectory: URL
    private let manifestURL: URL
    weak var appState: AppState?

    /// Tasks backing the swift-async-algorithms debounces installed by
    /// ``performSetup(with:)``. Each owns its own notification observer and
    /// removes it when the task ends, so `deinit` only has to cancel them.
    private(set) var screenParametersTask: Task<Void, Never>?
    private(set) var focusFilterActivatedTask: Task<Void, Never>?
    private(set) var focusFilterDeactivatedTask: Task<Void, Never>?
    private(set) var spaceChangeTask: Task<Void, Never>?

    /// Tracks the last seen active display UUID for auto-switch debouncing.
    var lastActiveDisplayUUID: String?
    /// Tracks the last seen active Space key for auto-switch debouncing.
    var lastActiveSpaceKey: String?
    /// Whether a Focus Filter profile is currently applied.
    var focusFilterActive = false
    /// The in-flight layout apply task. Exposed for callers that need to
    /// wait for the layout to finish (e.g. the Apply button).
    var layoutTask: Task<Void, Never>?

    /// Generation counter to prevent older layout tasks from clearing newer ones.
    var layoutGeneration: UInt = 0

    /// Hotkeys for switching to each profile, keyed by profile ID.
    var profileHotkeys: [UUID: Hotkey] = [:]
    /// Maps Hotkey identity to profile ID for the perform() lookup.
    var hotkeyProfileMap: [ObjectIdentifier: UUID] = [:]

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

    @MainActor
    deinit {
        // Each observer task is manually owned, so cancel it here. Ending a
        // task runs its defer, which removes its notification observer.
        screenParametersTask?.cancel()
        focusFilterActivatedTask?.cancel()
        focusFilterDeactivatedTask?.cancel()
        spaceChangeTask?.cancel()
    }

    /// (Re)starts the notification observation tasks, cancelling any previous
    /// ones so their observers don't keep running. Kept out of
    /// `performSetup(with:)` so the wiring is testable without an `AppState`.
    func startObservationTasks() {
        // Listen for display changes to trigger auto-switch.
        screenParametersTask?.cancel()
        screenParametersTask = debouncedNotificationTask(
            center: .default,
            name: NSApplication.didChangeScreenParametersNotification,
            interval: .seconds(1.5)
        ) { [weak self] in
            await self?.checkDisplayAndAutoSwitch()
        }

        // Listen for Focus Filter activation from the system.
        focusFilterActivatedTask?.cancel()
        focusFilterActivatedTask = debouncedNotificationTask(
            center: DistributedNotificationCenter.default(),
            name: Notification.Name("com.stonerl.Thaw.focusFilterActivated"),
            interval: .seconds(0.5)
        ) { [weak self] in
            await self?.applyFocusFilterProfile()
        }

        // Listen for Focus Filter deactivation (Focus mode turned off).
        focusFilterDeactivatedTask?.cancel()
        focusFilterDeactivatedTask = debouncedNotificationTask(
            center: DistributedNotificationCenter.default(),
            name: Notification.Name("com.stonerl.Thaw.focusFilterDeactivated"),
            interval: .seconds(0.5)
        ) { [weak self] in
            await self?.handleFocusFilterDeactivated()
        }

        // Listen for Space switches to trigger auto-switch. Debounced a
        // little longer than the switch animation so a fast swipe across
        // three Spaces applies one profile rather than three.
        spaceChangeTask?.cancel()
        spaceChangeTask = debouncedNotificationTask(
            center: NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            interval: .seconds(0.75)
        ) { [weak self] in
            await self?.checkSpaceAndAutoSwitch()
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

    /// Captures the current configuration and saves it as a named profile.
    ///
    /// Takes only the stores the capture reads so tests don't need an
    /// AppState. The `AppState` overload in ProfileManager+Live.swift
    /// forwards here.
    func saveProfile(
        name: String,
        settings: AppSettings,
        appearanceManager: MenuBarAppearanceManager,
        itemManager: MenuBarItemManager
    ) throws {
        let profile = Profile(
            name: name,
            content: ProfileContent(
                generalSettings: GeneralSettingsSnapshot.capture(from: settings.general),
                advancedSettings: AdvancedSettingsSnapshot.capture(from: settings.advanced),
                hotkeys: Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:],
                displayConfigurations: settings.displaySettings.configurations,
                globalDisplayConfiguration: settings.displaySettings.globalConfiguration,
                confirmSpacingRelaunch: settings.displaySettings.confirmSpacingRelaunch,
                unconfirmedSpacingProfileScope: settings.displaySettings.unconfirmedSpacingProfileScope,
                appearanceConfiguration: appearanceManager.configuration,
                menuBarLayout: captureCurrentLayout(from: itemManager)
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

    // MARK: - Persisted layout repair

    /// Runs ``repairPersistedLayouts()`` once per app build, so a build that
    /// recognizes a new class of unmatchable identifier gets another pass.
    func repairPersistedLayoutsIfNeeded() {
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        guard Defaults.string(forKey: .profileLayoutRepairBuild) != currentBuild else {
            return
        }
        repairPersistedLayouts()
        Defaults.set(currentBuild, forKey: .profileLayoutRepairBuild)
    }

    /// Rewrites every profile on disk with its layout pruned.
    ///
    /// Read-time pruning leaves the damage on disk, where `armProfileState`
    /// seeds from it at startup and a manual re-apply brings entries back.
    ///
    /// ``MenuBarLayoutSnapshot/itemSectionMap`` is filtered by the same
    /// verdict: `resolvedItemSectionMap` returns it verbatim, so an entry
    /// left in the map would still be planned against.
    ///
    /// Files that fail to decode are left untouched and logged.
    ///
    /// - Returns: The number of profiles rewritten.
    @discardableResult
    func repairPersistedLayouts() -> Int {
        var repaired = 0

        for metadata in profiles {
            let url = profileURL(for: metadata.id)
            let profile: Profile
            do {
                profile = try decoder.decode(Profile.self, from: Data(contentsOf: url))
            } catch {
                diagLog.error("repairPersistedLayouts: skipping \(metadata.id), cannot decode: \(error)")
                continue
            }

            var layout = profile.menuBarLayout
            let originalOrder = layout.itemOrder
            let originalSavedOrder = layout.savedSectionOrder
            let originalMap = layout.itemSectionMap

            let displayNameAliases = MenuBarItemManager.controlCenterDisplayNameAliases()
            layout.savedSectionOrder = LayoutSolver.prunedSectionOrder(
                LayoutSolver.canonicalizedSectionOrder(layout.savedSectionOrder),
                displayNameAliases: displayNameAliases
            )
            if let itemOrder = layout.itemOrder {
                layout.itemOrder = LayoutSolver.prunedSectionOrder(
                    LayoutSolver.canonicalizedSectionOrder(itemOrder),
                    displayNameAliases: displayNameAliases
                )
            }

            if let map = layout.itemSectionMap {
                // Same empty-means-absent rule as `resolvedItemOrder`: a
                // present-but-empty itemOrder is a mistimed capture, not a
                // layout, and filtering against it would empty the map and
                // permanently shadow the savedSectionOrder fallback.
                let survivingOrder: [String: [String]] = {
                    guard let itemOrder = layout.itemOrder, !itemOrder.isEmpty else {
                        return layout.savedSectionOrder
                    }
                    return itemOrder
                }()
                let surviving = Set(survivingOrder.values.joined())
                // The orders above were canonicalized; map keys must be
                // compared (and stored) in the same form or a pre-canonical
                // entry is dropped even though its item survived.
                var filteredMap = [String: String]()
                for (key, section) in map {
                    let canonicalKey = LayoutSolver.canonicalIdentifier(key)
                    guard surviving.contains(canonicalKey) else { continue }
                    if filteredMap[canonicalKey] == nil || key == canonicalKey {
                        filteredMap[canonicalKey] = section
                    }
                }
                layout.itemSectionMap = filteredMap
            }

            guard
                layout.savedSectionOrder != originalSavedOrder ||
                layout.itemOrder != originalOrder ||
                layout.itemSectionMap != originalMap
            else {
                continue
            }

            var updated = profile
            updated.menuBarLayout = layout
            do {
                let data = try encoder.encode(updated)
                try data.write(to: url, options: .atomic)
                repaired += 1
                diagLog.info("repairPersistedLayouts: rewrote profile \(metadata.name)")
            } catch {
                diagLog.error("repairPersistedLayouts: failed to write \(metadata.id): \(error)")
            }
        }

        if repaired > 0 {
            diagLog.info("repairPersistedLayouts: repaired \(repaired) profile(s)")
        }
        return repaired
    }

    /// Deletes a profile by its identifier.
    ///
    /// An already-absent file counts as success and the manifest entry is
    /// still removed, or the profile could never be deleted. Any other
    /// failure keeps both file and entry and rethrows, so the file isn't
    /// orphaned.
    func deleteProfile(id: UUID) throws {
        let url = profileURL(for: id)

        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            diagLog.debug(
                "deleteProfile: file already absent for \(id), removing manifest entry anyway"
            )
        }

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

    /// Overwrites an existing profile with the current configuration,
    /// keeping its id, name, display association, and creation date.
    /// Same narrow-dependency seam as
    /// ``saveProfile(name:settings:appearanceManager:itemManager:)``.
    func updateProfileWithCurrentState(
        id: UUID,
        settings: AppSettings,
        appearanceManager: MenuBarAppearanceManager,
        itemManager: MenuBarItemManager
    ) throws {
        guard let old = profiles.first(where: { $0.id == id }) else { return }

        // Capture via a temp profile, then re-save it under the original identity.
        let tempName = "__temp_update__"
        try saveProfile(
            name: tempName,
            settings: settings,
            appearanceManager: appearanceManager,
            itemManager: itemManager
        )
        guard let tempMeta = profiles.last, tempMeta.name == tempName else { return }

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
        saveManifest()

        // The content was just captured from the running state, so it is the
        // configuration in effect: mark it active. Set before the re-arm below
        // so its active-profile gate sees this profile.
        activeProfileID = id

        // The live arrangement is unchanged by this save, so re-capturing it
        // yields the same layout that was just persisted. Re-arm the cache from
        // it when this is the active profile so a later late-arrival re-sort
        // honours the update instead of reverting to the pre-update spec.
        rearmActiveLayoutIfNeeded(
            updatedID: id,
            scope: .all,
            layout: captureCurrentLayout(from: itemManager),
            itemManager: itemManager
        )
    }

    // MARK: - Capture Helpers

    /// Captures the current menu bar layout. Depends only on the item manager
    /// (and UserDefaults), not the full app state, so the capture and re-arm
    /// paths can be exercised in tests without standing up an AppState.
    private func captureCurrentLayout(from itemManager: MenuBarItemManager) -> MenuBarLayoutSnapshot {
        let savedSectionOrder = Defaults.store.dictionary(
            forKey: MenuBarItemManager.LayoutStateKey.savedSectionOrder
        ) as? [String: [String]] ?? [:]
        let pinnedHiddenBundleIDs = Defaults.store.array(
            forKey: MenuBarItemManager.LayoutStateKey.pinnedHiddenBundleIDs
        ) as? [String] ?? []
        let pinnedAlwaysHiddenBundleIDs = Defaults.store.array(
            forKey: MenuBarItemManager.LayoutStateKey.pinnedAlwaysHiddenBundleIDs
        ) as? [String] ?? []
        let customNames = Defaults.dictionary(
            forKey: .menuBarItemCustomNames
        ) as? [String: String] ?? [:]
        let itemHotkeys = Defaults.dictionary(
            forKey: .menuBarItemHotkeys
        ) as? [String: Data] ?? [:]

        // itemOrder must agree with savedSectionOrder. Iterating itemCache
        // directly dropped closed-but-saved apps and kept transient Control
        // Center widgets, so re-apply treated those apps as unmanaged.
        // computeSectionOrder applies the same filter and closed-app merge.
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
    private func applyCurrentConfiguration(
        to profile: inout Profile,
        settings: AppSettings,
        appearanceManager: MenuBarAppearanceManager
    ) {
        profile.generalSettings = GeneralSettingsSnapshot.capture(
            from: settings.general
        )
        profile.advancedSettings = AdvancedSettingsSnapshot.capture(
            from: settings.advanced
        )
        profile.hotkeys = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:]
        profile.displayConfigurations = settings.displaySettings.configurations
        profile.globalDisplayConfiguration = settings.displaySettings.globalConfiguration
        profile.confirmSpacingRelaunch = settings.displaySettings.confirmSpacingRelaunch
        profile.unconfirmedSpacingProfileScope = settings.displaySettings.unconfirmedSpacingProfileScope
        profile.appearanceConfiguration = appearanceManager.configuration
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
    /// True only when the updated profile is active and the update captured a
    /// fresh layout (.all or .layoutOnly). Without re-arming, the next
    /// late-arrival re-sort reverts the bar to the pre-update spec.
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
    /// Same narrow-dependency seam as
    /// ``saveProfile(name:settings:appearanceManager:itemManager:)``.
    func updateProfile(
        id: UUID,
        scope: ProfileUpdateScope,
        settings: AppSettings,
        appearanceManager: MenuBarAppearanceManager,
        itemManager: MenuBarItemManager
    ) throws {
        switch scope {
        case .all:
            try updateProfileWithCurrentState(
                id: id,
                settings: settings,
                appearanceManager: appearanceManager,
                itemManager: itemManager
            )
        case .layoutOnly:
            try updateProfileLayout(id: id, itemManager: itemManager)
        case .configurationOnly:
            try updateProfileConfiguration(
                id: id,
                settings: settings,
                appearanceManager: appearanceManager
            )
        }
    }

    /// Updates only the menu bar layout of an existing profile. Takes the item
    /// manager rather than the app state so tests can drive it.
    func updateProfileLayout(id: UUID, itemManager: MenuBarItemManager) throws {
        var profile = try loadProfile(id: id)
        let layout = captureCurrentLayout(from: itemManager)
        profile.menuBarLayout = layout
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
        rearmActiveLayoutIfNeeded(updatedID: id, scope: .layoutOnly, layout: layout, itemManager: itemManager)
    }

    /// Rewrites one section's order in the active profile's persisted layout
    /// to the given sorted identifiers, so a subsequent
    /// ``reapplyActiveProfile`` applies the new order instead of the stale
    /// on-disk one. Used by the "Sort A→Z" action, which writes the
    /// live ``savedSectionOrder`` first and then calls this so the profile
    /// and the live bar stay in sync. Returns true when an active profile
    /// was updated.
    @discardableResult
    func updateActiveProfileSectionOrder(
        _ section: MenuBarSection.Name,
        identifiers: [String]
    ) -> Bool {
        guard let activeID = activeProfileID else { return false }
        let key = switch section {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "alwaysHidden"
        }
        do {
            var profile = try loadProfile(id: activeID)
            var layout = profile.menuBarLayout
            var saved = layout.savedSectionOrder
            saved[key] = identifiers
            layout.savedSectionOrder = saved
            // Seed a missing itemOrder from the full savedSectionOrder. A
            // single-section dict would shadow the complete order and drop
            // every other section on reapply.
            if layout.itemOrder == nil {
                layout.itemOrder = saved
            }
            layout.itemOrder?[key] = identifiers
            profile.menuBarLayout = layout
            profile.modifiedAt = Date()
            try saveProfileAndUpdateManifest(profile)
            return true
        } catch {
            diagLog.error("updateActiveProfileSectionOrder failed: \(error)")
            return false
        }
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
            itemSectionMap: layout.resolvedItemSectionMap,
            itemOrder: layout.resolvedItemOrder
        )
    }

    /// Updates only the configuration (settings, hotkeys, appearance) of an existing profile.
    private func updateProfileConfiguration(
        id: UUID,
        settings: AppSettings,
        appearanceManager: MenuBarAppearanceManager
    ) throws {
        var profile = try loadProfile(id: id)
        applyCurrentConfiguration(
            to: &profile,
            settings: settings,
            appearanceManager: appearanceManager
        )
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

    /// Sets the associated Space key for a profile, clearing it from any
    /// other profile that previously held it (enforces uniqueness), and
    /// caches a user-supplied label for display.
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
        saveManifest()
    }

    /// Returns the profile associated with the given Space key, if any.
    func profile(forSpaceKey key: String) -> ProfileMetadata? {
        profiles.first { $0.associatedSpaceKey == key }
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

            // Same reconciliation for the Space association. A key exported
            // from another Mac will not match any local Space, so it sits
            // inert rather than binding the profile to the wrong desktop.
            if let spaceKey = entry.associatedSpaceKey {
                setAssociatedSpace(
                    key: spaceKey,
                    spaceName: entry.associatedSpaceName,
                    forProfileID: imported.id
                )
            }
        }
        saveManifest()
    }
}
