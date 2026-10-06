//
//  MenuBarAppearanceManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine
import MenuBarModel
import Observation

/// Layers per-Space overrides over stored appearance settings and renders them in per-screen overlays.
@MainActor
@Observable
final class MenuBarAppearanceManager {
    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarAppearanceManager")

    /// Shared appearance settings persist in didSet; panels react separately through throttled effectiveConfiguration.
    var configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2 {
        didSet {
            // Switching a surface to accent color must update it before the next system accent change.
            let synced = configuration
                .withAccentColor(Self.accentColor)
                .withSystemGlass(tinted: Self.systemGlassIsTinted)
            if synced != configuration {
                configuration = synced
                return
            }
            guard oldValue != configuration else { return }
            persist(configuration, forKey: .menuBarAppearanceConfigurationV2, label: "menu bar appearance configuration")
        }
    }

    /// NSGlassTintAmount is 0 for Clear, 1 for Tinted, and intermediate during animation.
    static var systemGlassIsTinted: Bool {
        UserDefaults.standard.double(forKey: "NSGlassTintAmount") >= 0.5
    }

    /// The system accent color, in the color space the look is stored in.
    static var accentColor: CGColor {
        (NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor).cgColor
    }

    /// Live editor preview replaces stored settings; nil when inactive.
    var previewConfiguration: MenuBarAppearancePartialConfiguration? {
        didSet {
            reactToPreviewConfigurationChange()
        }
    }

    /// Overrides keyed by stringified CGSSpaceID.
    /// Launch restore also triggers didSet, harmlessly persisting the just-loaded data.
    private(set) var spaceOverrides: [String: MenuBarAppearanceConfigurationV2] = [:] {
        didSet {
            guard oldValue != spaceOverrides else { return }
            persist(spaceOverrides, forKey: .menuBarAppearanceSpaceOverrides, label: "per-Space appearance overrides")
        }
    }

    /// didSet cannot throw; record encoding failures here so the editor warns about unsaved settings.
    /// Nil when stored settings are current.
    private(set) var lastPersistenceFailure: String?

    /// The most recently observed active Space.
    private(set) var activeSpaceID = SpaceInfo.activeSpace().spaceID

    /// Render the active Space's override, falling back to shared settings.
    /// Observation tracks all three inputs through this computed property.
    var effectiveConfiguration: MenuBarAppearanceConfigurationV2 {
        Self.effectiveConfiguration(
            base: configuration,
            overrides: spaceOverrides,
            activeSpaceID: activeSpaceID
        )
    }

    @ObservationIgnored
    private weak var appState: AppState?

    @ObservationIgnored
    private let encoder = JSONEncoder()

    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// Keeps the manager's Combine subscriptions alive.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// _throttle is the pinned AsyncAlgorithms release's public throttle operator.
    /// latest: true coalesces panel updates to the newest effectiveConfiguration.
    @ObservationIgnored
    private var panelRequirementsTask: Task<Void, Never>?

    /// One overlay panel per managed screen, or empty when nothing needs painting.
    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// Compare display frames to avoid rebuilding for brightness, HDR, colorspace, or relaunch notifications.
    /// Unnecessary rebuilds blink the overlay and strand NSGlassEffectView composite appearances.
    private var lastConfiguredScreenLayout: [CGDirectDisplayID: CGRect] = [:]

    private static func currentScreenLayout() -> [CGDirectDisplayID: CGRect] {
        Dictionary(NSScreen.managedScreens.map { ($0.displayID, $0.frame) }) { first, _ in first }
    }

    /// Inset from the menu bar's edges for inset appearances.
    let menuBarInsetAmount: CGFloat = 3.5

