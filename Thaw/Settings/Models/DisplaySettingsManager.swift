//
//  DisplaySettingsManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine

/// Manages per-display Thaw Bar configuration.
///
/// Configurations are keyed by display UUID string (via `Bridging.getDisplayUUIDString(for:)`).
/// Displays without an explicit configuration inherit ``globalConfiguration``.
@MainActor
@Observable
final class DisplaySettingsManager {
    /// The members below would be private, but the live half of this class
    /// lives in DisplaySettingsManager+Live.swift (excluded from coverage;
    /// see sonar-project.properties), and an extension in another file cannot
    /// reach private members. None of them are part of the intended surface.
    @ObservationIgnored
    let diagLog = DiagLog(category: "DisplaySettingsManager")

    /// Per-display configurations, keyed by display UUID string.
    ///
    /// `didSet` both persists the new value and re-derives the active
    /// display's spacing, replacing the previous `$configurations`
    /// Combine pipelines (one for persistence, one — `removeDuplicates()`
    /// — for the spacing reaction). `loadInitialState()` runs from `init`,
    /// so its assignment does not trigger this `didSet`, matching the old
    /// `dropFirst()` skip of the initial emission during setup.
    var configurations: [String: DisplayIceBarConfiguration] = [:] {
        didSet {
            guard oldValue != configurations else { return }
            persistConfigurations()
            applyActiveDisplaySpacing(reason: "configurationsChanged")
        }
    }

    /// The global configuration template applied to all displays by the
    /// Apply-to-All action in the Displays pane and used as the seed for
    /// newly connected displays. Persisted independently from
    /// configurations so the template survives display disconnects, and
    /// captured by every Profile so each profile carries its own global.
    var globalConfiguration: DisplayIceBarConfiguration = .defaultConfiguration {
        didSet {
            guard oldValue != globalConfiguration else { return }
            do {
                let data = try encoder.encode(globalConfiguration)
                Defaults.set(data, forKey: .globalDisplayConfiguration)
            } catch {
                diagLog.error("Failed to encode global display configuration: \(error)")
            }
        }
    }

    /// Cache of previously-seen displays (name + notch state), keyed by
    /// display UUID. Lets the Displays pane show settings rows for
    /// disconnected displays so users can edit them without having to
    /// re-connect the display first.
    var knownDisplays: [String: KnownDisplay] = [:] {
        didSet {
            guard oldValue != knownDisplays else { return }
            do {
                let data = try encoder.encode(knownDisplays)
                Defaults.set(data, forKey: .knownDisplays)
            } catch {
                diagLog.error("Failed to encode known display cache: \(error)")
            }
        }
    }

    /// Whether Thaw asks for confirmation before a spacing change relaunches
    /// menu bar apps. When true, the automatic display-transition path shows
    /// a just-in-time prompt and the Displays pane shows its Apply/global
    /// confirmation alerts. When false, both apply without asking.
    var confirmSpacingRelaunch = Defaults.DefaultValue.confirmSpacingRelaunch {
        didSet {
            guard oldValue != confirmSpacingRelaunch else { return }
            Defaults.set(confirmSpacingRelaunch, forKey: .confirmSpacingRelaunch)
        }
    }

    /// When confirmSpacingRelaunch is off and a profile is active, selects
    /// whether an applied spacing change is saved to the active profile only
    /// or to every profile.
    var unconfirmedSpacingProfileScope = Defaults.DefaultValue.unconfirmedSpacingProfileScope {
        didSet {
            guard oldValue != unconfirmedSpacingProfileScope else { return }
            Defaults.set(unconfirmedSpacingProfileScope.rawValue, forKey: .unconfirmedSpacingProfileScope)
        }
    }

    /// Storage for internal observers.
    @ObservationIgnored
    var cancellables = Set<AnyCancellable>()

    /// Task backing the swift-async-algorithms screen-parameters debounce (see
    /// ``configureObservers()``). Held so it is cancelled in `deinit`,
    /// matching the lifetime of the Combine cancellables above; its notification
    /// observer is owned inside the task and removed when it ends.
    @ObservationIgnored
    var screenParametersTask: Task<Void, Never>?

    /// JSON encoder for persistence.
    @ObservationIgnored
    let encoder = JSONEncoder()

    /// JSON decoder for persistence.
    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// Reference to AppState for driving spacingManager and itemManager from
    /// active-display configuration changes. Held weakly to avoid retain cycles.
    @ObservationIgnored
    weak var appState: AppState?

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

