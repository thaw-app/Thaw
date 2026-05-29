//
//  DisplaySettingsManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

/// Manages per-display Thaw Bar configuration.
///
/// Configurations are keyed by display UUID string (via `Bridging.getDisplayUUIDString(for:)`).
/// When a display has no explicit configuration, `DisplayIceBarConfiguration.defaultConfiguration`
/// is returned.
@MainActor
final class DisplaySettingsManager: ObservableObject {
    private let diagLog = DiagLog(category: "DisplaySettingsManager")

    /// Per-display configurations, keyed by display UUID string.
    @Published var configurations: [String: DisplayIceBarConfiguration] = [:]

    /// The global configuration template applied to all displays by the
    /// Apply-to-All action in the Displays pane and used as the seed for
    /// newly connected displays. Persisted independently from
    /// configurations so the template survives display disconnects, and
    /// captured by every Profile so each profile carries its own global.
    @Published var globalConfiguration: DisplayIceBarConfiguration = .defaultConfiguration

    /// Cache of previously-seen displays (name + notch state), keyed by
    /// display UUID. Lets the Displays pane show settings rows for
    /// disconnected displays so users can edit them without having to
    /// re-connect the display first.
    @Published var knownDisplays: [String: KnownDisplay] = [:]

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// JSON encoder for persistence.
    private let encoder = JSONEncoder()

    /// JSON decoder for persistence.
    private let decoder = JSONDecoder()

    /// Reference to AppState for driving spacingManager and itemManager from
    /// active-display configuration changes. Held weakly to avoid retain cycles.
    private weak var appState: AppState?

    /// UUID of the active menu bar display the last time spacing was applied.
    /// Used to skip didChangeScreenParametersNotification fires that only
    /// reflect a resolution or other-parameter change on the same display.
    /// Internal access so unit tests in ThawTests can seed and assert it.
    var lastAppliedActiveDisplayUUID: String?

    /// UUID of the display that currently owns the menu bar, or nil if it
    /// cannot be determined. Exposed for views that need to decide whether
    /// a spacing change will trigger the relaunch wave (only writes against
    /// the active display do, because applyActiveDisplaySpacing only reads
    /// configurationForActiveDisplay()).
    var activeMenuBarDisplayUUID: String? {
        Bridging.getActiveMenuBarDisplayUUID()
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
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

    // MARK: - Loading

    /// Default baseline for NSStatusItemSpacing and NSStatusItemSelectionPadding,
    /// kept in sync with MenuBarItemSpacingManager.Key.defaultValue. Used to
    /// translate on-disk system spacing into Thaw's relative offset model.
    private static let systemSpacingDefault = 16

    /// Loads saved configurations from Defaults. On a truly first launch
    /// (no persisted per-display configurations) with externally configured
    /// system spacing, adopts the on-disk value as the seed offset for each
    /// connected display so Thaw does not overwrite a user's manual
    /// defaults write NSStatusItemSpacing and trigger a startup relaunch
    /// wave. See issue #602.
    private func loadInitialState() {
        let persistedData = Defaults.data(forKey: .displayIceBarConfigurations)
        if let data = persistedData {
            do {
                configurations = try decoder.decode([String: DisplayIceBarConfiguration].self, from: data)
                diagLog.info("Loaded per-display configurations for \(configurations.count) display(s)")
            } catch {
                diagLog.error("Failed to decode per-display configurations: \(error)")
            }
        }
        // Gate seeding on absence of the persisted key rather than an empty
        // in-memory dictionary so a user-initiated reset (which persists an
        // empty dict) is not silently re-seeded from on-disk system spacing.
        if persistedData == nil {
            seedConfigurationsFromSystemSpacing()
        }
        if let data = Defaults.data(forKey: .globalDisplayConfiguration) {
            do {
                globalConfiguration = try decoder.decode(DisplayIceBarConfiguration.self, from: data)
                diagLog.info("Loaded global display configuration template")
            } catch {
                diagLog.error("Failed to decode global display configuration: \(error)")
            }
        }
        if let data = Defaults.data(forKey: .knownDisplays) {
            do {
                let decoded = try decoder.decode([String: KnownDisplay].self, from: data)
                // Drop entries whose name is empty/whitespace — they can be
                // captured transiently (mirrored slave, GPU sleep) and would
                // otherwise show up as anonymous rows in the Displays pane.
                knownDisplays = decoded.filter {
                    !$0.value.name.trimmingCharacters(in: .whitespaces).isEmpty
                }
                let dropped = decoded.count - knownDisplays.count
                if dropped > 0 {
                    diagLog.info("Loaded known display cache for \(knownDisplays.count) display(s); dropped \(dropped) empty-name entr(ies)")
                } else {
                    diagLog.info("Loaded known display cache for \(knownDisplays.count) display(s)")
                }
            } catch {
                diagLog.error("Failed to decode known display cache: \(error)")
            }
        }
    }

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
    private func seedConfigurationsFromSystemSpacing() {
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
            if seeded[uuid] != nil { continue }
            seeded[uuid] = DisplayIceBarConfiguration
                .defaultConfiguration
                .withItemSpacingOffset(offset)
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

    // MARK: - Persistence

    /// Configures Combine sinks to persist configurations on change.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $configurations
            .dropFirst() // Skip the initial emission during setup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configs in
                guard let self else { return }
                do {
                    let data = try encoder.encode(configs)
                    Defaults.set(data, forKey: .displayIceBarConfigurations)
                } catch {
                    diagLog.error("Failed to encode per-display configurations: \(error)")
                }
            }
            .store(in: &c)

        $knownDisplays
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cache in
                guard let self else { return }
                do {
                    let data = try encoder.encode(cache)
                    Defaults.set(data, forKey: .knownDisplays)
                } catch {
                    diagLog.error("Failed to encode known display cache: \(error)")
                }
            }
            .store(in: &c)

