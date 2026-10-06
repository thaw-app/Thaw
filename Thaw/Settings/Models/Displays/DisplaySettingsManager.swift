//
//  DisplaySettingsManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

/// Manages per-display Thaw Bar configuration.
///
/// Configurations are keyed by display UUID string (via Bridging.getDisplayUUIDString(for:)).
/// When a display has no explicit configuration, the global display template
/// is returned so profiles remain portable across machines and display UUIDs.
@MainActor
@Observable
final class DisplaySettingsManager {
    private(set) var isReapplyingSpacing = false
    private(set) var lastSpacingApplyFailure: String?
    @ObservationIgnored
    private let diagLog = DiagLog(category: "DisplaySettingsManager")

    /// Per-display configurations, keyed by display UUID string.
    ///
    /// didSet persists the new value and re-derives the active display's
    /// spacing. It also fires for assignments in loadInitialState(): the
    /// persist is a harmless round-trip and the spacing apply no-ops while
    /// appState is nil.
    var configurations: [String: DisplayThawBarConfiguration] = [:] {
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
    var globalConfiguration: DisplayThawBarConfiguration = .defaultConfiguration {
        didSet {
            guard oldValue != globalConfiguration else { return }
            do {
                let data = try encoder.encode(globalConfiguration)
                Defaults.set(data, forKey: .globalDisplayConfiguration)
                lastPersistenceFailure = nil
            } catch {
                diagLog.error("Failed to encode global display configuration: \(error)")
                lastPersistenceFailure = error.localizedDescription
            }
        }
    }

    /// The last display write that did not reach Defaults, or nil when the
    /// stored display settings are current.
    ///
    /// Each of these writes happens in a didSet or a seeding pass, none of
    /// which can throw: without this the pane keeps showing the new value
    /// while nothing is stored, and it is gone at the next launch. The
    /// Displays pane reads this to say so.
    private(set) var lastPersistenceFailure: String?

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
                lastPersistenceFailure = nil
            } catch {
                diagLog.error("Failed to encode known display cache: \(error)")
                lastPersistenceFailure = error.localizedDescription
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

    /// Whether a spacing change relaunches menu bar apps now or is only written for their next start.
    /// Mirrored into MenuBarItemSpacingManager.spacingApplyMode, which enforces it.
    var spacingApplyMode = Defaults.DefaultValue.spacingApplyMode {
        didSet {
            guard oldValue != spacingApplyMode else { return }
            Defaults.set(spacingApplyMode.rawValue, forKey: .spacingApplyMode)
            appState?.spacingManager.spacingApplyMode = spacingApplyMode
        }
    }

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    private let encoder = JSONEncoder()

    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// Reference to AppState for driving spacingManager and itemManager from
    /// active-display configuration changes. Held weakly to avoid retain cycles.
    @ObservationIgnored
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

    /// Loads persisted state at construction. didSet fires for assignments in
    /// loadInitialState() (only direct init assignments are exempt); that is a
    /// harmless round-trip, and applyActiveDisplaySpacing returns early until
    /// performSetup(with:) wires appState. Loading here rather than in
    /// performSetup(with:) keeps setup from persisting that round-trip.
    init() {
        loadInitialState()
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        // Capturing displays below can apply spacing, which must see the saved mode.
        appState.spacingManager.spacingApplyMode = spacingApplyMode
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
        for screen in NSScreen.managedScreens {
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
            // DisplayThawBarConfiguration.defaultConfiguration at read time.
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

    /// Default baseline for NSStatusItemSpacing and NSStatusItemSelectionPadding.
    /// Used to translate on-disk system spacing into Thaw's relative offset model.
    private static let systemSpacingDefault = 16

    /// Loads saved configurations from Defaults. On a first launch (no
    /// persisted per-display configurations) with externally configured system
    /// spacing, seeds each connected display's offset from the on-disk value so
    /// Thaw does not overwrite a manual defaults write of NSStatusItemSpacing
    /// and trigger a startup relaunch wave.
    private func loadInitialState() {
        let persistedData = Defaults.data(forKey: .displayThawBarConfigurations)
        if let data = persistedData {
            do {
                configurations = try decoder.decode([String: DisplayThawBarConfiguration].self, from: data)
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
                globalConfiguration = try decoder.decode(DisplayThawBarConfiguration.self, from: data)
                diagLog.info("Loaded global display configuration template")
            } catch {
                diagLog.error("Failed to decode global display configuration: \(error)")
            }
        }
        if let data = Defaults.data(forKey: .knownDisplays) {
            do {
                let decoded = try decoder.decode([String: KnownDisplay].self, from: data)
                // Drop entries whose name is empty/whitespace, they can be
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
        if let raw = Defaults.string(forKey: .spacingApplyMode),
           let mode = SpacingApplyMode(rawValue: raw)
        {
            spacingApplyMode = mode
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

    /// Adopts an NSStatusItemSpacing the user set outside Thaw by seeding each
    /// display's offset from it. Otherwise the first launch computes 16, finds
    /// another value on disk and relaunches items to overwrite the user's.
    /// The padding key is not read, so padding that differs from spacing gets
    /// one normalising relaunch.
    private func seedConfigurationsFromSystemSpacing() {
        guard let onDisk = Self.currentSystemSpacing(),
              onDisk != Self.systemSpacingDefault
        else {
            return
        }
        let offset = Double(onDisk - Self.systemSpacingDefault)
        var seeded = configurations
        for screen in NSScreen.managedScreens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                continue
            }
            if seeded[uuid] != nil {
                continue
            }
            seeded[uuid] = DisplayThawBarConfiguration
                .defaultConfiguration
                .withItemSpacingOffset(offset)
        }
        guard seeded != configurations else { return }
        configurations = seeded
        do {
            let data = try encoder.encode(seeded)
            Defaults.set(data, forKey: .displayThawBarConfigurations)
            diagLog.info(
                "Seeded itemSpacingOffset=\(offset) from external NSStatusItemSpacing=\(onDisk) for \(seeded.count) display(s)"
            )
            lastPersistenceFailure = nil
        } catch {
            diagLog.error("Failed to persist seeded per-display configurations: \(error)")
            lastPersistenceFailure = error.localizedDescription
        }
    }

    // MARK: - Persistence

    /// Encodes and persists configurations. Called from configurations's
    /// didSet.
    private func persistConfigurations() {
        do {
            let data = try encoder.encode(configurations)
            Defaults.set(data, forKey: .displayThawBarConfigurations)
            lastPersistenceFailure = nil
        } catch {
            diagLog.error("Failed to encode per-display configurations: \(error)")
            lastPersistenceFailure = error.localizedDescription
        }
    }

    /// Configures the manager's non-persistence internal observers: the
    /// Settings-URI notification subscription. Display changes arrive through
    /// handleDisplayTopologyChange(_:). Persistence is not here, it is driven
    /// by didSet on each property (see the property declarations above).
    private func configureObservers() {
        var c = Set<AnyCancellable>()

        // Re-deriving spacing on per-display configuration changes lives in
        // configurations's didSet; applyOffset's no-op guard keeps it free.

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

    /// Logs display connect/disconnect, refreshes the known-display cache and
    /// re-derives the active display's spacing, after the item rescan.
    ///
    /// Screen-parameter events only: DisplayTopology settles a dock, lid,
    /// sleep, KVM or Sidecar flap into one event, and the active bar following
    /// focus between displays is not a reason to start a relaunch wave.
    func handleDisplayTopologyChange(_ event: DisplayTopology.Event) {
        guard event.source == .screenParameters else { return }
        diagLog.info("Screen parameters changed, \(NSScreen.managedScreens.count) screen(s) connected")
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

    /// Whether a screen-parameters change should be ignored because the active
    /// menu bar display is unchanged. A resolution change, lid open/close or
    /// sleep transition that leaves the UUID the same is not a reason to
    /// re-apply spacing and risk a relaunch wave.
    ///
    /// Pure on its inputs so it can be tested without AppState or real events.
    static func shouldSkipSpacingApply(
        currentActiveDisplayUUID currentUUID: String?,
        lastAppliedActiveDisplayUUID lastUUID: String?
    ) -> Bool {
        currentUUID == lastUUID
    }

    /// Reads the active display's spacing offset and applies it.
    /// applyOffset's no-op guard makes this safe on every configurations
    /// change, and a real relaunch wave starts a settling period so a later
    /// applyProfileLayout waits for items to re-attach.
    func reapplySpacing(forDisplayUUID displayID: String) {
        guard !isReapplyingSpacing, displayID == activeMenuBarDisplayUUID else { return }
        let needsConfirmation = Self.needsSpacingRelaunchConfirmation(
            applyMode: spacingApplyMode,
            confirmationsEnabled: confirmSpacingRelaunch
        )
        if needsConfirmation, !presentSpacingRelaunchConfirmation() {
            return
        }
        // The active display can change while the confirmation is on screen.
        guard displayID == activeMenuBarDisplayUUID else { return }
        applyActiveDisplaySpacing(
            reason: "userReapply",
            forceRelaunch: spacingApplyMode == .relaunchApps
        )
    }

    /// Whether to ask before a relaunch wave. Write-only mode relaunches
    /// nothing, so it never asks, whatever the confirmation toggle says.
    static func needsSpacingRelaunchConfirmation(
        applyMode: SpacingApplyMode,
        confirmationsEnabled: Bool
    ) -> Bool {
        applyMode == .relaunchApps && confirmationsEnabled
    }

    private func applyActiveDisplaySpacing(reason: String, forceRelaunch: Bool = false) {
        guard let appState else { return }
        let desired = Int(configurationForActiveDisplay().itemSpacingOffset.rounded())
        // Plugging or unplugging a display is not a spacing edit. Quitting
        // every menu bar app for it, Chrome included, was far worse than a
        // gap that is off until those apps next launch, so a display change
        // only writes the new display's value. Reapply Spacing applies it now.
        let relaunchApps = reason != "screenParametersChanged"
        if !relaunchApps, appState.spacingManager.willRelaunch(forOffset: desired) {
            diagLog.info("Active display changed; saving spacing \(desired) without relaunching menu bar apps")
        }
        lastAppliedActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        appState.spacingManager.offset = desired
        if forceRelaunch {
            isReapplyingSpacing = true
        }
        lastSpacingApplyFailure = nil
        Task { [weak self] in
            guard let self else { return }
            defer {
                if forceRelaunch {
                    isReapplyingSpacing = false
                }
            }
            // Preflight settling so intermediate restore logic is
            // suppressed while the wave runs. Cancelled
            // below if applyOffset turns out to be a no-op.
            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:\(reason):preflight")
            do {
                // Read the captured request, not a later display's offset.
                appState.spacingManager.offset = desired
                let outcome = try await appState.spacingManager.applyOffset(
                    forceRelaunch: forceRelaunch,
                    relaunchApps: relaunchApps
                )
                if !outcome.failedAppNames.isEmpty {
                    lastSpacingApplyFailure = String(localized: "Could not relaunch: \(outcome.failedAppNames.formatted(.list(type: .and)))")
                }
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
                lastSpacingApplyFailure = error.localizedDescription
            }
        }
    }

    /// Presents an app-modal confirmation before a display transition fires the
    /// relaunch wave, returning whether the user approved. Ticking the
    /// suppression box while pressing Apply turns confirmSpacingRelaunch off;
    /// cancelling never changes it.
    private func presentSpacingRelaunchConfirmation() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Apply menu bar spacing change?")
        alert.informativeText = String(localized: "Applying spacing relaunches apps with menu bar items so they can read the saved value. Save your work first; unsaved input or progress may be lost.")
        let applyButton = alert.addButton(withTitle: String(localized: "Apply"))
        let cancelButton = alert.addButton(withTitle: String(localized: "Cancel"))
        // The alert arrives unasked, on a display change, and Apply can cost
        // unsaved work in other apps, so Return must not be the one to press it.
        applyButton.hasDestructiveAction = true
        applyButton.keyEquivalent = ""
        cancelButton.keyEquivalent = "\r"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don’t ask again")
        let apply = alert.runModal() == .alertFirstButtonReturn
        if apply, alert.suppressionButton?.state == .on {
            confirmSpacingRelaunch = false
        }
        return apply
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
            let connectedUUIDs = NSScreen.managedScreens.compactMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
            let hasConfig = configurations[uuid] != nil
            guard connectedUUIDs.contains(uuid) || hasConfig else {
                diagLog.warning("DisplaySettingsManager: Ignoring change for unknown display UUID '\(uuid)'")
                return
            }
        }

        diagLog.debug("DisplaySettingsManager: Received external change for \(key) with scope \(scope)\(specificUUID.map { " (UUID: \($0))" } ?? "")")

        switch key {
        case "useThawBar":
            if notification.userInfo?["toggle"] as? Bool == true {
                // Toggle operation
                if let uuid = specificUUID {
                    toggleUseThawBar(forDisplayUUID: uuid)
                } else {
                    toggleThawBarForActiveDisplay()
                }
            } else if let value = notification.userInfo?["value"] as? Bool {
                // Set operation
                if let uuid = specificUUID {
                    setUseThawBar(value, forDisplayUUID: uuid)
                } else {
                    setUseThawBar(value, forActiveDisplay: true)
                }
            }

        case "thawBarLocation":
            if let rawValueString = notification.userInfo?["stringValue"] as? String,
               let rawValue = Int(rawValueString),
               let location = ThawBarLocation(rawValue: rawValue)
            {
                if let uuid = specificUUID {
                    setThawBarLocation(location, forDisplayUUID: uuid)
                } else {
                    setThawBarLocation(location, scope: scope)
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

        case "thawBarLayout":
            if let rawValueString = notification.userInfo?["stringValue"] as? String,
               let layout = ThawBarLayout.fromString(rawValueString)
            {
                if let uuid = specificUUID {
                    setThawBarLayout(layout, forDisplayUUID: uuid)
                } else {
                    setThawBarLayout(layout, scope: scope)
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
    /// Format: "active", "allEnabled", "allNonThawBar", or "specific:UUID"
    private func parseScope(from scopeRaw: String) -> (SettingsURIHandler.PerDisplayScope, String?) {
        if scopeRaw.hasPrefix("specific:") {
            let uuid = String(scopeRaw.dropFirst("specific:".count))
            return (.activeDisplay, uuid) // Use activeDisplay as placeholder, UUID determines actual target
        }
        switch scopeRaw {
        case "active": return (.activeDisplay, nil)
        case "allEnabled": return (.allEnabledDisplays, nil)
        // "allNonIceBar" is the Ice-era spelling, kept for script compatibility.
        case "allNonThawBar", "allNonIceBar": return (.allNonThawBarDisplays, nil)
        default: return (.activeDisplay, nil)
        }
    }

    private func setUseThawBar(_ value: Bool, forActiveDisplay: Bool) {
        if forActiveDisplay {
            guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
                diagLog.warning("Cannot set useThawBar, no active menu bar display UUID")
                return
            }
            updateConfiguration(forDisplayUUID: uuid) { config in
                config.withUseThawBar(value)
            }
        }
    }

    private func setUseThawBar(_ value: Bool, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseThawBar(value)
        }
    }

    private func toggleUseThawBar(forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseThawBar(!config.useThawBar)
        }
    }

    private func setThawBarLocation(_ location: ThawBarLocation, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            for screen in NSScreen.managedScreens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if config.useThawBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarLocation(location) }
                }
            }
        } else {
            diagLog.debug("setThawBarLocation not implemented for scope \(scope)")
        }
    }

    private func setThawBarLocation(_ location: ThawBarLocation, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withThawBarLocation(location)
        }
    }

    private func setThawBarLayout(_ layout: ThawBarLayout, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            for screen in NSScreen.managedScreens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if config.useThawBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarLayout(layout) }
                }
            }
        } else {
            diagLog.debug("setThawBarLayout not implemented for scope \(scope)")
        }
    }

    private func setThawBarLayout(_ layout: ThawBarLayout, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withThawBarLayout(layout)
        }
    }

    private func setGridColumns(_ columns: Int, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allEnabledDisplays {
            for screen in NSScreen.managedScreens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if config.useThawBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withGridColumns(columns) }
                }
            }
        } else {
            diagLog.debug("setGridColumns not implemented for scope \(scope)")
        }
    }

    private func setGridColumns(_ columns: Int, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withGridColumns(columns)
        }
    }

    private func setAlwaysShowHiddenItems(_ value: Bool, scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allNonThawBarDisplays {
            for screen in NSScreen.managedScreens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if !config.useThawBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withAlwaysShowHiddenItems(value) }
                }
            }
        } else {
            diagLog.debug("setAlwaysShowHiddenItems not implemented for scope \(scope)")
        }
    }

    private func toggleAlwaysShowHiddenItems(scope: SettingsURIHandler.PerDisplayScope) {
        if scope == .allNonThawBarDisplays {
            for screen in NSScreen.managedScreens {
                guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
                let config = configuration(forUUID: uuid)
                if !config.useThawBar {
                    updateConfiguration(forDisplayUUID: uuid) { $0.withAlwaysShowHiddenItems(!$0.alwaysShowHiddenItems) }
                }
            }
        } else {
            diagLog.debug("toggleAlwaysShowHiddenItems not implemented for scope \(scope)")
        }
    }

    private func setAlwaysShowHiddenItems(_ value: Bool, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withAlwaysShowHiddenItems(value)
        }
    }

    private func toggleAlwaysShowHiddenItems(forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withAlwaysShowHiddenItems(!config.alwaysShowHiddenItems)
        }
    }

    // MARK: - Lookup

    /// Returns the configuration for a given display ID.
    func configuration(for displayID: CGDirectDisplayID) -> DisplayThawBarConfiguration {
        Self.resolvedConfiguration(
            displayUUID: Bridging.getDisplayUUIDString(for: displayID),
            configurations: configurations,
            globalConfiguration: globalConfiguration
        )
    }

    /// Returns the configuration for the display with the active menu bar.
    func configurationForActiveDisplay() -> DisplayThawBarConfiguration {
        guard let displayID = Bridging.getActiveMenuBarDisplayID() else {
            return globalConfiguration
        }
        return configuration(for: displayID)
    }

    static func resolvedConfiguration(
        displayUUID: String?,
        configurations: [String: DisplayThawBarConfiguration],
        globalConfiguration: DisplayThawBarConfiguration
    ) -> DisplayThawBarConfiguration {
        guard let displayUUID else { return globalConfiguration }
        return configurations[displayUUID] ?? globalConfiguration
    }

    func useThawBar(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).useThawBar
    }

    func thawBarLocation(for displayID: CGDirectDisplayID) -> ThawBarLocation {
        configuration(for: displayID).thawBarLocation
    }

    /// Whether hidden items should always be shown for the given display.
    func alwaysShowHiddenItems(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).alwaysShowHiddenItems
    }

    /// Whether any connected display has "Always show hidden items" enabled.
    var isAlwaysShowEnabledOnAnyDisplay: Bool {
        connectedDisplays().contains { configuration(forUUID: $0.id).alwaysShowHiddenItems }
    }

    // MARK: - Mutation (Immutable Pattern)

    /// Updates the configuration for a display by applying a transform,
    /// producing a new dictionary (immutable pattern).
    func updateConfiguration(
        forDisplayUUID uuid: String,
        transform: (DisplayThawBarConfiguration) -> DisplayThawBarConfiguration
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
        let targets = displays.map(\.id)
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
    func toggleThawBarForActiveDisplay() {
        guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
            diagLog.warning("Cannot toggle Thaw Bar, no active menu bar display UUID")
            return
        }
        updateConfiguration(forDisplayUUID: uuid) { config in
            config.withUseThawBar(!config.useThawBar)
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
        NSScreen.managedScreens.compactMap { screen in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            // Skip transient blank-name screens (mirrored slave, GPU
            // sleep transition) so connectedDisplays stays consistent
            // with captureCurrentlyConnectedDisplays, the persistence
            // loader, and displays' disconnected branch.
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

    /// Returns info about all known displays, currently connected ones plus
    /// previously-seen ones whose name/notch state was cached. Connected
    /// displays come first (alphabetical within each group), then
    /// disconnected ones (alphabetical).
    ///
    /// UUIDs with a saved configuration but no cached name are not surfaced:
    /// a placeholder row is one the user can't identify. The data is kept, and
    /// the display appears normally once it reconnects and its name is captured.
    ///
    /// - Complexity: O(n) in the number of connected screens plus known
    ///   displays; walks NSScreen.managedScreens and the stored profile
    ///   data on every access.
    var displays: [DisplayInfo] {
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
    /// the global profile template when no explicit configuration exists.
    func configuration(forUUID uuid: String) -> DisplayThawBarConfiguration {
        Self.resolvedConfiguration(
            displayUUID: uuid,
            configurations: configurations,
            globalConfiguration: globalConfiguration
        )
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
