//
//  LayoutBarSmallViewsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// The layout bar's notch marker, opaque slots, new items badge, feedback and refusal copy, drawn off screen.
@MainActor
@Suite("Layout bar small views", .serialized)
struct LayoutBarSmallViewsTests {
    private typealias World = LayoutEditorWorld

    private static let dark = MenuBarAverageColorInfo(color: CGColor(gray: 0.05, alpha: 1), source: .menuBarWindow)
    private static let bright = MenuBarAverageColorInfo(color: CGColor(gray: 0.95, alpha: 1), source: .menuBarWindow)

    private func pixels(of view: NSView, size: CGSize) throws -> Data {
        view.frame = CGRect(origin: .zero, size: size)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    // MARK: Group refusal copy

    @Test("Each group refusal names its own reason, and one missing member reads in the singular")
    func groupRefusalReasons() {
        let item = World.item("Alpha")
        let reasons = [
            GroupMoveRefusal.protectedMember(item: item),
            .hidingUnsupported(item: item),
            .notHideable(item: item),
            .hidingUnavailable,
            .unresolvedMembers(missingCount: 1),
            .unresolvedMembers(missingCount: 3),
        ].map(\.localizedReason)
        #expect(Set(reasons).count == reasons.count)
        #expect(reasons[0].contains(item.displayName))
        #expect(reasons[5].contains("3"))
        #expect(!reasons[4].contains("1 items"))
    }

    // MARK: Feedback

    @Test("Each refusal builder writes its own message, and posting then clearing empties the centre")
    func feedbackBuilders() {
        let refusals = [
            LayoutBarFeedbackCenter.blockedGroupMove(groupName: "Tools", section: .hidden, refusal: .hidingUnavailable),
            LayoutBarFeedbackCenter.systemItemHidingDisabled(itemName: "Weather", section: .hidden),
            LayoutBarFeedbackCenter.itemCannotMove(itemName: "Clock", section: .hidden),
            LayoutBarFeedbackCenter.itemNotMovable(itemName: "Clock"),
            LayoutBarFeedbackCenter.ownerUnresponsive(itemName: "Stuck"),
            LayoutBarFeedbackCenter.manualSectionChange(),
            LayoutBarFeedbackCenter.groupRegatherIncomplete(groupName: "Tools", section: .visible),
        ]
        #expect(Set(refusals.map(\.title)).count >= 5)
        #expect(refusals[0].title.contains("Tools"))
        #expect(refusals[0].message.contains(GroupMoveRefusal.hidingUnavailable.localizedReason))
        #expect(refusals[4].message != refusals[3].message, "an unresponsive app is explained differently")
        #expect(refusals[0] != refusals[1], "every refusal is its own value")

        let center = LayoutBarFeedbackCenter()
        center.post(refusals[2])
        #expect(center.refusal == refusals[2])
        center.post(refusals[3])
        #expect(center.refusal == refusals[3], "a newer refusal replaces the one showing")
        center.clear()
        #expect(center.refusal == nil)
    }

    // MARK: Notch marker

    @Test("The notch marker ignores the pointer and draws dark ink on a bright bar")
    func notchMarker() throws {
        let view = NotchIndicatorView(averageColorInfo: Self.dark)
        #expect(view.hitTest(.zero) == nil)
        #expect(!view.isAccessibilityElement())
        let size = CGSize(width: 180, height: 24)
        let onDark = try pixels(of: view, size: size)
        view.averageColorInfo = Self.bright
        let onBright = try pixels(of: view, size: size)
        view.averageColorInfo = nil
        view.viewDidChangeEffectiveAppearance()
        let unsampled = try pixels(of: view, size: size)
        #expect(onDark != onBright)
        #expect(unsampled.contains { $0 != 0 })
        #expect(try !pixels(of: view, size: CGSize(width: 4, height: 4)).contains { $0 != 0 }, "a marker too small for its inset draws nothing")
    }

    // MARK: Opaque slots

    /// A running app as the opaque slot sees it.
    private struct FakeApplication: LayoutOpaqueSlotApplication {
        let bundleIdentifier: String?
        let icon: NSImage?
    }

    @Test("A governable extra is keyed by its menu extra title and named for people")
    func governableExtra() {
        let slot = LayoutOpaqueSlotDescriptor.governableExtra(menuExtraTitle: "com.apple.menuextra.wifi", displayName: "Wi‑Fi")
        #expect(slot.runtimePositionKey == "governable:com.apple.menuextra.wifi")
        #expect(slot.bundleIdentifier == "com.apple.controlcenter")
        #expect(slot.captureTag == MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi"))
        #expect(slot.tooltip.contains("Wi‑Fi"))
        #expect(slot.accessibilityLabel.contains("Wi‑Fi"))

        let titles = [
            "com.apple.menuextra.airdrop", "com.apple.menuextra.bluetooth", "com.apple.menuextra.wifi",
            "com.apple.menuextra.now-playing", "com.apple.menuextra.user", "com.apple.menuextra.focusmode",
        ]
        let names = titles.map(LayoutOpaqueSlotDescriptor.governableExtraDisplayName(forMenuExtraTitle:))
        #expect(Set(names).count == titles.count)
        #expect(!names.contains { $0.hasPrefix("com.apple") })
        #expect(LayoutOpaqueSlotDescriptor.governableExtraDisplayName(forMenuExtraTitle: "com.example.other") == "com.example.other")
    }

    @Test("A captured image wins over the owning app's icon, which wins over nothing")
    func preferredIcon() {
        let captured = NSImage(size: NSSize(width: 1, height: 1))
        let appIcon = NSImage(size: NSSize(width: 2, height: 2))
        let apps = [FakeApplication(bundleIdentifier: "com.example.other", icon: nil), FakeApplication(bundleIdentifier: "com.example.app", icon: appIcon)]
        #expect(LayoutOpaqueSlotDescriptor.preferredIcon(capturedImage: captured, bundleIdentifier: "com.example.app", applications: apps) === captured)
        #expect(LayoutOpaqueSlotDescriptor.preferredIcon(capturedImage: nil, bundleIdentifier: "com.example.app", applications: apps) === appIcon)
        #expect(LayoutOpaqueSlotDescriptor.appIcon(bundleIdentifier: "com.example.missing", applications: apps) == nil)
    }

    @Test("An opaque slot is a disabled image that draws an icon and a badge")
    func opaqueSlotView() throws {
        let slot = LayoutOpaqueSlotDescriptor.governableExtra(menuExtraTitle: "com.apple.menuextra.airdrop", displayName: "AirDrop")
        let fallback = LayoutOpaqueSlotView(descriptor: slot, runningApplications: [])
        let captured = LayoutOpaqueSlotView(
            descriptor: slot,
            runningApplications: [],
            capturedImage: NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)
        )
        #expect(!fallback.isEnabled)
        #expect(fallback.accessibilityRole() == .image)
        #expect(fallback.accessibilityLabel() == slot.accessibilityLabel)
        if case let .opaqueSlot(descriptor) = fallback.kind {
            #expect(descriptor == slot)
        } else {
            Issue.record("an opaque slot reports its descriptor")
        }
        #expect(!fallback.isNewItemsBadge)
        let size = CGSize(width: 32, height: 32)
        let fallbackPixels = try pixels(of: fallback, size: size)
        let capturedPixels = try pixels(of: captured, size: size)
        #expect(fallbackPixels.contains { $0 != 0 })
        #expect(fallbackPixels != capturedPixels)

        fallback.updateTrackingAreas()
        fallback.updateTrackingAreas()
        #expect(fallback.trackingAreas.count == 1)
    }

