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

    init() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory not found")
        }
        profilesDirectory = appSupport
            .appendingPathComponent("Thaw/Profiles", isDirectory: true)
        manifestURL = profilesDirectory
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
                Task { await self.checkDisplayAndAutoSwitch() }
            }
            .store(in: &cancellables)

        // Listen for Focus Filter activation from the system.
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.stonerl.Thaw.focusFilterActivated"))
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.applyFocusFilterProfile() }
            }
            .store(in: &cancellables)

        // Listen for Focus Filter deactivation (Focus mode turned off).
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.stonerl.Thaw.focusFilterDeactivated"))
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.handleFocusFilterDeactivated() }
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
            // No Focus Filter — fall back to display-based profile.
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
                appearanceConfiguration: appState.appearanceManager.configuration,
                menuBarLayout: captureCurrentLayout(from: appState)
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
    func applyProfile(_ profile: Profile, to appState: AppState) {
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

        // Apply appearance configuration
        appState.appearanceManager.configuration = profile.appearanceConfiguration

        // Apply custom names to UserDefaults.
        Defaults.set(
            profile.menuBarLayout.customNames,
            forKey: .menuBarItemCustomNames
        )

        // Cancel any in-flight layout task before starting a new one.
        // Prevents two profile applies from fighting over item positions.
        layoutTask?.cancel()

        let pinnedHidden = Set(profile.menuBarLayout.pinnedHiddenBundleIDs)
        let pinnedAlwaysHidden = Set(profile.menuBarLayout.pinnedAlwaysHiddenBundleIDs)
        let sectionOrder = profile.menuBarLayout.savedSectionOrder
        let itemSectionMap = profile.menuBarLayout.itemSectionMap ?? [:]
        let itemOrder = profile.menuBarLayout.itemOrder ?? [:]
        layoutGeneration &+= 1
        let generation = layoutGeneration
        layoutTask = Task { [weak self] in
            await appState.itemManager.applyProfileLayout(
                pinnedHidden: pinnedHidden,
                pinnedAlwaysHidden: pinnedAlwaysHidden,
                sectionOrder: sectionOrder,
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder
            )
            if self?.layoutGeneration == generation {
                self?.layoutTask = nil
            }
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
    }

    // MARK: - Capture Helpers

    /// Captures the current menu bar layout from the app state.
    private func captureCurrentLayout(from appState: AppState) -> MenuBarLayoutSnapshot {
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

        var itemSectionMap = [String: String]()
        var itemOrder = [String: [String]]()
        let cache = appState.itemManager.itemCache
        for section in MenuBarSection.Name.allCases {
            let sectionKey: String
            switch section {
            case .visible: sectionKey = "visible"
            case .hidden: sectionKey = "hidden"
            case .alwaysHidden: sectionKey = "alwaysHidden"
            }
            var orderedIDs = [String]()
            for item in cache.managedItems(for: section)
                where item.canBeHidden || item.isControlItem
            {
                let uid = item.uniqueIdentifier
                itemSectionMap[uid] = sectionKey
                orderedIDs.append(uid)
            }
            if !orderedIDs.isEmpty {
                itemOrder[sectionKey] = orderedIDs
            }
        }

        return MenuBarLayoutSnapshot(
            savedSectionOrder: savedSectionOrder,
            pinnedHiddenBundleIDs: pinnedHiddenBundleIDs,
            pinnedAlwaysHiddenBundleIDs: pinnedAlwaysHiddenBundleIDs,
            customNames: customNames,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
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

    /// Updates a profile with only the specified scope of current state.
    func updateProfile(id: UUID, scope: ProfileUpdateScope, appState: AppState) throws {
        switch scope {
        case .all:
            try updateProfileWithCurrentState(id: id, appState: appState)
        case .layoutOnly:
            try updateProfileLayout(id: id, appState: appState)
        case .configurationOnly:
            try updateProfileConfiguration(id: id, appState: appState)
        }
    }

    /// Updates only the menu bar layout of an existing profile.
    private func updateProfileLayout(id: UUID, appState: AppState) throws {
        var profile = try loadProfile(id: id)
        profile.menuBarLayout = captureCurrentLayout(from: appState)
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
    }

    /// Updates only the configuration (settings, hotkeys, appearance) of an existing profile.
    private func updateProfileConfiguration(id: UUID, appState: AppState) throws {
        var profile = try loadProfile(id: id)
        applyCurrentConfiguration(to: &profile, from: appState)
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
            activeProfileID = profileID
            focusFilterActive = true
            applyProfile(profile, to: appState)
        } catch {
            diagLog.error("Focus Filter apply failed: \(error)")
        }
    }

    /// Called when the Focus Filter deactivates (Focus mode turned off).
    /// Reverts to the display-based profile.
    private func handleFocusFilterDeactivated() async {
        guard focusFilterActive else { return }
        focusFilterActive = false
        diagLog.info("Focus Filter deactivated — reverting to display profile")
        if let uuid = Bridging.getActiveMenuBarDisplayUUID() {
            await applyProfileForDisplay(uuid: uuid)
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
            activeProfileID = meta.id
            applyProfile(profile, to: appState)
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
