//
//  SettingsLinkItemsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Observation
import Testing
@testable import Thaw

private typealias Demand = SettingsProcessCaptureDemand

@MainActor
private enum Fixture {
    static func tag(_ title: String, windowID: CGWindowID? = nil) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("com.example.items"), title: title, windowID: windowID)
    }

    static func item(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: tag(title, windowID: 5), windowID: 5, ownerPID: 1, sourcePID: 2,
            bounds: CGRect(x: 10, y: 0, width: 24, height: 22), title: title, isOnScreen: true
        )
    }

    static func capture(width: Int) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: width, height: 16, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 16))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
    }

    static func payload(_ value: some Encodable) throws -> Data {
        try #require(SettingsLinkPayload.encode(value))
    }
}

/// The app as the relay sees it, with what the relay asked of it.
@MainActor
@Observable
private final class FakeApp {
    var cache = MenuBarItemCache(displayID: 1)
    var captures: [MenuBarItemTag: MenuBarItemGlyphCapture] = [:]
    @ObservationIgnored var demands = [Demand]()
    @ObservationIgnored var prepares = 0
    @ObservationIgnored var saves = 0
    @ObservationIgnored var releases = 0
    @ObservationIgnored var samples = [CGDirectDisplayID?]()

    var app: SettingsItemsRelay.App {
        SettingsItemsRelay.App(
            itemCache: { self.cache },
            captures: { self.captures },
            preparePictures: { self.prepares += 1 },
            savePictures: { self.saves += 1 },
            releasePictures: { self.releases += 1 },
            setCaptureDemand: { self.demands.append($0) },
            sampleColors: { self.samples.append($0) }
        )
    }
}

@Suite("Settings process item mirror, in the app")
@MainActor
struct SettingsItemsRelayTests {
    private let fake = FakeApp()
    private let feature: SettingsAppFeature

    init() {
        let pace = SettingsItemsRelay.Pace(items: .milliseconds(1), pictures: .milliseconds(1), colors: .milliseconds(5))
        feature = .items(relay: SettingsItemsRelay(app: fake.app, pace: pace)) { SettingsBarColors() }
    }

    private func status<Value: Decodable>(_ topic: String, _: Value.Type = Value.self) -> Value? {
        feature.statuses[topic]?().flatMap { SettingsLinkPayload.decode(Value.self, from: $0) }
    }

    private func listen(_ demand: Demand = .none) throws {
        try feature.commands[SettingsItemsLink.listen]?(Fixture.payload(demand))
    }

    @Test("The item list is sent once the settings process listens, follows the app, and stops when the process ends")
    func itemList() async throws {
        #expect(status(SettingsItemsLink.hello, Bool.self) == true)
        for topic in [SettingsItemsLink.cache, SettingsItemsLink.pictures, SettingsItemsLink.colors] {
            #expect(feature.statuses[topic]?() == nil, "\(topic) waits for the settings process")
        }
        feature.processEnded()
        #expect(fake.releases == 0, "A process that never listened leaves nothing to undo")

        let demand = Demand(consumesCapture: false, scope: .allSections, isFrontmost: true)
        try listen(demand)
        #expect(fake.demands == [demand])
        #expect(fake.prepares == 0, "No page draws pictures yet")
        #expect(await settingsLinkWait { status(SettingsItemsLink.cache, MenuBarItemCache.self) == fake.cache })
        #expect(status(SettingsItemsLink.colors, SettingsBarColors.self) == SettingsBarColors())

        var changed = fake.cache
        changed[.hidden] = [Fixture.item("Clock")]
        fake.cache = MenuBarItemCache(displayID: 2)
        fake.cache = changed
        #expect(await settingsLinkWait { status(SettingsItemsLink.cache, MenuBarItemCache.self) == changed })

        feature.processEnded()
        #expect(fake.demands == [demand, .none])
        #expect(fake.releases == 0, "No pictures were readied, so none are let go")
        fake.cache = MenuBarItemCache(displayID: 3)
        for _ in 0 ..< 3 {
            await mainActorQueueDrained()
        }
        #expect(feature.statuses[SettingsItemsLink.cache]?() == nil)
        #expect(feature.statuses[SettingsItemsLink.colors]?() == nil)
    }