    // MARK: New items badge

    @Test("The new items badge is sized by its title, inks for the bar and hides while it is being dragged")
    func newItemsBadge() throws {
        let badge = LayoutBarNewItemsBadgeView()
        #expect(badge.isNewItemsBadge)
        #expect(badge.frame.height == 24)
        #expect(badge.frame.width > 20)
        let size = badge.frame.size
        badge.averageColorInfo = Self.dark
        let onDark = try pixels(of: badge, size: size)
        badge.averageColorInfo = Self.bright
        let onBright = try pixels(of: badge, size: size)
        #expect(onDark != onBright)
        #expect(badge.draggingImage() != nil)

        badge.isDraggingPlaceholder = true
        #expect(try !pixels(of: badge, size: size).contains { $0 != 0 }, "the placeholder leaves an empty slot")
        badge.animateAppearance()
    }

    // MARK: SwiftUI bar

    @Test("The layout bar draws as a card and bare")
    func layoutBarChromes() throws {
        let world = World()
        world.seat([World.item("Alpha")], in: .visible)
        let size = CGSize(width: 300, height: 60)
        func render(_ chrome: LayoutBar.Chrome) throws -> Data {
            let bar = LayoutBar(imageCache: world.appState.imageCache, section: .visible, chrome: chrome)
                .environment(world.appState)
                .frame(width: size.width, height: size.height)
            return try OffscreenRender(bar, size: size).pixels()
        }
        let card = try render(.card)
        let bare = try render(.bare)
        #expect(card.contains { $0 != 0 })
        #expect(card != bare, "the card adds a background and an outline")
    }
}