    /// Loads persisted state immediately at construction time, before any
    /// `didSet` observer is armed. Swift's `didSet` does not fire for
    /// assignments made from within the declaring class's own `init`, so
    /// running `loadInitialState()` here — rather than from
    /// ``performSetup(with:)`` — reproduces the old `$configurations`
    /// `.dropFirst()` Combine pipelines' skip of the initial emission during
    /// setup, without persisting-back or re-deriving spacing from data that
    /// was just loaded from the same source.
    init() {
        loadInitialState()
    }

    // MARK: - Loading

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
        // Must precede seeding: seedConfigurationsFromSystemSpacing() builds
        // its entries from globalConfiguration, so restoring the template
        // afterwards would seed every display from the hardcoded default
        // instead of the user's own.
        if let data = Defaults.data(forKey: .globalDisplayConfiguration) {
            do {
                globalConfiguration = try decoder.decode(DisplayIceBarConfiguration.self, from: data)
                diagLog.info("Loaded global display configuration template")
            } catch {
                diagLog.error("Failed to decode global display configuration: \(error)")
            }
        }
        // Gate seeding on absence of the persisted key rather than an empty
        // in-memory dictionary so a user-initiated reset (which persists an
        // empty dict) is not silently re-seeded from on-disk system spacing.
        if persistedData == nil {
            seedConfigurationsFromSystemSpacing()
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
        Defaults.ifPresent(key: .confirmSpacingRelaunch, assign: &confirmSpacingRelaunch)
        if let raw = Defaults.string(forKey: .unconfirmedSpacingProfileScope),
           let scope = SpacingProfileSaveScope(rawValue: raw)
        {
            unconfirmedSpacingProfileScope = scope
        }
    }

    @MainActor
    deinit {
        // Combine cancellables tear down automatically; the async-algorithms
        // screen-parameters task is manually owned, so cancel it here. Ending
        // the task runs its defer, which removes the notification observer.
        screenParametersTask?.cancel()
    }

    // MARK: - Persistence

    /// Encodes and persists `configurations`, matching the previous
    /// `$configurations.dropFirst()` persistence sink. Called from
    /// `configurations`'s `didSet` and from `seedConfigurationsFromSystemSpacing()`.
    private func persistConfigurations() {
        do {
            let data = try encoder.encode(configurations)
            Defaults.set(data, forKey: .displayIceBarConfigurations)
        } catch {
            diagLog.error("Failed to encode per-display configurations: \(error)")
        }
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

    /// Handles per-display settings changed externally via Settings URI scheme.
    ///
    /// Internal rather than private so tests can drive it with a hand-built
    /// `Notification` instead of going through `performSetup(with:)`, which
    /// needs a live `AppState` and installs a one-second debounced observer.
    /// The `specific:UUID` scope reaches every setter below without touching
    /// `NSScreen`, provided `configurations` already holds the UUID.
    func handleExternalPerDisplaySettingsChange(_ notification: Notification) {
        guard let key = notification.userInfo?["key"] as? String,
              let scopeRaw = notification.userInfo?["scope"] as? String
        else {
            return
        }

        // Parse scope - it might be a simple scope or "specific:UUID"
        let (scope, specificUUID) = Self.parseScope(from: scopeRaw)

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

        case "useThawBarForAlwaysHidden":
            if notification.userInfo?["toggle"] as? Bool == true {
                if let uuid = specificUUID {
                    toggleUseThawBarForAlwaysHidden(forDisplayUUID: uuid)
                } else {
                    toggleUseThawBarForAlwaysHidden(scope: scope)
                }
            } else if let value = notification.userInfo?["value"] as? Bool {
                if let uuid = specificUUID {
                    setUseThawBarForAlwaysHidden(value, forDisplayUUID: uuid)
                } else {
                    setUseThawBarForAlwaysHidden(value, scope: scope)
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
    ///
    /// Static and internal because it depends on nothing but its argument,
    /// which makes the parse rules directly testable.
    static func parseScope(from scopeRaw: String) -> (SettingsURIHandler.PerDisplayScope, String?) {
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
        let current = configuration(forUUID: uuid)
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseIceBar(!current.useIceBar)
        }
    }

    /// Sets useThawBarForAlwaysHidden for displays based on scope.
    private func setUseThawBarForAlwaysHidden(_ value: Bool, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allNonIceBarDisplays {
            // Update all displays that do NOT have IceBar enabled; on the rest
            // the setting is redundant, since every section already opens in
            // the Thaw Bar there.
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if !config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withUseThawBarForAlwaysHidden(value) }
                }
            }
        } else {
            diagLog.debug("setUseThawBarForAlwaysHidden not implemented for scope \(scope)")
        }
    }