        $globalConfiguration
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                guard let self else { return }
                do {
                    let data = try encoder.encode(config)
                    Defaults.set(data, forKey: .globalDisplayConfiguration)
                } catch {
                    diagLog.error("Failed to encode global display configuration: \(error)")
                }
            }
            .store(in: &c)

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
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
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
            .store(in: &c)

        // Whenever per-display configurations change (user edit, profile
        // load), re-derive what the active display's spacing should be and
        // apply it. The no-op guard inside applyOffset() makes this free
        // when on-disk already matches.
        $configurations
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyActiveDisplaySpacing(reason: "configurationsChanged")
            }
            .store(in: &c)

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

    /// Returns true when a didChangeScreenParametersNotification fire should
    /// be ignored because the active menu bar display has not changed
    /// identity since the last spacing apply. A resolution change, lid
    /// open/close, GPU/sleep transition, or other display-parameter event
    /// that leaves the active display UUID the same is not a reason to
    /// re-apply spacing (and risk a relaunch wave when on-disk values drift).
    ///
    /// Pure on its inputs, separated from the sink so it can be unit tested
    /// without spinning up AppState or driving real screen events.
    static func shouldSkipSpacingApply(
        currentActiveDisplayUUID currentUUID: String?,
        lastAppliedActiveDisplayUUID lastUUID: String?
    ) -> Bool {
        currentUUID == lastUUID
    }

    /// Reads the active display's spacing offset, syncs it into
    /// spacingManager.offset, and triggers applyOffset. The no-op guard
    /// inside applyOffset skips when on-disk values already match, so this
    /// is safe to call on every configurations change. On a real relaunch
    /// wave, kicks off a settling period so a subsequent applyProfileLayout
    /// (e.g. from a profile switch) waits for items to re-attach before
    /// moving them.
    private func applyActiveDisplaySpacing(reason: String) {
        guard let appState else { return }
        lastAppliedActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        let desired = Int(configurationForActiveDisplay().itemSpacingOffset.rounded())
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
                diagLog.error("applyActiveDisplaySpacing(\(reason)) failed: \(error)")
            }
        }
    }

    /// Handles per-display settings changed externally via Settings URI scheme.
    private func handleExternalPerDisplaySettingsChange(_ notification: Notification) {
        guard let key = notification.userInfo?["key"] as? String,
              let scopeRaw = notification.userInfo?["scope"] as? String
        else {
            return
        }

        // Parse scope - it might be a simple scope or "specific:UUID"
        let (scope, specificUUID) = parseScope(from: scopeRaw)

        // Validate specific UUID if provided (defense-in-depth)
        if let uuid = specificUUID {
            let connectedUUIDs = NSScreen.screens.compactMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
            let hasConfig = configurations[uuid] != nil
            guard connectedUUIDs.contains(uuid) || hasConfig else {
                diagLog.warning("DisplaySettingsManager: Ignoring change for unknown display UUID '\(uuid)'")
                return
            }
        }

        diagLog.debug("DisplaySettingsManager: Received external change for \(key) with scope \(scope)\(specificUUID.map { " (UUID: \($0))" } ?? "")")

        switch key {
        case "useIceBar":
            if notification.userInfo?["toggle"] as? Bool == true {
                // Toggle operation
                if let uuid = specificUUID {
                    toggleUseIceBar(forDisplayUUID: uuid)
                } else {
                    toggleIceBarForActiveDisplay()
                }
            } else if let value = notification.userInfo?["value"] as? Bool {
                // Set operation
                if let uuid = specificUUID {
                    setUseIceBar(value, forDisplayUUID: uuid)
                } else {
                    setUseIceBar(value, forActiveDisplay: true)
                }
            }

        case "iceBarLocation":
            if let rawValueString = notification.userInfo?["stringValue"] as? String,
               let rawValue = Int(rawValueString),
               let location = IceBarLocation(rawValue: rawValue)
            {
                if let uuid = specificUUID {
                    setIceBarLocation(location, forDisplayUUID: uuid)
                } else {
                    setIceBarLocation(location, scope: scope)
                }
            }

        case "alwaysShowHiddenItems":
            if notification.userInfo?["toggle"] as? Bool == true {
                if let uuid = specificUUID {
                    toggleAlwaysShowHiddenItems(forDisplayUUID: uuid)
                } else {
                    toggleAlwaysShowHiddenItems(scope: scope)
                }
            } else if let value = notification.userInfo?["value"] as? Bool {
                if let uuid = specificUUID {
                    setAlwaysShowHiddenItems(value, forDisplayUUID: uuid)
                } else {
                    setAlwaysShowHiddenItems(value, scope: scope)
                }
            }

        case "iceBarLayout":
            if let rawValueString = notification.userInfo?["stringValue"] as? String,
               let layout = IceBarLayout.fromString(rawValueString)
            {
                if let uuid = specificUUID {
                    setIceBarLayout(layout, forDisplayUUID: uuid)
                } else {
                    setIceBarLayout(layout, scope: scope)
                }
            }

        case "gridColumns":
            if let rawValueString = notification.userInfo?["stringValue"] as? String,
               let value = Int(rawValueString)
            {
                let clamped = Swift.max(2, Swift.min(value, 10))
                if let uuid = specificUUID {
                    setGridColumns(clamped, forDisplayUUID: uuid)
                } else {
                    setGridColumns(clamped, scope: scope)
                }
            }

        default:
            break
        }
    }

    /// Parses scope string into scope enum and optional specific UUID.
    /// Format: "active", "allEnabled", "allNonIceBar", or "specific:UUID"
    private func parseScope(from scopeRaw: String) -> (SettingsURIHandler.PerDisplayScope, String?) {
        if scopeRaw.hasPrefix("specific:") {
            let uuid = String(scopeRaw.dropFirst("specific:".count))
            return (.activeDisplay, uuid) // Use activeDisplay as placeholder, UUID determines actual target
        }
        switch scopeRaw {
        case "active": return (.activeDisplay, nil)
        case "allEnabled": return (.allEnabledDisplays, nil)
        case "allNonIceBar": return (.allNonIceBarDisplays, nil)
        default: return (.activeDisplay, nil)
        }
    }

    /// Sets useIceBar for the active display.
    private func setUseIceBar(_ value: Bool, forActiveDisplay: Bool) {
        if forActiveDisplay {
            guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
                diagLog.warning("Cannot set useIceBar — no active menu bar display UUID")
                return
            }
            updateConfiguration(forDisplayUUID: uuid) { config in
                config.withUseIceBar(value)
            }
        }
    }

    /// Sets useIceBar for a specific display UUID.
    private func setUseIceBar(_ value: Bool, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseIceBar(value)
        }
    }

    /// Toggles useIceBar for a specific display UUID.
    private func toggleUseIceBar(forDisplayUUID uuid: String) {
        let current = configurations[uuid] ?? .defaultConfiguration
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseIceBar(!current.useIceBar)
        }
    }

    /// Sets iceBarLocation for displays based on scope.
    private func setIceBarLocation(_ location: IceBarLocation, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            // Update all displays that have IceBar enabled
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configurations[uuid] ?? .defaultConfiguration
                if config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withIceBarLocation(location) }
                }
            }
        } else {
            diagLog.debug("setIceBarLocation not implemented for scope \(scope)")
        }
    }

    /// Sets iceBarLocation for a specific display UUID.
    private func setIceBarLocation(_ location: IceBarLocation, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withIceBarLocation(location)
        }
    }

    /// Sets iceBarLayout for displays based on scope.
    private func setIceBarLayout(_ layout: IceBarLayout, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configurations[uuid] ?? .defaultConfiguration
                if config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withIceBarLayout(layout) }
                }
            }
        } else {
            diagLog.debug("setIceBarLayout not implemented for scope \(scope)")
        }
    }

    /// Sets iceBarLayout for a specific display UUID.
    private func setIceBarLayout(_ layout: IceBarLayout, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withIceBarLayout(layout)
        }
    }

    /// Sets gridColumns for displays based on scope.
    private func setGridColumns(_ columns: Int, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configurations[uuid] ?? .defaultConfiguration
                if config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withGridColumns(columns) }
                }
            }
        } else {
            diagLog.debug("setGridColumns not implemented for scope \(scope)")
        }
    }

    /// Sets gridColumns for a specific display UUID.
    private func setGridColumns(_ columns: Int, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withGridColumns(columns)
        }
    }

    /// Sets alwaysShowHiddenItems for displays based on scope.
    private func setAlwaysShowHiddenItems(_ value: Bool, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allNonIceBarDisplays {
            // Update all displays that do NOT have IceBar enabled
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configurations[uuid] ?? .defaultConfiguration
                if !config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withAlwaysShowHiddenItems(value) }
                }
            }
        } else {
            diagLog.debug("setAlwaysShowHiddenItems not implemented for scope \(scope)")
        }
    }

    /// Toggles alwaysShowHiddenItems for displays based on scope.
    private func toggleAlwaysShowHiddenItems(scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allNonIceBarDisplays {
            // Toggle on all displays that do NOT have IceBar enabled
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configurations[uuid] ?? .defaultConfiguration
                if !config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withAlwaysShowHiddenItems(!$0.alwaysShowHiddenItems) }
                }
            }
        } else {
            diagLog.debug("toggleAlwaysShowHiddenItems not implemented for scope \(scope)")
        }
    }

    /// Sets alwaysShowHiddenItems for a specific display UUID.
    private func setAlwaysShowHiddenItems(_ value: Bool, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withAlwaysShowHiddenItems(value)
        }
    }

    /// Toggles alwaysShowHiddenItems for a specific display UUID.
    private func toggleAlwaysShowHiddenItems(forDisplayUUID uuid: String) {
        let current = configurations[uuid] ?? .defaultConfiguration
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withAlwaysShowHiddenItems(!current.alwaysShowHiddenItems)
        }
    }

    // MARK: - Lookup

    /// Returns the configuration for a given display ID.
    func configuration(for displayID: CGDirectDisplayID) -> DisplayIceBarConfiguration {
        guard let uuid = Bridging.getDisplayUUIDString(for: displayID) else {
            return .defaultConfiguration
        }
        return configurations[uuid] ?? .defaultConfiguration
    }

    /// Returns the configuration for the display with the active menu bar.
    func configurationForActiveDisplay() -> DisplayIceBarConfiguration {
        guard let displayID = Bridging.getActiveMenuBarDisplayID() else {
            return .defaultConfiguration
        }
        return configuration(for: displayID)
    }

    /// Whether the Thaw Bar is enabled for the given display.
    func useIceBar(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).useIceBar
    }

    /// The Thaw Bar location for the given display.
    func iceBarLocation(for displayID: CGDirectDisplayID) -> IceBarLocation {
        configuration(for: displayID).iceBarLocation
    }

    /// The Thaw Bar layout for the given display.
    func iceBarLayout(for displayID: CGDirectDisplayID) -> IceBarLayout {
        configuration(for: displayID).iceBarLayout
    }

    /// The grid column count for the given display.
    func gridColumns(for displayID: CGDirectDisplayID) -> Int {
        configuration(for: displayID).gridColumns
    }

    /// Whether hidden items should always be shown for the given display.
    func alwaysShowHiddenItems(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).alwaysShowHiddenItems
    }

    /// Whether any connected display has the Thaw Bar enabled.
    var isIceBarEnabledOnAnyDisplay: Bool {
        configurations.values.contains { $0.useIceBar }
    }

    /// Whether any connected display has "Always show hidden items" enabled.
    var isAlwaysShowEnabledOnAnyDisplay: Bool {
        configurations.values.contains { $0.alwaysShowHiddenItems }
    }

    // MARK: - Mutation (Immutable Pattern)

    /// Updates the configuration for a display by applying a transform,
    /// producing a new dictionary (immutable pattern).
    func updateConfiguration(
        forDisplayUUID uuid: String,
        transform: (DisplayIceBarConfiguration) -> DisplayIceBarConfiguration
    ) {
        let current = configurations[uuid] ?? .defaultConfiguration
        let updated = transform(current)
        var newConfigurations = configurations
        newConfigurations[uuid] = updated
        configurations = newConfigurations
    }

    /// Overwrites the configuration of every known display (connected and
    /// previously-seen but currently disconnected) with the current
    /// globalConfiguration. Returns the list of affected UUIDs. Drives a
    /// single assignment to configurations so the persistence sink and
    /// applyActiveDisplaySpacing each fire once.
    @discardableResult
    func applyGlobalToAllKnownDisplays() -> [String] {
        let targets = allDisplays().map(\.id)
        guard !targets.isEmpty else { return [] }
        var updated = configurations
        for uuid in targets {
            updated[uuid] = globalConfiguration
        }
        if updated != configurations {
            configurations = updated
        }
        return targets
    }

    /// Toggles the Thaw Bar for the display with the active menu bar.
    func toggleIceBarForActiveDisplay() {
        guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
            diagLog.warning("Cannot toggle Thaw Bar — no active menu bar display UUID")
            return
        }
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseIceBar(!config.useIceBar)
        }
    }

    // MARK: - Display Info

    /// Information about a display for use in the settings UI. May represent
    /// either a currently-connected display (in which case displayID is set)
    /// or a previously-connected one whose name was cached in knownDisplays
    /// (in which case displayID is nil).
    struct DisplayInfo: Identifiable {
        let id: String // UUID string
        let displayID: CGDirectDisplayID?
        let name: String
        let hasNotch: Bool
        let isConnected: Bool
    }

    /// Returns info about all currently connected displays.
    func connectedDisplays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            // Skip transient blank-name screens (mirrored slave, GPU
            // sleep transition) so connectedDisplays stays consistent
            // with captureCurrentlyConnectedDisplays, the persistence
            // loader, and allDisplays' disconnected branch.
            let trimmed = screen.localizedName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return DisplayInfo(
                id: uuid,
                displayID: screen.displayID,
                name: trimmed,
                hasNotch: screen.hasNotch,
                isConnected: true
            )
        }
    }

    /// Returns info about all known displays — currently connected ones plus
    /// previously-seen ones whose name/notch state was cached. Connected
    /// displays come first (alphabetical within each group), then
    /// disconnected ones (alphabetical).
    ///
    /// UUIDs that have a saved configuration but no cached name (e.g. a
    /// stray entry from an older build) are deliberately not surfaced:
    /// rendering them with a placeholder name would clutter the pane with
    /// rows the user can't meaningfully identify. Their configuration data
    /// is retained in storage; if such a display reconnects, its name is
    /// captured into knownDisplays and it appears normally on subsequent
    /// renders.
    func allDisplays() -> [DisplayInfo] {
        let connected = connectedDisplays()
        let connectedIDs = Set(connected.map(\.id))

        let disconnected: [DisplayInfo] = knownDisplays
            .filter { !connectedIDs.contains($0.key) }
            .filter { !$0.value.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { uuid, known in
                DisplayInfo(
                    id: uuid,
                    displayID: nil,
                    name: known.name,
                    hasNotch: known.hasNotch,
                    isConnected: false
                )
            }

        return connected.sorted { $0.name < $1.name }
            + disconnected.sorted { $0.name < $1.name }
    }

    /// Returns the configuration for a given display UUID, falling back to
    /// the default when no explicit configuration exists.
    func configuration(forUUID uuid: String) -> DisplayIceBarConfiguration {
        configurations[uuid] ?? .defaultConfiguration
    }
}

/// Cached metadata for a previously-connected display so its settings
/// remain visible and editable in the Displays pane after disconnect.
struct KnownDisplay: Codable, Equatable {
    let name: String
    let hasNotch: Bool
}