    @Test("Pictures are named once they are saved, and only a new or redrawn one is saved")
    func pictures() async throws {
        let (clock, wifi) = (Fixture.tag("Clock", windowID: 5), Fixture.tag("Wi-Fi"))
        try listen()
        fake.captures = try [clock: Fixture.capture(width: 20), wifi: Fixture.capture(width: 30)]
        for _ in 0 ..< 3 {
            await mainActorQueueDrained()
        }
        #expect(fake.prepares == 0 && fake.saves == 0, "A page that draws no pictures costs the app none")
        try listen(Demand(showsPictures: true))
        try listen()
        try listen(Demand(showsPictures: true))
        #expect(fake.prepares == 1, "The pictures are readied once and then followed until the process ends")
        #expect(await settingsLinkWait { Set(status(SettingsItemsLink.pictures, SettingsItemPictures.self)?.tags ?? []) == [clock, wifi] })
        #expect(fake.saves == 1)
        let first = try #require(status(SettingsItemsLink.pictures, SettingsItemPictures.self)).revision

        fake.captures[wifi] = nil
        #expect(await settingsLinkWait { status(SettingsItemsLink.pictures, SettingsItemPictures.self)?.tags == [clock] })
        #expect(fake.saves == 1, "The file still holds a picture that was only dropped")
        let second = try #require(status(SettingsItemsLink.pictures, SettingsItemPictures.self)).revision
        #expect(second > first)

        fake.captures[clock] = try Fixture.capture(width: 20)
        #expect(await settingsLinkWait { (status(SettingsItemsLink.pictures, SettingsItemPictures.self)?.revision ?? 0) > second })
        #expect(fake.saves == 2)

        feature.processEnded()
        #expect(fake.releases == 1)
        #expect(feature.statuses[SettingsItemsLink.pictures]?() == nil)
    }

    @Test("A sample asked for before the page reads the screen is taken once it does, and dropped if the process ends first")
    func earlySampleWaitsForThePage() throws {
        try feature.commands[SettingsItemsLink.sampleColors]?(Fixture.payload(CGDirectDisplayID(3)))
        try feature.commands[SettingsItemsLink.sampleColors]?(Fixture.payload(CGDirectDisplayID(7)))
        try listen()
        #expect(fake.samples.isEmpty, "The app samples nothing for a page that reads no screen")
        try listen(Demand(consumesCapture: true))
        #expect(fake.samples.first == .some(7), "The last request stands for the earlier one")
        #expect(!fake.samples.contains(3))

        feature.processEnded()
        try feature.commands[SettingsItemsLink.sampleColors]?(Fixture.payload(CGDirectDisplayID(9)))
        feature.processEnded()
        try listen(Demand(consumesCapture: true))
        #expect(!fake.samples.contains(9), "A request the ended process left behind is not taken for the next one")
    }

    @Test("Colours are sampled when a preview asks, and now and then while the page shown reads the screen")
    func colours() async throws {
        try listen(Demand(consumesCapture: true))
        try feature.commands[SettingsItemsLink.sampleColors]?(Fixture.payload(CGDirectDisplayID(7)))
        feature.commands[SettingsItemsLink.sampleColors]?(Data())
        #expect(fake.samples.prefix(2) == [7, nil])

        #expect(await settingsLinkWait { fake.samples.count >= 5 })
        #expect(fake.samples.dropFirst(2).allSatisfy { $0 == nil })

        try listen()
        let sampled = fake.samples.count
        try await Task.sleep(for: .milliseconds(30))
        #expect(fake.samples.count == sampled, "A page that no longer reads the screen is not sampled for")
    }