    /// Toggles useThawBarForAlwaysHidden for displays based on scope.
    private func toggleUseThawBarForAlwaysHidden(scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allNonIceBarDisplays {
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if !config.useIceBar {
                    updateConfiguration(forDisplayUUID: uuid) {
                        $0.withUseThawBarForAlwaysHidden(!$0.useThawBarForAlwaysHidden)
                    }
                }
            }
        } else {
            diagLog.debug("toggleUseThawBarForAlwaysHidden not implemented for scope \(scope)")
        }
    }

    /// Sets useThawBarForAlwaysHidden for a specific display UUID.
    private func setUseThawBarForAlwaysHidden(_ value: Bool, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseThawBarForAlwaysHidden(value)
        }
    }

    /// Toggles useThawBarForAlwaysHidden for a specific display UUID.
    private func toggleUseThawBarForAlwaysHidden(forDisplayUUID uuid: String) {
        let current = configuration(forUUID: uuid)
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseThawBarForAlwaysHidden(!current.useThawBarForAlwaysHidden)
        }
    }

    /// Sets iceBarLocation for displays based on scope.
    private func setIceBarLocation(_ location: IceBarLocation, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            // Update all displays that have IceBar enabled
            for screen in NSScreen.screens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
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
                let config = configuration(forUUID: uuid)
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
                let config = configuration(forUUID: uuid)
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
                let config = configuration(forUUID: uuid)
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
                let config = configuration(forUUID: uuid)
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
        let current = configuration(forUUID: uuid)
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withAlwaysShowHiddenItems(!current.alwaysShowHiddenItems)
        }
    }

    // MARK: - Lookup

    /// Returns the configuration for a given display ID.
    ///
    /// Uses the global template if the display has no override or its UUID
    /// cannot be resolved, preventing transient display changes from resetting
    /// spacing to the system default.
    func configuration(for displayID: CGDirectDisplayID) -> DisplayIceBarConfiguration {
        guard let uuid = Bridging.getDisplayUUIDString(for: displayID) else {
            return globalConfiguration
        }
        return configurations[uuid] ?? globalConfiguration
    }

    /// Returns the configuration for the display with the active menu bar.
    func configurationForActiveDisplay() -> DisplayIceBarConfiguration {
        guard let displayID = Bridging.getActiveMenuBarDisplayID() else {
            return globalConfiguration
        }
        return configuration(for: displayID)
    }

    /// The spacing offset the active display's configuration calls for.
    ///
    /// The single source of truth for what `MenuBarItemSpacingManager.offset`
    /// should hold. Everything that pushes into that property reads it from
    /// here, so a launch seed, a display transition, and a profile apply can't
    /// disagree about which value is current.
    var activeDisplaySpacingOffset: Int {
        Int(configurationForActiveDisplay().itemSpacingOffset.rounded())
    }

    /// Whether the Thaw Bar is enabled for the given display.
    func useIceBar(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).useIceBar
    }

    /// Whether the always-hidden section alone opens in the Thaw Bar on the
    /// given display.
    func useThawBarForAlwaysHidden(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).useThawBarForAlwaysHidden
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
        let current = configuration(forUUID: uuid)
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

    /// Returns the configuration for a display UUID, inheriting the global
    /// template when no override exists.
    func configuration(forUUID uuid: String) -> DisplayIceBarConfiguration {
        configurations[uuid] ?? globalConfiguration
    }

    /// The display's own stored configuration, or nil when it has none and
    /// resolves to the global template. The Displays pane uses this to mark
    /// displays whose custom settings shadow the global toggles (#1045).
    func configurationOverride(forUUID uuid: String) -> DisplayIceBarConfiguration? {
        configurations[uuid]
    }
}

/// Cached metadata for a previously-connected display so its settings
/// remain visible and editable in the Displays pane after disconnect.
struct KnownDisplay: Codable, Equatable {
    let name: String
    let hasNotch: Bool
}

/// Destination for an applied spacing change when the relaunch confirmation
/// is disabled and a profile is active.
enum SpacingProfileSaveScope: String, CaseIterable, Codable {
    case activeProfile
    case allProfiles
}
