//
//  SettingsLink+Items.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation

/// The menu bar items mirrored read-only into the settings process: the item list, the pictures and the bar colours.
/// Nothing here acts on an item, and imageCache.hasNoRenderableItems(in:) always answers false in that process.
nonisolated enum SettingsItemsLink {
    /// Sent as the settings process starts. It answers with listen, and only then does the app send the rest.
    static let hello = "items.hello"
    static let cache = "items.cache"
    static let pictures = "items.pictures"
    static let colors = "items.colors"
    /// The settings process reads the mirror, and this is what its page needs captured.
    static let listen = "items.listen"
    static let sampleColors = "items.sampleColors"

    /// Has the app sample the bar's colours again, for one display or for all it would sample itself.
    @MainActor
    static func sampleColors(for displayID: CGDirectDisplayID?) {
        if let displayID {
            SettingsRemote.current?.perform(sampleColors, displayID)
        } else {
            SettingsRemote.current?.perform(sampleColors)
        }
    }
}

/// The pictures the app holds, once they are in its picture file.
nonisolated struct SettingsItemPictures: Codable, Equatable {
    /// Counts the changes, so pictures redrawn under the same tags still read as new.
    var revision = 0
    var tags = [MenuBarItemTag]()
}

/// The bar colours the app sampled.
nonisolated struct SettingsBarColors: Codable, Equatable {
    /// One sample, as its colour space's name and components.
    nonisolated struct Sample: Codable, Equatable {
        var space: String
        var components: [Double]
        var isFromWallpaper: Bool

        /// Nil for a colour that can't be named or converted. A display's own colour space has no
        /// name, so its sample travels as sRGB.
        @MainActor
        init?(_ info: MenuBarAverageColorInfo) {
            let named = info.color.colorSpace?.name == nil
                ? CGColorSpace(name: CGColorSpace.sRGB).flatMap { info.color.converted(to: $0, intent: .defaultIntent, options: nil) }
                : info.color
            guard let named, let space = named.colorSpace?.name, let components = named.components else { return nil }
            self.space = space as String
            self.components = components.map(Double.init)
            isFromWallpaper = info.source == .desktopWallpaper
        }

        @MainActor var info: MenuBarAverageColorInfo? {
            guard let space = CGColorSpace(name: space as CFString),
                  let color = CGColor(colorSpace: space, components: components.map { CGFloat($0) })
            else { return nil }
            return MenuBarAverageColorInfo(color: color, source: isFromWallpaper ? .desktopWallpaper : .menuBarWindow)
        }
    }

    var averages = [CGDirectDisplayID: Sample]()
    /// The sample of the display with the active menu bar.
    var active: Sample?
    var palettes = [CGDirectDisplayID: WallpaperPalette]()
}

extension SettingsBarColors {
    @MainActor
    init(_ monitor: MenuBarWallpaperColorMonitor) {
        averages = monitor.averageColors.compactMapValues(Sample.init)
        active = monitor.averageColorInfo.flatMap(Sample.init)
        palettes = monitor.wallpaperPalettes
    }
}

// MARK: - In the app

/// The app's side of the item mirror. It does nothing until a settings process says it listens,
/// and stops when that process ends.
@MainActor
@Observable
final class SettingsItemsRelay {
    /// What the relay reads from the app and has it do.
    struct App {
        var itemCache: () -> MenuBarItemCache
        var captures: () -> [MenuBarItemTag: MenuBarItemGlyphCapture]
        /// Readies the pictures as opening Settings in the app does.
        var preparePictures: () -> Void
        /// Writes the pictures to their file and returns once they are there.
        var savePictures: () async -> Void
        /// Lets the pictures go again once nothing in the app shows them.
        var releasePictures: () -> Void
        var setCaptureDemand: (SettingsProcessCaptureDemand) -> Void
        var sampleColors: (CGDirectDisplayID?) -> Void
    }

    /// How long the relay waits after sending one kind of state before it sends that kind again.
    struct Pace {
        var items = Duration.milliseconds(250)
        var pictures = Duration.milliseconds(500)
        /// macOS posts nothing when the desktop picture changes, so a preview's colours are sampled again this often.
        var colors = Duration.seconds(60)
    }

    private(set) var isListening = false
    /// The item list to send, and the pictures that are in the file. Nil sends nothing.
    private(set) var itemCache: MenuBarItemCache?
    private(set) var pictures: SettingsItemPictures?

    @ObservationIgnored private let app: App
    @ObservationIgnored private let pace: Pace
    @ObservationIgnored private var itemWatch: Task<Void, Never>?
    @ObservationIgnored private var pictureWatch: Task<Void, Never>?
    @ObservationIgnored private var colorPoll: Task<Void, Never>?

    init(app: App, pace: Pace = Pace()) {
        self.app = app
        self.pace = pace
    }

