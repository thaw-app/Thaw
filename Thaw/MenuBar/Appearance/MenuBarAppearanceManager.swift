//
//  MenuBarAppearanceManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine
import Observation

/// A manager for the appearance of the menu bar.
@MainActor
@Observable
final class MenuBarAppearanceManager {
    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarAppearanceManager")

    /// The current menu bar appearance configuration.
    ///
    /// `didSet` persists every change; panel reconfiguration is throttled
    /// separately by `configurationPanelObservationTask`.
    var configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2 {
        didSet {
            do {
                let data = try encoder.encode(configuration)
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            } catch {
                diagLog.error("Error encoding menu bar appearance configuration: \(error)")
            }
            updateEffectiveConfiguration()
        }
    }

    /// Appearance overrides applied while a specific Space is active, keyed
    /// by the Space's persistent key — the reboot-stable identifier — with a
    /// session-scoped `CGSSpaceID` fallback for Spaces that expose none.
    private(set) var spaceOverrides: [String: MenuBarAppearanceConfigurationV2] = [:]

    /// The most recently observed active Space.
    private(set) var activeSpaceID = SpaceInfo.activeSpace().spaceID

    /// The configuration the overlay panels render: the active Space's
    /// override when one exists, otherwise the shared `configuration`.
    private(set) var effectiveConfiguration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2

    /// The currently previewed partial configuration.
    var previewConfiguration: MenuBarAppearancePartialConfiguration? {
        didSet {
            if let previewConfiguration {
                let needsPanels = previewConfiguration.hasShadow
                    || previewConfiguration.borderOnMenuBar
                    || effectiveConfiguration.shapeKind != .noShape
                    || previewConfiguration.tintKind != .noTint
                    || previewConfiguration.backgroundKind != .none
                if overlayPanels.isEmpty, needsPanels {
                    configureOverlayPanels(with: effectiveConfiguration, force: true)
                }
            } else {
                if !needsOverlayPanels(for: effectiveConfiguration) {
                    closeAllOverlayPanels()
                }
            }
        }
    }

    /// Whether the system is currently drawing an opaque menu bar because
    /// Accessibility's Reduce Transparency is enabled.
    ///
    /// The overlay sits behind the menu bar, so an opaque material hides it
    /// entirely (see ``MenuBarOverlayPanel/updateWindowLevel()``); the editor
    /// warns the user instead.
    private(set) var isReduceTransparencyEnabled =
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    /// The shared app state.
    @ObservationIgnored
    private weak var appState: AppState?

    /// Encoder for UserDefaults values.
    @ObservationIgnored
    private let encoder = JSONEncoder()

    /// Decoder for UserDefaults values.
    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Task observing `configuration`, throttled to 0.1 s (latest value wins),
    /// that creates or tears down the overlay panels.
    ///
    /// `_throttle(for:latest:)` is not a typo: swift-async-algorithms 1.1.5
    /// only exposes the throttle under the underscored name.
    private var configurationPanelObservationTask: Task<Void, Never>?

    /// The currently managed menu bar overlay panels.
    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// The shared Mission Control detector used by all overlay panels.
    ///
    /// One for the whole app, not per panel: the probe is synchronous IPC.
    let missionControlDetector = MissionControlDetector()

    /// The amount to inset the menu bar if called for by the configuration.
    let menuBarInsetAmount: CGFloat = 3.5

    @MainActor
    deinit {
        configurationPanelObservationTask?.cancel()
    }