    @Test("A preview's request for new colours goes to the app, and the app's own feature waits to be asked")
    func previewAsksTheApp() {
        var sent = [SettingsLinkMessage]()
        let previous = SettingsRemote.current
        SettingsRemote.current = SettingsRemote { sent.append($0) }
        defer { SettingsRemote.current = previous }
        SettingsItemsLink.sampleColors(for: 7)
        SettingsItemsLink.sampleColors(for: nil)
        #expect(sent == [
            .command(name: SettingsItemsLink.sampleColors, payload: Data("7".utf8)),
            .command(name: SettingsItemsLink.sampleColors, payload: Data()),
        ])

        let live = SettingsAppFeature.items(AppState())
        #expect(live.statuses[SettingsItemsLink.hello]?() != nil)
        for topic in [SettingsItemsLink.cache, SettingsItemsLink.pictures, SettingsItemsLink.colors] {
            #expect(live.statuses[topic]?() == nil, "\(topic) costs the app nothing while no settings process listens")
        }
    }

    @Test("What the mirror sends survives being encoded and decoded")
    func payloads() throws {
        let demand = Demand(consumesCapture: true, scope: .allSections, isFrontmost: true, showsPictures: true, needsEveryPicture: true)
        #expect(try SettingsLinkPayload.decode(Demand.self, from: Fixture.payload(demand)) == demand)
        #expect(Demand(scope: .allSections, showsPictures: true).asIfFrontmost == Demand(scope: .allSections, isFrontmost: true, showsPictures: true))

        let pictures = SettingsItemPictures(revision: 4, tags: [Fixture.tag("Clock", windowID: 5), Fixture.tag("Wi-Fi")])
        #expect(try SettingsLinkPayload.decode(SettingsItemPictures.self, from: Fixture.payload(pictures)) == pictures)

        let bar = MenuBarAverageColorInfo(color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), source: .desktopWallpaper)
        var colors = SettingsBarColors()
        colors.averages[4] = SettingsBarColors.Sample(bar)
        colors.active = SettingsBarColors.Sample(bar)
        colors.palettes[4] = WallpaperPalette(swatches: [WallpaperPalette.Swatch(red: 0.1, green: 0.2, blue: 0.3, weight: 1)])
        let decoded = try #require(try SettingsLinkPayload.decode(SettingsBarColors.self, from: Fixture.payload(colors)))
        #expect(decoded == colors)
        #expect(decoded.averages[4]?.info == bar)

        // A display's own colour space has no name to send, so its sample travels as sRGB.
        let display = try #require(CGColor(colorSpace: CGDisplayCopyColorSpace(CGMainDisplayID()), components: [0.2, 0.4, 0.6, 1]))
        let sample = try #require(SettingsBarColors.Sample(MenuBarAverageColorInfo(color: display, source: .menuBarWindow)))
        #expect(sample.info?.source == .menuBarWindow)
        #expect(sample.info?.color.numberOfComponents == 4)
    }
}

