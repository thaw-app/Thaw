//
//  SettingsLink+ThawBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

/// The Thaw Bar page's share of the link. Its settings are stored preferences both ends read again, and its
/// preview draws the mirrored items. The app opens the real bar, samples for the preview and names the apps the bar leaves out.
@MainActor
enum ThawBarSettingsLink {
    /// Sent by the app: the apps switched off in System Settings, whose items the bar and its preview leave out.
    static let switchedOffApps = "thawBar.switchedOffApps"
    /// Asked of the app: open the real Thaw Bar.
    static let open = "thawBar.open"
    /// Asked of the app: sample the colour of the display the preview draws.
    static let sample = "thawBar.sample"

    struct Open: Codable, Equatable {
        var section: MenuBarSection.Name
        var displayID: CGDirectDisplayID
        /// The settings process's display settings, which the app takes first, so the bar opens as the page shows it.
        var settings: DisplaySettingsManager.Snapshot
    }

    /// Opens the Thaw Bar's panel on a display.
    typealias Show = @MainActor (_ section: MenuBarSection.Name, _ displayID: CGDirectDisplayID) -> Void

    static func app(_ appState: AppState) -> SettingsAppFeature {
        app(
            displaySettings: appState.settings.displaySettings,
            hiding: appState.menuBarManager.nativeAppHidingExperiment,
            sampler: ThawBarPreviewSampler(
                isCaptureShown: { [weak appState] in appState?.navigationState.hasVisibleCaptureUI ?? false },
                sample: { [weak appState] in await appState?.menuBarManager.updateAverageColorInfoAsync(for: $0) }
            ),
            show: showsBar(of: appState)
        )
    }

    static func child(_ appState: AppState) -> SettingsChildFeature {
        child(hiding: appState.menuBarManager.nativeAppHidingExperiment)
    }

    static func app(
        displaySettings: DisplaySettingsManager,
        hiding: NativeAppHidingExperiment,
        sampler: ThawBarPreviewSampler,
        show: @escaping Show
    ) -> SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                // Sorted, because a set's order is not the same from one encoding to the next.
                switchedOffApps: { SettingsLinkPayload.encode(hiding.userSwitchedOffBundleIDs.sorted()) },
            ],
            commands: [
                open: { payload in
                    guard let request = SettingsLinkPayload.decode(Open.self, from: payload) else { return }
                    displaySettings.adopt(request.settings)
                    show(request.section, request.displayID)
                },
                sample: { payload in
                    SettingsLinkPayload.decode(CGDirectDisplayID.self, from: payload).map(sampler.request)
                },
            ],
            processEnded: { sampler.stop() }
        )
    }

    static func child(hiding: NativeAppHidingExperiment) -> SettingsChildFeature {
        SettingsChildFeature(statuses: [
            switchedOffApps: { payload in
                SettingsLinkPayload.decode([String].self, from: payload).map { hiding.mirrorUserSwitchedOffApps(Set($0)) }
            },
        ])
    }

    /// Opens this process's own bar, on a display that is connected.
    static func showsBar(of appState: AppState) -> Show {
        { [weak appState] section, displayID in
            guard let screen = NSScreen.screen(for: displayID) else { return }
            appState?.menuBarManager.thawBarPanel.show(section: section, on: screen)
        }
    }

    /// The page's button that opens the real bar. The bar is the app's, so the settings process has the app
    /// open it, and sends its display settings along so an edit made a moment ago shows in the bar.
    static func openBar(
        _ section: MenuBarSection.Name,
        on displayID: CGDirectDisplayID,
        settings: DisplaySettingsManager,
        remote: SettingsRemote? = .current,
        show: Show
    ) {
        guard let remote else { return show(section, displayID) }
        remote.perform(open, Open(section: section, displayID: displayID, settings: settings.snapshot))
    }

    /// Has the colour of the preview's display sampled again. Only the app reads the screen.
    static func sampleColors(
        for displayID: CGDirectDisplayID,
        remote: SettingsRemote? = .current,
        here: @MainActor (CGDirectDisplayID) async -> Void
    ) async {
        guard let remote else { return await here(displayID) }
        remote.perform(sample, displayID)
    }
}

/// Samples a display for the preview once the app knows a page that reads the screen is shown. The request
/// can arrive before that word does, and the colour monitor samples nothing until then.
@MainActor
final class ThawBarPreviewSampler {
    private let isCaptureShown: @MainActor () -> Bool
    private let sample: @MainActor (CGDirectDisplayID) async -> Void
    private var waiting: Task<Void, Never>?

    init(isCaptureShown: @escaping @MainActor () -> Bool, sample: @escaping @MainActor (CGDirectDisplayID) async -> Void) {
        self.isCaptureShown = isCaptureShown
        self.sample = sample
    }

    /// Samples the display now, or as soon as such a page is shown. A newer request replaces one still waiting.
    func request(_ displayID: CGDirectDisplayID) {
        waiting?.cancel()
        waiting = Task { @MainActor [isCaptureShown, sample] in
            for await isShown in Observations({ isCaptureShown() }) where isShown {
                guard !Task.isCancelled else { return }
                await sample(displayID)
                return
            }
        }
    }

    /// The settings process has ended, so nothing waits for its page any more.
    func stop() {
        waiting?.cancel()
        waiting = nil
    }
}
