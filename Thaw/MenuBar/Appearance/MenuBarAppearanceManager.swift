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
    /// `didSet` persists the new value, replacing the old unthrottled
    /// `$configuration.encode(encoder:).sink` pipeline — persistence always
    /// ran on every change, so a direct `didSet` is a faithful replacement.
    /// The throttled panel-reconfiguration reaction is handled separately by
    /// `configurationPanelObservationTask` (wave 3), since it genuinely needs
    /// rate-limiting and `didSet` has no equivalent.
    var configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2 {
        didSet {
            do {
                let data = try encoder.encode(configuration)
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            } catch {
                diagLog.error("Error encoding menu bar appearance configuration: \(error)")
            }
        }
    }

    /// The currently previewed partial configuration.
    ///
    /// `didSet` replaces the old (unthrottled) `$previewConfiguration.sink`.
    var previewConfiguration: MenuBarAppearancePartialConfiguration? {
        didSet {
            if let previewConfiguration {
                let needsPanels = previewConfiguration.hasShadow
                    || previewConfiguration.hasBorder
                    || configuration.shapeKind != .noShape
                    || previewConfiguration.tintKind != .noTint
                    || previewConfiguration.backgroundKind != .none
                if overlayPanels.isEmpty, needsPanels {
                    configureOverlayPanels(with: configuration, force: true)
                }
            } else {
                if !needsOverlayPanels(for: configuration) {
                    closeAllOverlayPanels()
                }
            }
        }
    }

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

    /// Task observing `configuration`, throttled to match the old
    /// `$configuration.throttle(for: 0.1, scheduler: DispatchQueue.main,
    /// latest: true)` pipeline that decides whether the overlay panels need
    /// to be created or torn down (wave 3).
    ///
    /// `configuration` is now a plain `@Observable` property rather than a
    /// Combine `@Published` one, so there's no `$configuration` publisher to
    /// throttle directly. Instead, `Observations { configuration }` (an
    /// `AsyncSequence`) is wrapped with AsyncAlgorithms' `_throttle(for:
    /// latest:)`. The leading underscore is not a typo: in the pinned
    /// swift-async-algorithms 1.1.5 revision, the rate-limiting throttle
    /// overloads are still exposed under the underscored name pending
    /// stabilization — `_throttle(for:latest:)` is the only public throttle
    /// operator this package version actually provides. The `latest: true`
    /// argument preserves the original's "coalesce to the newest value seen
    /// during the interval" semantics.
    private var configurationPanelObservationTask: Task<Void, Never>?

    /// The currently managed menu bar overlay panels.
    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// The shared Mission Control detector used by all overlay panels.
    ///
    /// Owned here, alongside `overlayPanels`, rather than one per panel:
    /// probing the window server for displacement is a synchronous IPC
    /// call, and running it once for the whole app instead of once per
    /// screen is the point of this type. See `MissionControlDetector`.
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
                    configureOverlayPanels(with: configuration)
                }
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
                    // Configuration no longer needs panels, close them
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
        if current.hasBorder {
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
        // Close existing panels to prevent memory leaks and duplicate windows
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
