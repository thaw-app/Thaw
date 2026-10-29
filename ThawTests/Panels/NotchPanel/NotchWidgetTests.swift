//
//  NotchWidgetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// Menu bar items for the descender tests, on window IDs no real window uses.
@MainActor
enum NotchFixtures {
    static func item(
        bundleID: String,
        title: String,
        bounds: CGRect = CGRect(x: 600, y: 0, width: 24, height: 24)
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, instanceIndex: 0),
            windowID: 0xFFFF_FF00,
            ownerPID: 0,
            sourcePID: 0,
            bounds: bounds,
            title: title,
            isOnScreen: true
        )
    }

    static func clockItem() -> MenuBarItem {
        item(bundleID: "com.apple.controlcenter", title: "Clock")
    }
}

/// A widget whose answers the test sets, recording what the registry asks of it.
@MainActor
private final class StubWidget: NotchWidget {
    let id: String
    var matchesItems: Bool
    var available: Bool
    var preparedTitles = [String]()
    var refreshCount = 0
    let refreshPolicy: NotchWidgetRefreshPolicy
    let bodySize = CGSize(width: 100, height: 40)

    init(id: String, matches: Bool, available: Bool, policy: NotchWidgetRefreshPolicy = .onDemand) {
        self.id = id
        self.matchesItems = matches
        self.available = available
        self.refreshPolicy = policy
    }

    func matches(_: MenuBarItem) -> Bool {
        matchesItems
    }

    func prepare(for item: MenuBarItem) {
        preparedTitles.append(item.tag.title)
    }

    func isAvailable() -> Bool {
        available
    }

    var body: AnyView {
        AnyView(Color.red)
    }

    func refresh() {
        refreshCount += 1
    }
}

/// A widget that keeps the protocol's default prepare(for:).
@MainActor
private final class DefaultPrepareWidget: NotchWidget {
    let id = "default"
    let refreshPolicy = NotchWidgetRefreshPolicy.onDemand
    let bodySize = CGSize.zero

    func matches(_: MenuBarItem) -> Bool {
        true
    }

    func isAvailable() -> Bool {
        true
    }

    var body: AnyView {
        AnyView(EmptyView())
    }

    func refresh() { /* Nothing to refresh in this stub. */ }
}

@Suite("Notch widget registry")
@MainActor
struct NotchWidgetRegistryTests {
    @Test("The first matching widget that is available wins, in registry order")
    func firstAvailableWins() {
        let unmatched = StubWidget(id: "a", matches: false, available: true)
        let unavailable = StubWidget(id: "b", matches: true, available: false)
        let chosen = StubWidget(id: "c", matches: true, available: true)
        let shadowed = StubWidget(id: "d", matches: true, available: true)
        let registry = NotchWidgetRegistry(widgets: [unmatched, unavailable, chosen, shadowed])

        let widget = registry.widget(for: NotchFixtures.item(bundleID: "com.example", title: "Thing"))
        #expect(widget?.id == "c")
        #expect(unmatched.preparedTitles.isEmpty, "an unmatched widget is never prepared")
        #expect(unavailable.preparedTitles == ["Thing"])
        #expect(chosen.preparedTitles == ["Thing"])
        #expect(shadowed.preparedTitles.isEmpty, "lookup stops at the first available widget")
    }

    @Test("No widget is returned when none is available")
    func noneAvailable() {
        let registry = NotchWidgetRegistry(widgets: [StubWidget(id: "a", matches: true, available: false)])
        #expect(registry.widget(for: NotchFixtures.clockItem()) == nil)
        #expect(NotchWidgetRegistry(widgets: []).widget(for: NotchFixtures.clockItem()) == nil)
    }

    @Test("The default prepare step leaves a widget available")
    func defaultPrepare() {
        let registry = NotchWidgetRegistry(widgets: [DefaultPrepareWidget()])
        #expect(registry.widget(for: NotchFixtures.clockItem())?.id == "default")
    }
}

@Suite("Notch panel model")
@MainActor
struct NotchPanelModelTests {
    private func presentation(_ widget: any NotchWidget, id: String) -> NotchPresentation {
        NotchPresentation(
            id: id,
            widget: widget,
            itemWindowID: 1,
            bodySize: widget.bodySize,
            bodyOffset: 0,
            panelFrame: CGRect(x: 0, y: 0, width: 200, height: 80)
        )
    }

