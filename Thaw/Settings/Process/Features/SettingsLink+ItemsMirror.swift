//
//  SettingsLink+ItemsMirror.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation

/// The settings process's side of the item mirror: it puts what the app sends into the models the
/// pages read, and tells the app what the page shown needs captured.
@MainActor
final class SettingsItemsMirror {
    private let itemManager: MenuBarItemManager
    private let imageCache: MenuBarItemImageCache
    private let colors: MenuBarWallpaperColorMonitor
    private let navigationState: AppNavigationState
    private let pictureFile: URL?
    /// Whether this process shows a pane itself. A pane it hands to the app needs nothing from here.
    private let showsPane: (String) -> Bool
    private let report: (SettingsProcessCaptureDemand) -> Void
    private var demandWatch: Task<Void, Never>?
    private var frontmostWatch: AnyCancellable?
    /// Each saved picture as last read, by its identifier in the file, so one that did not change is not decoded again.
    private var decoded = [String: (png: Data, capture: MenuBarItemGlyphCapture)]()

    init(
        appState: AppState,
        pictureFile: URL?,
        showsPane: @escaping (String) -> Bool = SettingsProcessRoute.ownProcessPanes.contains,
        report: @escaping (SettingsProcessCaptureDemand) -> Void
    ) {
        itemManager = appState.itemManager
        imageCache = appState.imageCache
        colors = appState.menuBarManager.wallpaperColorMonitor
        navigationState = appState.navigationState
        self.pictureFile = pictureFile
        self.showsPane = showsPane
        self.report = report
        imageCache.prepareToMirror()
    }

    /// The panes that draw no item pictures, so the app readies none for them. Any other pane gets them.
    static let panesWithoutPictures: Set<SettingsNavigationIdentifier> = [.general, .visibility, .privacy, .about]

    /// What the page shown here needs captured, by the rules a page in the app follows.
    var demand: SettingsProcessCaptureDemand {
        let pane = navigationState.settingsNavigationIdentifier
        guard showsPane(pane.rawValue) else { return .none }
        let page = MenuBarItemImageCache.NavigationStateSnapshot(
            isThawBarPresented: false,
            isSearchPresented: false,
            isAppFrontmost: true,
            isSettingsPresented: navigationState.isSettingsPresented,
            settingsNavigationIdentifier: pane,
            isItemHotkeyListExpanded: imageCache.isItemHotkeyListExpanded,
            isSimpleModeSettings: navigationState.isSimpleModeSettings
        )
        return SettingsProcessCaptureDemand(
            consumesCapture: navigationState.hasVisibleCaptureUI,
            scope: page.liveCaptureScope,
            isFrontmost: navigationState.isAppFrontmost,
            showsPictures: navigationState.isSettingsPresented && !Self.panesWithoutPictures.contains(pane),
            needsEveryPicture: imageCache.isItemHotkeyListExpanded
        )
    }

    /// Keeps "this process is in front" current, as the app's launch does for the app.
    func followFrontmostApp() {
        frontmostWatch = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .map { $0 == .current }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [navigationState] in navigationState.isAppFrontmost = $0 }
    }

    /// The app's hello shows the link is up, so from here on the app hears what the page needs.
    func startReporting() {
        guard demandWatch == nil else { return }
        demandWatch = Task { @MainActor [weak self] in
            var reported: SettingsProcessCaptureDemand?
            for await demand in Observations({ [weak self] in self?.demand }) {
                guard let self, let demand else { return }
                guard demand != reported else { continue }
                reported = demand
                report(demand)
            }
        }
    }

    func show(_ cache: MenuBarItemCache) {
        itemManager.itemCache = cache
    }

    func show(_ colors: SettingsBarColors) {
        self.colors.adopt(
            averageColors: colors.averages.compactMapValues(\.info),
            active: colors.active?.info,
            palettes: colors.palettes
        )
    }

    /// Shows exactly the pictures the app names, read from its file. A tag the file has no picture for shows none.
    func show(_ pictures: SettingsItemPictures) {
        let saved = pictureFile.flatMap(MenuBarItemImageCacheDiskStore.savedPictures(at:)) ?? [:]
        var read = [String: (png: Data, capture: MenuBarItemGlyphCapture)]()
        var captures = [MenuBarItemTag: MenuBarItemGlyphCapture]()
        for tag in pictures.tags {
            let identifier = tag.tagIdentifier
            if read[identifier] == nil, let entry = saved[identifier], let png = entry["png"] as? Data {
                read[identifier] = decoded[identifier].flatMap { $0.png == png ? $0 : nil }
                    ?? imageCache.diskStore.decodeEntry(entry, legacyJSON: false).map { (png, $0) }
            }
            captures[tag] = read[identifier]?.capture
        }
        decoded = read
        imageCache.replaceCaptures(with: captures)
    }
}

extension SettingsChildFeature {
    static func items(_ appState: AppState) -> SettingsChildFeature {
        let mirror = SettingsItemsMirror(appState: appState, pictureFile: appState.imageCache.diskStore.cacheFileURL) {
            SettingsRemote.current?.perform(SettingsItemsLink.listen, $0)
        }
        mirror.followFrontmostApp()
        return items(mirror: mirror)
    }

    static func items(mirror: SettingsItemsMirror) -> SettingsChildFeature {
        SettingsChildFeature(statuses: [
            SettingsItemsLink.hello: { _ in mirror.startReporting() },
            SettingsItemsLink.cache: { SettingsLinkPayload.decode(MenuBarItemCache.self, from: $0).map(mirror.show) },
            SettingsItemsLink.pictures: { SettingsLinkPayload.decode(SettingsItemPictures.self, from: $0).map(mirror.show) },
            SettingsItemsLink.colors: { SettingsLinkPayload.decode(SettingsBarColors.self, from: $0).map(mirror.show) },
        ])
    }
}

// MARK: - The picture file

extension MenuBarItemImageCacheDiskStore {
    /// Returns once the saves queued before this call are in the file. It hurries them, because
    /// a window in another process waits for what an ordinary save lets wait.
    nonisolated func queuedSavesLanded() async {
        await withCheckedContinuation { continuation in
            queue.async(qos: .userInitiated) { continuation.resume() }
        }
    }

    /// The pictures in the file at url, by their saved identifier, for a process that only reads.
    /// Unlike readSaveFile(), it leaves a file it can't use where it is: the file is the app's.
    static nonisolated func savedPictures(at url: URL) -> [String: [String: Any]]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              ImageCacheFileValidity.appBuild.map({ $0 == root["build"] as? String }) ?? true
        else { return nil }
        return root["images"] as? [String: [String: Any]]
    }
}

extension MenuBarItemImageCache {
    /// For a cache that is never activated and holds another process's pictures: it keeps its glyph slots current.
    /// It never reads the picture file by itself, which can delete the file.
    @MainActor
    func prepareToMirror() {
        hasLoadedFromDisk = true
        guard !isObservingCapturesForGlyphSlots else { return }
        isObservingCapturesForGlyphSlots = true
        observeCapturesForGlyphSlots()
    }
}
