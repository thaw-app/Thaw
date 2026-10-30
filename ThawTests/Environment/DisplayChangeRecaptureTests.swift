//
//  DisplayChangeRecaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

@MainActor
@Suite("Display change recapture", .timeLimit(.minutes(1)), .scratchDefaults)
struct DisplayChangeRecaptureTests {
    private let imageCache = RecordingImageCache()
    private let effects: MenuBarDisplayChangeEffects

    init() {
        let manager = MenuBarItemManager()
        effects = MenuBarDisplayChangeEffects(
            itemManager: manager,
            repairs: manager.repairs,
            imageCache: imageCache,
            displaySettings: DisplaySettingsManager(),
            profiles: ProfileManager(),
            presentationMonitor: PresentationMonitor(),
            menuBarManager: MenuBarManager()
        )
    }

    @Test("The recapture step asks the image cache for one recapture")
    func recaptureAsksOnce() async {
        await effects.recaptureImages()

        #expect(imageCache.calls == [.recapture])
    }

    @Test("Cleaning a removed display's images leaves the recapture to the next step")
    func cleanupDoesNotRecapture() async {
        await effects.cleanImagesAfterRemoval()

        #expect(imageCache.calls == [.cleanup])
    }

    @Test("A removed display cleans, then recaptures once")
    func removalCleansThenRecapturesOnce() async {
        await effects.cleanImagesAfterRemoval()
        await effects.recaptureImages()

        #expect(imageCache.calls == [.cleanup, .recapture])
    }
}

/// The postings go to a private center, since the default one would reach the app hosting the tests.
@MainActor
@Suite("Image recapture triggers", .scratchDefaults)
struct ImageRecaptureTriggersTests {
    @Test("A screen-parameters posting no longer asks the image cache for a recapture")
    func ignoresScreenParameters() {
        let center = NotificationCenter()
        var sends = 0
        let cancellable = ImageRecaptureTriggers.changes(
            itemCacheChanges: PassthroughSubject<Void, Never>(),
            center: center
        )
        .sink { sends += 1 }
        defer { cancellable.cancel() }

        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(sends == 0)
    }

    @Test("A Space change and an item-cache change each still ask once")
    func keepsSpaceAndItemCache() {
        let center = NotificationCenter()
        let itemCacheChanges = PassthroughSubject<Void, Never>()
        var sends = 0
        let cancellable = ImageRecaptureTriggers.changes(itemCacheChanges: itemCacheChanges, center: center)
            .sink { sends += 1 }
        defer { cancellable.cancel() }

        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(sends == 1)
        itemCacheChanges.send()
        #expect(sends == 2)
    }
}

@MainActor
private final class RecordingImageCache: DisplayChangeImageCache {
    enum Call: Equatable {
        case cleanup
        case recapture
    }

    private(set) var calls: [Call] = []

    func performCacheCleanup() {
        calls.append(.cleanup)
    }

    func recaptureForCurrentConsumers() async {
        calls.append(.recapture)
    }
}