    @Test("Staging a new presentation retracts, staging the same one again is ignored")
    func staging() {
        let model = NotchPanelModel()
        let widget = StubWidget(id: "w", matches: true, available: true)
        model.stage(presentation(widget, id: "one"))
        model.setRevealed(true)
        #expect(model.isRevealed)

        model.stage(presentation(widget, id: "one"))
        #expect(model.isRevealed, "the same presentation keeps the reveal")

        model.stage(presentation(widget, id: "two"))
        #expect(model.presentation?.id == "two")
        #expect(!model.isRevealed)

        model.stage(nil)
        #expect(model.presentation == nil)
    }

    @Test("Revealing refreshes only widgets that refresh while revealed")
    func revealRefreshPolicy() {
        let model = NotchPanelModel()
        let live = StubWidget(id: "live", matches: true, available: true, policy: .whileRevealed)
        model.stage(presentation(live, id: "live"))
        model.setRevealed(true)
        model.setRevealed(true)
        #expect(live.refreshCount == 1, "a repeated reveal is a no-op")
        model.setRevealed(false)
        #expect(live.refreshCount == 1, "retracting does not refresh")

        let onDemand = StubWidget(id: "demand", matches: true, available: true, policy: .onDemand)
        model.stage(presentation(onDemand, id: "demand"))
        model.setRevealed(true)
        #expect(onDemand.refreshCount == 0)
    }

    @Test("Revealing with nothing staged changes only the flag")
    func revealWithoutPresentation() {
        let model = NotchPanelModel()
        model.setRevealed(true)
        #expect(model.isRevealed)
        #expect(model.presentation == nil)
    }
}

@Suite("Notch anchor placement")
@MainActor
struct NotchAnchorTests {
    private let widget = StubWidget(id: "w", matches: true, available: true)

    @Test("A body under an item mid-screen hangs centred under it")
    func centredUnderItem() throws {
        let screen = try #require(NSScreen.screens.first)
        let itemBounds = CGRect(x: screen.frame.midX - 12, y: 0, width: 24, height: 24)
        let item = NotchFixtures.item(bundleID: "com.example", title: "Thing", bounds: itemBounds)
        let presentation = try #require(NotchAnchor.present(widget: widget, for: item, on: screen))

        let panelWidth = widget.bodySize.width + NotchMetrics.horizontalSlack * 2
        #expect(presentation.panelFrame.width == panelWidth)
        #expect(presentation.panelFrame.height == widget.bodySize.height + NotchMetrics.shoulderRadius + NotchMetrics.shadowSlack)
        #expect(abs(presentation.panelFrame.midX - itemBounds.midX) < 0.001)
        #expect(presentation.bodyOffset == 0)
        #expect(presentation.panelFrame.maxY <= screen.frame.maxY)
        #expect(presentation.id == "w-\(item.windowID)")
        #expect(presentation.itemWindowID == item.windowID)
    }

    @Test("At the screen's edge the panel is pushed inward and the body slides toward the item")
    func pushedInwardAtEdge() throws {
        let screen = try #require(NSScreen.screens.first)
        let itemBounds = CGRect(x: screen.frame.maxX - 10, y: 0, width: 10, height: 24)
        let item = NotchFixtures.item(bundleID: "com.example", title: "Thing", bounds: itemBounds)
        let presentation = try #require(NotchAnchor.present(widget: widget, for: item, on: screen))

        #expect(presentation.panelFrame.maxX == screen.frame.maxX)
        let limit = presentation.panelFrame.width / 2 - widget.bodySize.width / 2 - NotchMetrics.shoulderRadius
        #expect(presentation.bodyOffset == limit, "the offset is clamped so a shoulder stays on the panel")
    }

    @Test("An item with no width cannot be measured")
    func zeroWidthItem() throws {
        let screen = try #require(NSScreen.screens.first)
        let item = NotchFixtures.item(bundleID: "com.example", title: "Thing", bounds: .zero)
        #expect(NotchAnchor.present(widget: widget, for: item, on: screen) == nil)
    }
}

@Suite("Notch clock widget")
@MainActor
struct NotchClockWidgetTests {
    @Test("Only Control Center's clock module matches")
    func matching() {
        let widget = NotchClockWidget()
        #expect(widget.matches(NotchFixtures.clockItem()))
        #expect(!widget.matches(NotchFixtures.item(bundleID: "com.apple.controlcenter", title: "WiFi")))
        #expect(!widget.matches(NotchFixtures.item(bundleID: "com.example.clock", title: "Clock")))
        #expect(widget.isAvailable())
        #expect(widget.refreshPolicy == .whileRevealed)
    }

    @Test("Refreshing moves the shown time forward and the body draws")
    func refreshAndDraw() throws {
        let widget = NotchClockWidget()
        let before = widget.now
        widget.refresh()
        #expect(widget.now >= before)
        let render = OffscreenRender(widget.body.frame(width: widget.bodySize.width, height: widget.bodySize.height), size: widget.bodySize)
        #expect(try render.pixels().contains { $0 != 0 })
    }
}