@Suite("Settings process item mirror, in the settings process", .serialized, .scratchDefaults)
@MainActor
final class SettingsItemsMirrorTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: ScratchDefaults.name("SettingsItemsMirrorTests"), directoryHint: .isDirectory)
    private let queue = DispatchQueue(label: "SettingsItemsMirrorTests")
    private var reported = [Demand]()

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private var store: MenuBarItemImageCacheDiskStore {
        MenuBarItemImageCacheDiskStore(cachesDirectory: directory, queue: queue)
    }

    private func mirror(_ appState: AppState, showsPane: @escaping (String) -> Bool = { _ in true }) -> SettingsItemsMirror {
        SettingsItemsMirror(appState: appState, pictureFile: store.cacheFileURL, showsPane: showsPane) { [weak self] in
            self?.reported.append($0)
        }
    }

    @Test("The app's item list and bar colours replace this process's own")
    func itemListAndColours() throws {
        let appState = AppState()
        let feature = SettingsChildFeature.items(mirror: mirror(appState))
        var cache = MenuBarItemCache(displayID: 3)
        cache[.hidden] = [Fixture.item("Clock")]
        try feature.statuses[SettingsItemsLink.cache]?(Fixture.payload(cache))
        feature.statuses[SettingsItemsLink.cache]?(Data("not an item list".utf8))
        #expect(appState.itemManager.itemCache == cache)
        #expect(appState.itemManager.managedItems(for: .hidden).map(\.tag) == [Fixture.tag("Clock", windowID: 5)])

        let bar = MenuBarAverageColorInfo(color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), source: .menuBarWindow)
        var colors = SettingsBarColors()
        colors.averages[4] = SettingsBarColors.Sample(bar)
        colors.active = SettingsBarColors.Sample(bar)
        colors.palettes[4] = WallpaperPalette(swatches: [WallpaperPalette.Swatch(red: 0.1, green: 0.2, blue: 0.3, weight: 1)])
        try feature.statuses[SettingsItemsLink.colors]?(Fixture.payload(colors))
        #expect(appState.menuBarManager.averageColors == [4: bar])
        #expect(appState.menuBarManager.averageColorInfo == bar)
        #expect(appState.menuBarManager.wallpaperPalettes == colors.palettes)
        #expect(SettingsBarColors(appState.menuBarManager.wallpaperColorMonitor) == colors)
    }

    @Test("The pictures the app names are read from its file, which is only ever read")
    func pictures() async throws {
        let appState = AppState()
        let feature = SettingsChildFeature.items(mirror: mirror(appState))
        let imageCache = appState.imageCache
        #expect(imageCache.hasLoadedFromDisk, "This process never reads the file by itself")
        let (clock, wifi, unsaved) = (Fixture.tag("Clock", windowID: 5), Fixture.tag("Wi-Fi"), Fixture.tag("Unsaved"))
        let url = try #require(store.cacheFileURL)
        let store = store
        try store.enqueueSave([clock: Fixture.capture(width: 20), wifi: Fixture.capture(width: 30)])
        queue.sync {}
        let slot = imageCache.glyphSlot(for: clock)

        func show(_ revision: Int, _ tags: [MenuBarItemTag]) throws {
            try feature.statuses[SettingsItemsLink.pictures]?(Fixture.payload(SettingsItemPictures(revision: revision, tags: tags)))
        }
        try show(1, [clock, unsaved])
        #expect(Set(imageCache.capturesByTag.keys) == [clock], "Only what the app names and the file holds")
        #expect(imageCache.image(for: clock)?.cgImage.width == 20)
        #expect(await settingsLinkWait { slot.capture?.cgImage.width == 20 })

        let shown = imageCache.capturesByTag[clock]?.cgImage
        try show(2, [clock, wifi])
        #expect(imageCache.capturesByTag[clock]?.cgImage === shown, "An unchanged picture is not decoded again")
        #expect(imageCache.capturesByTag[wifi]?.cgImage.width == 30)

        try store.enqueueSave([clock: Fixture.capture(width: 40)])
        queue.sync {}
        try show(3, [clock, wifi])
        #expect(imageCache.capturesByTag.mapValues(\.cgImage.width) == [clock: 40])
        try show(4, [])
        #expect(imageCache.capturesByTag.isEmpty)
        #expect(MenuBarItemImageCacheDiskStore.savedPictures(at: url)?.count == 1)

        // Another build's file is not shown, and is left for the app to deal with.
        var root = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        root["build"] = "another build"
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: url)
        #expect((MenuBarItemImageCacheDiskStore.savedPictures(at: url) == nil) == (ImageCacheFileValidity.appBuild != nil))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(MenuBarItemImageCacheDiskStore.savedPictures(at: directory.appending(path: "missing")) == nil)
    }

    @Test("The page shown asks for what the same page in the app would capture")
    func demand() {
        let appState = AppState()
        let navigation = appState.navigationState
        defer { navigation.isSettingsPresented = false }
        navigation.isSimpleModeSettings = false
        let mirror = mirror(appState) { $0 != SettingsNavigationIdentifier.menuBarLayout.rawValue }

        navigation.settingsNavigationIdentifier = .thawBar
        #expect(mirror.demand == .none, "No window, nothing to capture for")
        navigation.isSettingsPresented = true
        #expect(mirror.demand == Demand(consumesCapture: true, scope: .allSections, isFrontmost: false, showsPictures: true))
        navigation.isAppFrontmost = true
        #expect(mirror.demand == Demand(consumesCapture: true, scope: .allSections, isFrontmost: true, showsPictures: true))

        navigation.settingsNavigationIdentifier = .hotkeys
        #expect(mirror.demand == Demand(consumesCapture: true, scope: .none, isFrontmost: true, showsPictures: true))
        appState.imageCache.isItemHotkeyListExpanded = true
        #expect(mirror.demand == Demand(consumesCapture: true, scope: .allSections, isFrontmost: true, showsPictures: true, needsEveryPicture: true))
        appState.imageCache.isItemHotkeyListExpanded = false

        navigation.settingsNavigationIdentifier = .profiles
        #expect(mirror.demand == Demand(isFrontmost: true, showsPictures: true), "Pictures without capture")
        navigation.settingsNavigationIdentifier = .general
        #expect(mirror.demand == Demand(isFrontmost: true))
        navigation.settingsNavigationIdentifier = .triggers
        #expect(mirror.demand == Demand(isFrontmost: true), "A page that lists names draws no pictures")
        navigation.settingsNavigationIdentifier = .menuBarAppearance
        #expect(mirror.demand == Demand(consumesCapture: true, scope: .none, isFrontmost: true), "Colours are sampled, pictures are not readied")
        navigation.settingsNavigationIdentifier = .menuBarLayout
        #expect(mirror.demand == .none, "A pane handed to the app is the app's to capture for")
    }

    @Test("The app hears what the page needs once it says hello, and again when that changes")
    func reporting() async {
        let appState = AppState()
        let navigation = appState.navigationState
        defer { navigation.isSettingsPresented = false }
        navigation.isSimpleModeSettings = false
        navigation.settingsNavigationIdentifier = .general
        let feature = SettingsChildFeature.items(mirror: mirror(appState))
        for _ in 0 ..< 3 {
            await mainActorQueueDrained()
        }
        #expect(reported.isEmpty, "Nothing is sent before the link is known to be up")

        feature.statuses[SettingsItemsLink.hello]?(Data())
        #expect(await settingsLinkWait { reported == [.none] })
        navigation.settingsNavigationIdentifier = .thawBar
        navigation.isSettingsPresented = true
        let behind = Demand(consumesCapture: true, scope: .allSections, isFrontmost: false, showsPictures: true)
        #expect(await settingsLinkWait { reported.last == behind })

        feature.statuses[SettingsItemsLink.hello]?(Data())
        navigation.isAppFrontmost = true
        #expect(await settingsLinkWait { reported.last?.isFrontmost == true })
        #expect(reported.count == 3, "Each need is reported once, by one watcher")
    }

    @Test("Over the link, the settings process answers the app's hello and is then sent the item list")
    func handshake() async {
        let fake = FakeApp()
        fake.cache[.visible] = [Fixture.item("Clock")]
        let relay = SettingsItemsRelay(app: fake.app, pace: SettingsItemsRelay.Pace(items: .milliseconds(1)))
        let (toChild, fromChild) = (Pipe(), Pipe())
        let host = SettingsProcessHost(
            app: SettingsProcessHost.AppSide(
                reloadSettings: {}, openInApp: { _ in }, pageChanged: { _ in }, checkForUpdates: {}, quit: {},
                updatesState: { .updatesState(canCheck: false, lastCheck: nil) },
                features: [.items(relay: relay) { SettingsBarColors() }]
            ),
            isEnabled: { true },
            launch: { _, _ in
                SettingsProcessHost.Child(
                    processIdentifier: -1, isRunning: { true },
                    fromChild: fromChild.fileHandleForReading, toChild: toChild.fileHandleForWriting
                )
            }
        )
        #expect(host.show(pane: "General", simpleMode: false))

        let appState = AppState()
        var session: SettingsProcessSession?
        let mirror = SettingsItemsMirror(appState: appState, pictureFile: nil) { demand in
            SettingsLinkPayload.encode(demand).map { session?.send(.command(name: SettingsItemsLink.listen, payload: $0)) }
        }
        session = SettingsProcessSession(
            navigationState: appState.navigationState,
            side: SettingsProcessSession.ProcessSide(
                reloadSettings: {}, showSettings: {}, updatesStateChanged: { _, _ in }, terminate: {},
                features: [.items(mirror: mirror)]
            )
        )
        #expect(fake.demands.isEmpty)
        session?.start(input: toChild.fileHandleForReading, output: fromChild.fileHandleForWriting, onClose: {})
        #expect(await settingsLinkWait { appState.itemManager.itemCache == fake.cache })
        #expect(fake.demands.first == Demand.none)
        #expect(relay.isListening)
    }

    @Test("In the app, a page in the settings process counts as one of its own")
    func appCapturesForThePage() {
        let cache = MenuBarItemImageCache()
        let closed = MenuBarItemImageCache.NavigationStateSnapshot(
            isThawBarPresented: false, isSearchPresented: false, isAppFrontmost: false, isSettingsPresented: false,
            settingsNavigationIdentifier: .general, isItemHotkeyListExpanded: false, isSimpleModeSettings: false
        )
        let inFront = closed.including(Demand(consumesCapture: true, scope: .allSections, isFrontmost: true))
        #expect(inFront.liveCaptureScope == .allSections)
        let behind = closed.including(Demand(consumesCapture: true, scope: .allSections, isFrontmost: false))
        #expect(behind.liveCaptureScope == .none, "The pictures rest while the settings process is behind another app")
        #expect(cache.hasUnfocusedCaptureConsumer(nav: behind), "but are kept, since its page still draws them")
        #expect(!cache.hasUnfocusedCaptureConsumer(nav: closed))

        let appState = AppState()
        let app = SettingsItemsRelay.App.live(appState)
        #expect(!appState.navigationState.hasVisibleCaptureUI)
        app.setCaptureDemand(Demand(consumesCapture: true))
        #expect(appState.navigationState.hasVisibleCaptureUI)
        app.setCaptureDemand(.none)
        #expect(!appState.navigationState.hasVisibleCaptureUI)
        var items = MenuBarItemCache(displayID: 3)
        items[.visible] = [Fixture.item("Clock")]
        appState.itemManager.itemCache = items
        #expect(app.itemCache() == items)
        #expect(app.captures().isEmpty)
    }
}
