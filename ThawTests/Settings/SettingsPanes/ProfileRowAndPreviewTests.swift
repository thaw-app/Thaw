//
//  ProfileRowAndPreviewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The Profiles list row and the profile preview, drawn in the states the Profiles page tests don't reach.
@MainActor
@Suite("Profile row and preview states", .serialized)
struct ProfileRowAndPreviewTests {
    private static let rowSize = CGSize(width: 560, height: 60)
    private static let previewSize = CGSize(width: 420, height: 600)
    private static let itemNamespace = "com.example.thawtests.preview"
    private static let itemIdentifier = "\(itemNamespace):Wide"

    /// Draws the view and returns its pixels once it has put something on screen.
    private func drawn(_ render: OffscreenRender<some View>) async throws -> Data {
        await render.settle { (try? render.pixels())?.contains { $0 != 0 } == true }
        let pixels = try render.pixels()
        #expect(pixels.contains { $0 != 0 }, "the view draws something")
        return pixels
    }

    private func row(isActive: Bool = false, isEditing: Bool = false) -> OffscreenRender<some View> {
        let profile = ProfileMetadata(id: UUID(), name: "Work", createdAt: Date(), modifiedAt: Date())
        let view = ProfileListRow(
            profile: profile,
            isSelected: false,
            showsFocus: false,
            isActive: isActive,
            isApplying: false,
            isEditing: isEditing,
            editingName: .constant("Work"),
            select: {},
            apply: {},
            commitRename: {}
        ) {
            EmptyView()
        }
        return OffscreenRender(view.frame(width: Self.rowSize.width, height: Self.rowSize.height), size: Self.rowSize)
    }

    private func preview(
        diff: ProfileLayoutDiff? = nil,
        liveImages: [String: MenuBarItemDisplayImage] = [:]
    ) throws -> OffscreenRender<some View> {
        var profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"name": "Preview"}"#.utf8))
        profile.menuBarLayout.itemOrder = ["visible": [Self.itemIdentifier]]
        let view = ProfilePreviewView(profile: profile, diff: diff, liveImages: liveImages, isInline: true)
        return OffscreenRender(
            view.frame(width: Self.previewSize.width, height: Self.previewSize.height),
            size: Self.previewSize
        )
    }

    /// A solid icon as wide as asked and, unless told otherwise, as tall as a menu bar glyph.
    private static func solidIcon(width: CGFloat, height: CGFloat = 18) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
    }

    @Test("A row draws differently when it is the active profile or is being renamed")
    func rowStates() async throws {
        let idle = try await drawn(row())
        let active = try await drawn(row(isActive: true))
        let editing = try await drawn(row(isEditing: true))
        #expect(idle != active, "the active row says Active where the idle one offers Apply")
        #expect(idle != editing, "renaming swaps the name for a text field and a Done button")
        #expect(active != editing)
    }

    @Test("A saved item with a live picture draws it, and a wide picture is held to the width limit")
    func livePicturesDraw() async throws {
        let key = MenuBarItemTag.canonicalPersistentIdentifier(Self.itemIdentifier)
        let none = try await drawn(preview())
        let wide = try await drawn(preview(liveImages: [key: .icon(Self.solidIcon(width: 300))]))
        let narrow = try await drawn(preview(liveImages: [key: .icon(Self.solidIcon(width: 16))]))
        // A 300 by 18 picture is held to 40 points wide, which scales its height to 2.4.
        let atTheLimit = try await drawn(preview(liveImages: [key: .icon(Self.solidIcon(width: 40, height: 2.4))]))
        #expect(wide != none, "a live picture replaces the placeholder")
        #expect(narrow != none)
        #expect(wide == atTheLimit, "the wide picture is drawn at the width limit, no wider")
        #expect(narrow != atTheLimit, "a narrow picture keeps its own size")
    }

    @Test("A diff that reorders sections says which ones")
    func reorderedSectionsDraw() async throws {
        let item = ProfileLayoutDiff.Item(id: "com.a:A", bundleID: "com.a", title: "A")
        var moved = ProfileLayoutDiff()
        moved.moves = [ProfileLayoutDiff.Move(item: item, from: "visible", to: "hidden")]
        var reordered = moved
        reordered.reorderedSections = ["hidden", "visible"]
        let before = try await drawn(preview(diff: moved))
        let after = try await drawn(preview(diff: reordered))
        #expect(before != after, "each reordered section adds a line")
    }

    @Test("The bar's live pictures are collected for every managed item under its canonical identifier")
    func livePicturesFromTheBar() {
        let appState = AppState()
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(Self.itemNamespace), title: "Wide", instanceIndex: 0),
            windowID: 701,
            ownerPID: 999_995,
            sourcePID: 999_995,
            bounds: CGRect(x: 1000, y: 4.5, width: 24, height: 24),
            title: "Wide",
            isOnScreen: true
        )
        #expect(ProfilePreviewModel.liveImages(in: appState).isEmpty, "an empty bar has no pictures")

        appState.itemManager.itemCache[.visible] = [item]
        let images = ProfilePreviewModel.liveImages(in: appState)
        #expect(images.count == 1)
        #expect(images[item.canonicalIdentifier] != nil)
    }

    @Test("Items from Apple's own menu bar processes use Control Center's icon, not an app icon")
    func systemItemsUseControlCenterIcon() {
        for identifier in [
            "com.apple.controlcenter:WiFi",
            "com.apple.systemuiserver:Siri",
            "com.apple.TextInputMenuAgent:Input",
        ] {
            #expect(ProfilePreviewModel.savedItemIcon(for: identifier) == ControlCenterIcon.image, "\(identifier)")
        }
    }
}