@Suite("Notch media widget")
@MainActor
struct NotchMediaWidgetTests {
    @Test("Spotify and Music items match, other items do not")
    func matching() {
        let widget = NotchMediaWidget()
        #expect(widget.matches(NotchFixtures.item(bundleID: "com.spotify.client", title: "Spotify")))
        #expect(widget.matches(NotchFixtures.item(bundleID: "com.apple.Music", title: "Music")))
        #expect(!widget.matches(NotchFixtures.item(bundleID: "com.example", title: "Music")))
    }

    @Test("Preparing for a supported item makes the widget available, an unsupported one does not")
    func availability() {
        let widget = NotchMediaWidget()
        #expect(!widget.isAvailable())
        widget.prepare(for: NotchFixtures.item(bundleID: "com.spotify.client", title: "Spotify"))
        #expect(widget.isAvailable())
        widget.prepare(for: NotchFixtures.item(bundleID: "com.example", title: "Other"))
        #expect(!widget.isAvailable())
    }

    @Test("Without a player, refreshing clears the track and the body still draws")
    func refreshWithoutPlayer() throws {
        let widget = NotchMediaWidget()
        widget.refresh()
        #expect(widget.trackTitle == nil)
        #expect(widget.trackArtist == nil)
        #expect(!widget.isPlaying)
        let render = OffscreenRender(widget.body.frame(width: widget.bodySize.width, height: widget.bodySize.height), size: widget.bodySize)
        #expect(try render.pixels().contains { $0 != 0 })
    }
}

@Suite("Notch accessory widget")
@MainActor
struct NotchAccessoryWidgetTests {
    @Test("Third-party items match, Thaw's own items do not")
    func matching() {
        let widget = NotchAccessoryWidget()
        #expect(widget.matches(NotchFixtures.item(bundleID: "com.example.weather", title: "Weather")))
        #expect(!widget.matches(NotchFixtures.item(bundleID: ThawMenuBarIdentity.bundleIdentifier, title: "Thaw")))
        #expect(widget.refreshPolicy == .onDemand)
    }

    @Test("An item with no width reads nothing, so the widget is unavailable and stays narrow")
    func unmeasurableItem() throws {
        let widget = NotchAccessoryWidget()
        widget.prepare(for: NotchFixtures.item(bundleID: "com.example.weather", title: "Weather", bounds: .zero))
        #expect(!widget.isAvailable())
        #expect(widget.detail == nil)
        #expect(widget.secondary == nil)
        #expect(widget.symbolName == nil)
        #expect(widget.bodySize == CGSize(width: 96, height: 34), "an empty readout clamps to the minimum width")
        widget.refresh()
        #expect(!widget.isAvailable())
        let render = OffscreenRender(widget.body.frame(width: 96, height: 34), size: CGSize(width: 96, height: 34))
        _ = try render.pixels()
    }

    @Test("A weather readout gets the glyph for the condition it names, an unknown one gets none")
    func accessorySymbols() {
        #expect(NotchAccessoryWidget.symbol(for: "Thunderstorms likely") == "cloud.bolt.fill")
        #expect(NotchAccessoryWidget.symbol(for: "Partly Cloudy") == "cloud.sun.fill")
        #expect(NotchAccessoryWidget.symbol(for: "Overcast") == "cloud.fill")
        #expect(NotchAccessoryWidget.symbol(for: "Light rain") == "cloud.rain.fill")
        #expect(NotchAccessoryWidget.symbol(for: "SUNNY") == "sun.max.fill")
        #expect(NotchAccessoryWidget.symbol(for: "Battery 80%") == nil)
    }
}

@Suite("Notch silhouette")
struct NotchShapeTests {
    private func shape(height: CGFloat, offset: CGFloat = 0) -> NotchShape {
        NotchShape(bodyWidth: 100, bodyOffset: offset, bodyHeight: height, shoulderRadius: 10, bottomRadius: 12)
    }

    @Test("A body under a hairline draws nothing")
    func collapsed() {
        #expect(shape(height: 0.4).path(in: CGRect(x: 0, y: 0, width: 200, height: 80)).isEmpty)
        #expect(shape(height: -5).path(in: CGRect(x: 0, y: 0, width: 200, height: 80)).isEmpty)
    }