    /// The settings process reads the mirror and its page needs this captured. Sent again whenever the need changes.
    func listen(_ demand: SettingsProcessCaptureDemand) {
        app.setCaptureDemand(demand)
        pollColors(demand.consumesCapture)
        if !isListening {
            isListening = true
            itemWatch = followItems()
        }
        // Reading and saving pictures costs the app memory and work, so it waits for a page that draws them.
        if demand.showsPictures, pictureWatch == nil {
            app.preparePictures()
            pictureWatch = followPictures()
        }
    }

    /// The settings process has ended: nothing is sent or captured for it any more.
    func stop() {
        guard isListening else { return }
        itemWatch?.cancel()
        itemWatch = nil
        pollColors(false)
        isListening = false
        itemCache = nil
        pictures = nil
        app.setCaptureDemand(.none)
        guard let pictureWatch else { return }
        pictureWatch.cancel()
        self.pictureWatch = nil
        app.releasePictures()
    }

    func sampleColors(for displayID: CGDirectDisplayID?) {
        app.sampleColors(displayID)
    }

    /// A scan publishes the cache whether or not it changed, so only a different one is sent, and a burst as one.
    private func followItems() -> Task<Void, Never> {
        Task { @MainActor [weak self, app, pace] in
            for await cache in Observations({ app.itemCache() }) {
                guard let self, !Task.isCancelled else { return }
                if cache != itemCache {
                    itemCache = cache
                }
                try? await Task.sleep(for: pace.items)
            }
        }
    }

    /// Names the pictures once the file holds them. Only a new or redrawn picture is worth a save: after
    /// pictures were merely dropped, the file still has them for the app's next read.
    private func followPictures() -> Task<Void, Never> {
        Task { @MainActor [weak self, app, pace] in
            var named = [MenuBarItemTag: MenuBarItemGlyphCapture]()
            var revision = 0
            for await captures in Observations({ app.captures() }) {
                let isRedrawn = captures.contains { named[$0.key]?.cgImage !== $0.value.cgImage }
                guard isRedrawn || captures.count != named.count else { continue }
                if isRedrawn {
                    await app.savePictures()
                }
                guard let self, !Task.isCancelled else { return }
                named = captures
                revision += 1
                pictures = SettingsItemPictures(revision: revision, tags: Array(captures.keys))
                try? await Task.sleep(for: pace.pictures)
            }
        }
    }

    /// Samples the colours now and then for as long as the page shown reads the screen.
    private func pollColors(_ isWanted: Bool) {
        guard isWanted != (colorPoll != nil) else { return }
        colorPoll?.cancel()
        colorPoll = nil
        guard isWanted else { return }
        colorPoll = Task { @MainActor [app, pace] in
            while !Task.isCancelled {
                app.sampleColors(nil)
                try? await Task.sleep(for: pace.colors)
            }
        }
    }
}

extension SettingsItemsRelay.App {
    static func live(_ appState: AppState) -> SettingsItemsRelay.App {
        SettingsItemsRelay.App(
            itemCache: { [weak appState] in appState?.itemManager.itemCache ?? MenuBarItemCache(displayID: nil) },
            captures: { [weak appState] in appState?.imageCache.capturesByTag ?? [:] },
            preparePictures: { [weak appState] in appState?.imageCache.prepareForPresentation() },
            savePictures: { [weak appState] in
                guard let imageCache = appState?.imageCache else { return }
                imageCache.saveToDisk()
                await imageCache.diskStore.queuedSavesLanded()
            },
            releasePictures: { [weak appState] in appState?.imageCache.scheduleIdleTrim() },
            setCaptureDemand: { [weak appState] in appState?.navigationState.settingsProcessCapture = $0 },
            sampleColors: { [weak appState] displayID in
                Task { await appState?.menuBarManager.updateAverageColorInfoAsync(for: displayID) }
            }
        )
    }
}

extension SettingsAppFeature {
    static func items(_ appState: AppState) -> SettingsAppFeature {
        items(relay: SettingsItemsRelay(app: .live(appState))) { [weak appState] in
            appState.map { SettingsBarColors($0.menuBarManager.wallpaperColorMonitor) }
        }
    }

    static func items(relay: SettingsItemsRelay, colors: @escaping () -> SettingsBarColors?) -> SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                SettingsItemsLink.hello: { SettingsLinkPayload.encode(true) },
                SettingsItemsLink.cache: { relay.itemCache.flatMap(SettingsLinkPayload.encode) },
                SettingsItemsLink.pictures: { relay.pictures.flatMap(SettingsLinkPayload.encode) },
                SettingsItemsLink.colors: { relay.isListening ? colors().flatMap(SettingsLinkPayload.encode) : nil },
            ],
            commands: [
                SettingsItemsLink.listen: { payload in
                    SettingsLinkPayload.decode(SettingsProcessCaptureDemand.self, from: payload).map(relay.listen)
                },
                SettingsItemsLink.sampleColors: { payload in
                    relay.sampleColors(for: SettingsLinkPayload.decode(CGDirectDisplayID.self, from: payload))
                },
            ],
            processEnded: { relay.stop() }
        )
    }
}