    /// Call once to restore settings and start observing.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Decode shared settings and overrides independently so one unreadable key does not block the other.
    private func loadInitialState() {
        if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
            do {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            } catch {
                diagLog.error("Error decoding menu bar appearance configuration: \(error)")
            }
        }
        if let data = Defaults.data(forKey: .menuBarAppearanceSpaceOverrides) {
            do {
                spaceOverrides = try decoder.decode(
                    [String: MenuBarAppearanceConfigurationV2].self,
                    from: data
                )
            } catch {
                diagLog.error("Error decoding per-Space appearance overrides: \(error)")
            }
        }
    }

    // MARK: Per-Space Overrides

    /// Resolves the configuration for a Space. Pure so it is unit-testable.
    static nonisolated func effectiveConfiguration(
        base: MenuBarAppearanceConfigurationV2,
        overrides: [String: MenuBarAppearanceConfigurationV2],
        activeSpaceID: CGSSpaceID
    ) -> MenuBarAppearanceConfigurationV2 {
        overrides[String(activeSpaceID)] ?? base
    }

    var activeSpaceHasOverride: Bool {
        spaceOverrides[String(activeSpaceID)] != nil
    }

    /// Uses shared settings, not the current preview, for the Space override.
    func saveOverrideForActiveSpace() {
        spaceOverrides[String(activeSpaceID)] = configuration
    }

    func removeOverrideForActiveSpace() {
        spaceOverrides[String(activeSpaceID)] = nil
    }

    func removeAllSpaceOverrides() {
        spaceOverrides = [:]
    }

    private func configureCancellables() {
        cancellables = [
            observeScreenParameters(),
            observeActiveSpace(),
            observeAccentColor(),
            observeSystemGlass(),
        ]

        panelRequirementsTask?.cancel()
        panelRequirementsTask = Task { [weak self] in
            let changes = Observations { [weak self] in self?.effectiveConfiguration }
            for await configuration in changes._throttle(for: .milliseconds(100), latest: true) {
                guard let self, let configuration else { return }
                updateOverlayPanels(for: configuration)
                // Partner apps mirror the look; they fetch it again on this.
                DistributedNotificationCenter.default().postNotificationName(
                    SharedAppearance.didChangeNotification,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        }
    }

    /// Records encoding failures in lastPersistenceFailure instead of throwing.
    private func persist(_ value: some Encodable, forKey key: Defaults.Key, label: String) {
        do {
            let data = try encoder.encode(value)
            Defaults.set(data, forKey: key)
            lastPersistenceFailure = nil
        } catch {
            diagLog.error("Error encoding \(label): \(error)")
            lastPersistenceFailure = error.localizedDescription
        }
    }

    private func rebuildOverlayPanelsIfScreensMoved() {
        // Unchanged geometry needs no rebuild, avoiding overlay blinks and composite-appearance leaks.
        if !overlayPanels.isEmpty,
           Self.currentScreenLayout() == lastConfiguredScreenLayout
        {
            return
        }
        closeOverlayPanels()
        configureOverlayPanels(with: configuration)
    }

    private func closeOverlayPanels() {
        while let panel = overlayPanels.popFirst() {
            panel.close()
        }
    }

    private func observeScreenParameters() -> AnyCancellable {
        DisplayTopology.shared.screenParametersChanged
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.rebuildOverlayPanelsIfScreensMoved() }
    }

    /// Update accent-following surfaces when the system accent changes.
    private func observeAccentColor() -> AnyCancellable {
        NotificationCenter.default
            .publisher(for: NSColor.systemColorsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                configuration = configuration.withAccentColor(Self.accentColor)
            }
    }

    /// No notification announces Liquid Glass changes; observe the preference directly.
    private func observeSystemGlass() -> AnyCancellable {
        UserDefaults.standard
            .publisher(for: \.NSGlassTintAmount)
            .map { $0 >= 0.5 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tinted in
                guard let self else { return }
                configuration = configuration.withSystemGlass(tinted: tinted)
            }
    }

    private func observeActiveSpace() -> AnyCancellable {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.activeSpaceID = SpaceInfo.activeSpace().spaceID
            }
    }

    private func updateOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) {
        // Build panels lazily when effects first need them.
        if overlayPanels.isEmpty {
            configureOverlayPanels(with: configuration)
        } else if !needsOverlayPanels(for: configuration) {
            closeOverlayPanels()
        }
    }

    /// A preview can need overlays even when stored settings do not.
    private func reactToPreviewConfigurationChange() {
        if let preview = previewConfiguration {
            let needsPanels = preview.hasShadow
                || preview.hasBorder
                || configuration.shapeKind != .noShape
                || preview.tintKind != .noTint
                || preview.backgroundKind != .none
            if overlayPanels.isEmpty, needsPanels {
                configureOverlayPanels(with: configuration, force: true)
            }
        } else {
            if !needsOverlayPanels(for: configuration) {
                closeOverlayPanels()
            }
        }
    }

    /// These effects are not system-painted; without them the menu bar needs no overlay.
    private func needsOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let current = configuration.current
        return current.hasShadow
            || current.hasBorder
            || configuration.shapeKind != .noShape
            || current.tintKind != .noTint
            || configuration.current.backgroundKind != .none
    }

    /// Always rebuilds; when no effects are needed, clear the layout signature so future notifications retry.
    /// - Parameter force: Build even when stored settings need no panels, as for a live preview.
    private func configureOverlayPanels(
        with configuration: MenuBarAppearanceConfigurationV2,
        force: Bool = false
    ) {
        // Close existing panels to prevent memory leaks and duplicate windows
        closeOverlayPanels()

        guard
            let appState,
            force || needsOverlayPanels(for: configuration)
        else {
            lastConfiguredScreenLayout = [:]
            return
        }

        overlayPanels = Set(NSScreen.managedScreens.map { screen in
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen)
            panel.needsShow = true
            return panel
        })
        lastConfiguredScreenLayout = Self.currentScreenLayout()
    }
}

private extension UserDefaults {
    /// The system's Liquid Glass tint, observable with key-value observing.
    /// The name has to match the preference key.
    @objc dynamic var NSGlassTintAmount: Double {
        double(forKey: "NSGlassTintAmount")
    }
}