    @Test("A descended body spans the body plus both flares and hangs to its height")
    func descended() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let bounds = shape(height: 40).path(in: rect).boundingRect
        // Flares reach 24 points past the 100-point body on each side.
        #expect(abs(bounds.minX - 26) < 0.5)
        #expect(abs(bounds.maxX - 174) < 0.5)
        #expect(bounds.minY == 0)
        #expect(abs(bounds.maxY - 40) < 0.5)
    }

    @Test("The body height is clamped to the rect and a flare collapses against the panel's edge")
    func clampedAndOffset() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 30)
        let bounds = shape(height: 500, offset: 50).path(in: rect).boundingRect
        #expect(abs(bounds.maxY - 30) < 0.5)
        #expect(bounds.maxX <= 200.5, "the right flare has no room past the panel")
    }

    @Test("Insetting moves the top edge down with the rect")
    func inset() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let inset = shape(height: 40).inset(by: 4).path(in: rect).boundingRect
        #expect(inset.minY == 4)
        #expect(abs(inset.maxY - 44) < 0.5)
    }
}

@Suite("Notch panel and content", .serialized)
@MainActor
struct NotchPanelTests {
    private func presentation(widget: any NotchWidget) -> NotchPresentation {
        NotchPresentation(
            id: "p",
            widget: widget,
            itemWindowID: 1,
            bodySize: widget.bodySize,
            bodyOffset: 10,
            panelFrame: CGRect(x: 100, y: 200, width: widget.bodySize.width + 64, height: widget.bodySize.height + 24)
        )
    }

    @Test("Applying a presentation sizes the panel and limits clicks to the body")
    func applySetsFrameAndHitRegion() throws {
        let model = NotchPanelModel()
        let panel = NotchPanel(content: NotchContentView(model: model))
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.hasShadow)
        #expect(panel.level == .mainMenu + 1)

        let widget = NotchClockWidget()
        let presentation = presentation(widget: widget)
        panel.apply(presentation)
        #expect(panel.frame == presentation.panelFrame)

        let hosting = try #require(panel.hostingView)
        #expect(hosting.frame.size == presentation.panelFrame.size)
        let region = hosting.hitRegion()
        #expect(region.width == widget.bodySize.width)
        #expect(region.minY == NotchMetrics.shadowSlack)
        #expect(region.midX == presentation.panelFrame.width / 2 + 10)

        // A point in the shoulder surround passes through to the windows below.
        #expect(hosting.hitTest(CGPoint(x: 1, y: 1)) == nil)
    }

    @Test("A fresh hosting view takes no clicks anywhere")
    func defaultHitRegion() {
        let hosting = NotchHostingView(rootView: NotchContentView(model: NotchPanelModel()))
        hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(hosting.hitRegion() == .zero)
        #expect(hosting.hitTest(CGPoint(x: 50, y: 50)) == nil)
    }

    @Test("The content draws the staged body once revealed")
    func contentDrawsWhenRevealed() async throws {
        let model = NotchPanelModel()
        let widget = NotchClockWidget()
        let presentation = presentation(widget: widget)
        let render = OffscreenRender(NotchContentView(model: model), size: presentation.panelFrame.size)
        let empty = try render.pixels()

        model.stage(presentation)
        model.setRevealed(true)
        await render.settle { (try? render.pixels()) != empty }
        #expect(try render.pixels() != empty)
        model.setRevealed(false)
        #expect(!model.isRevealed)
    }
}

@Suite("Notch panel controller", .timeLimit(.minutes(1)))
@MainActor
struct NotchPanelControllerTests {
    @Test("A display invalidation with nothing showing leaves the model untouched")
    func invalidationWithNothingShowing() async {
        let model = NotchPanelModel()
        let controller = NotchPanelController(model: model)
        let invalidations = PassthroughSubject<Void, Never>()
        controller.observeDisplayInvalidations(invalidations)
        invalidations.send()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.presentation == nil)
        #expect(!model.isRevealed)
    }

    @Test("A display invalidation retracts a showing descender")
    func invalidationRetracts() async {
        let model = NotchPanelModel()
        let controller = NotchPanelController(model: model)
        let widget = NotchClockWidget()
        model.stage(NotchPresentation(
            id: "p",
            widget: widget,
            itemWindowID: 1,
            bodySize: widget.bodySize,
            bodyOffset: 0,
            panelFrame: CGRect(x: 0, y: 0, width: 250, height: 90)
        ))
        model.setRevealed(true)
        let invalidations = PassthroughSubject<Void, Never>()
        controller.observeDisplayInvalidations(invalidations)
        invalidations.send()

        // The retract is debounced on the main queue and then waits out the animation, so a busy run is slow, not wrong.
        await waitUntil({ model.presentation == nil }, wakingOn: model.$presentation.dropFirst())
        #expect(!model.isRevealed)
        #expect(model.presentation == nil)
    }
}