    /// Performs initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the initial values for the configuration.
    private func loadInitialState() {
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            diagLog.error("Error decoding menu bar appearance configuration: \(error)")
        }
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceSpaceOverrides) {
                spaceOverrides = try decoder.decode(
                    [String: MenuBarAppearanceConfigurationV2].self,
                    from: data
                )
            }
        } catch {
            diagLog.error("Error decoding per-Space appearance overrides: \(error)")
        }
        updateEffectiveConfiguration()
    }

    // MARK: Per-Space Overrides

    /// Resolves the configuration for a Space. Pure so it is unit-testable.
    static nonisolated func effectiveConfiguration(
        base: MenuBarAppearanceConfigurationV2,
        overrides: [String: MenuBarAppearanceConfigurationV2],
        activeSpaceKey: String
    ) -> MenuBarAppearanceConfigurationV2 {
        overrides[activeSpaceKey] ?? base
    }

    /// The key the active Space's override is stored under: the persistent
    /// key, since space IDs are reassigned after reboot, else the session space ID.
    private func activeSpaceOverrideKey() -> String {
        SpaceInfo(spaceID: activeSpaceID).persistentKey ?? String(activeSpaceID)
    }

    /// Whether the active Space renders a saved override.
    var activeSpaceHasOverride: Bool {
        spaceOverrides[activeSpaceOverrideKey()] != nil
    }

    /// The configuration the appearance editor reads and writes.
    ///
    /// The active Space's override when it has one, since the panels render
    /// ``effectiveConfiguration``; otherwise the shared ``configuration``.
    var editedConfiguration: MenuBarAppearanceConfigurationV2 {
        get {
            effectiveConfiguration
        }
        set {
            guard activeSpaceHasOverride else {
                configuration = newValue
                return
            }
            spaceOverrides[activeSpaceOverrideKey()] = newValue
            persistSpaceOverrides()
            updateEffectiveConfiguration()
        }
    }

    /// Saves the shared configuration as the active Space's override.
    func saveOverrideForActiveSpace() {
        let key = activeSpaceOverrideKey()
        spaceOverrides[key] = configuration
        pruneUnresolvableSpaceOverrides(keeping: key)
        persistSpaceOverrides()
        updateEffectiveConfiguration()
    }

    /// Removes the active Space's override, if any.
    func removeOverrideForActiveSpace() {
        spaceOverrides[activeSpaceOverrideKey()] = nil
        persistSpaceOverrides()
        updateEffectiveConfiguration()
    }

    /// Drops overrides whose key no longer resolves to a managed Space (stale
    /// session keys, deleted Spaces). Runs on save.
    private func pruneUnresolvableSpaceOverrides(keeping key: String) {
        var managedKeys = Set(
            Bridging.getManagedSpaces().map { managedSpace in
                managedSpace.persistentKey
            }
        )
        managedKeys.insert(key)
        let staleKeys = spaceOverrides.keys.filter { !managedKeys.contains($0) }
        guard !staleKeys.isEmpty else { return }
        for staleKey in staleKeys {
            spaceOverrides.removeValue(forKey: staleKey)
        }
        diagLog.debug("Pruned \(staleKeys.count) stale per-Space appearance override(s)")
    }

    /// Removes every per-Space override.
    func removeAllSpaceOverrides() {
        spaceOverrides = [:]
        persistSpaceOverrides()
        updateEffectiveConfiguration()
    }

    private func persistSpaceOverrides() {
        do {
            let data = try encoder.encode(spaceOverrides)
            Defaults.set(data, forKey: .menuBarAppearanceSpaceOverrides)
        } catch {
            diagLog.error("Error encoding per-Space appearance overrides: \(error)")
        }
    }

    private func updateEffectiveConfiguration() {
        effectiveConfiguration = Self.effectiveConfiguration(
            base: configuration,
            overrides: spaceOverrides,
            activeSpaceKey: activeSpaceOverrideKey()
        )
        // `configurationPanelObservationTask` ignores Space changes, so reconcile
        // panels here or an override that needs them renders nothing.
        if overlayPanels.isEmpty {
            configureOverlayPanels(with: effectiveConfiguration)
        } else if !needsOverlayPanels(for: effectiveConfiguration) {
            closeAllOverlayPanels()
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                closeAllOverlayPanels()
                if Set(overlayPanels.map(\.owningScreen)) != Set(NSScreen.screens) {
                    configureOverlayPanels(with: effectiveConfiguration)
                }
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isReduceTransparencyEnabled =
                    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                activeSpaceID = SpaceInfo.activeSpace().spaceID
                updateEffectiveConfiguration()
            }
            .store(in: &c)

        configurationPanelObservationTask?.cancel()
        configurationPanelObservationTask = Task { [weak self] in
            let changes = Observations { [weak self] in self?.configuration }
            for await configuration in changes._throttle(for: .milliseconds(100), latest: true) {
                guard let self else {
                    return
                }
                guard let configuration else {
                    continue
                }
                // The overlay panels may not have been configured yet. Since some of the
                // properties on the manager might call for them, try to configure now.
                if overlayPanels.isEmpty {
                    configureOverlayPanels(with: configuration)
                } else if !needsOverlayPanels(for: configuration) {
                    closeAllOverlayPanels()
                }
            }
        }

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether a set of overlay panels
    /// is needed for the given configuration.
    private func needsOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let current = configuration.current
        if current.hasShadow {
            return true
        }
        if current.borderOnMenuBar {
            return true
        }
        if configuration.shapeKind != .noShape {
            return true
        }
        if current.tintKind != .noTint {
            return true
        }
        if configuration.current.backgroundKind != .none {
            return true
        }
        return false
    }

    /// Configures the manager's overlay panels, if required by the given configuration.
    private func configureOverlayPanels(
        with configuration: MenuBarAppearanceConfigurationV2,
        force: Bool = false
    ) {
        closeAllOverlayPanels()

        guard
            let appState,
            force || needsOverlayPanels(for: configuration)
        else {
            return
        }

        var overlayPanels = Set<MenuBarOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen)
            overlayPanels.insert(panel)
            panel.needsShow = true
        }

        self.overlayPanels = overlayPanels

        // Mission Control displaces every on-screen window together, so one
        // representative screen is enough to drive the shared detector for
        // all panels.
        if let representativeScreen = NSScreen.screens.first {
            missionControlDetector.start(representativeScreen: representativeScreen)
        }
    }

    /// Closes all currently managed overlay panels and stops the shared
    /// Mission Control detector, since nothing needs it while there are no
    /// panels to drive.
    private func closeAllOverlayPanels() {
        while let panel = overlayPanels.popFirst() {
            panel.close()
        }
        missionControlDetector.stop()
    }
}
