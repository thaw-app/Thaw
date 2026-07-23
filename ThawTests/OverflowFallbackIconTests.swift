//
//  OverflowFallbackIconTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
@testable import Thaw
import XCTest

@MainActor
final class OverflowFallbackIconTests: XCTestCase {
    func testSupportsMissingCaptureFallbackOnMacOS27ForAnySection() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        XCTAssertTrue(OverflowFallbackIcon.supportsMissingCaptureFallback(for: .hidden))
        XCTAssertTrue(OverflowFallbackIcon.supportsMissingCaptureFallback(for: .alwaysHidden))
        XCTAssertTrue(OverflowFallbackIcon.supportsMissingCaptureFallback(for: .visible))
        XCTAssertFalse(OverflowFallbackIcon.supportsMissingCaptureFallback(for: nil))
    }

    func testShouldPreferAppIconOnlyWhenCaptureMissing() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let originalValue = Defaults.object(forKey: .alwaysUseAppIconForMenuBarItems)
        defer {
            if let originalValue {
                Defaults.set(originalValue, forKey: .alwaysUseAppIconForMenuBarItems)
            } else {
                Defaults.removeObject(forKey: .alwaysUseAppIconForMenuBarItems)
            }
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = false
        let item = appItem()

        XCTAssertTrue(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .alwaysHidden,
                appState: appState,
                cachedImage: nil
            )
        )
        XCTAssertTrue(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .visible,
                appState: appState,
                cachedImage: nil
            )
        )
        XCTAssertFalse(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .alwaysHidden,
                appState: appState,
                cachedImage: NSImage(size: NSSize(width: 16, height: 16))
            )
        )
    }

    func testShouldPreferAppIconWithCachedCaptureWhenOverrideEnabled() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let originalValue = Defaults.object(forKey: .alwaysUseAppIconForMenuBarItems)
        defer {
            if let originalValue {
                Defaults.set(originalValue, forKey: .alwaysUseAppIconForMenuBarItems)
            } else {
                Defaults.removeObject(forKey: .alwaysUseAppIconForMenuBarItems)
            }
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = true
        let item = runningAppItem()

        XCTAssertTrue(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .visible,
                appState: appState,
                cachedImage: NSImage(size: NSSize(width: 16, height: 16))
            )
        )
        XCTAssertFalse(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: nil,
                appState: appState,
                cachedImage: NSImage(size: NSSize(width: 16, height: 16))
            )
        )
    }

    func testNativeOverflowIgnoresCachedArrowCrop() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = false
        let item = runningAppItem()
        let cachedArrowCrop = NSImage(size: NSSize(width: 24, height: 24))

        XCTAssertTrue(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .hidden,
                appState: appState,
                cachedImage: cachedArrowCrop,
                isNativeOverflowActive: true
            )
        )
        XCTAssertFalse(
            OverflowFallbackIcon.resolvedImage(
                for: item,
                section: .hidden,
                appState: appState,
                cachedImage: cachedArrowCrop,
                isNativeOverflowActive: true
            ) === cachedArrowCrop
        )
    }

    func testOverrideDoesNotShowFallbackForQuitApp() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = true
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.example.QuitStatusApp"), title: "Status"),
            windowID: 5,
            sourcePID: nil
        )

        XCTAssertFalse(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .hidden,
                appState: appState,
                cachedImage: nil
            )
        )
        XCTAssertNil(
            OverflowFallbackIcon.resolvedImage(
                for: item,
                section: .hidden,
                appState: appState,
                cachedImage: nil
            )
        )
    }

    func testMenuBarAgentChildrenKeepCapturedPreviews() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let originalValue = Defaults.object(forKey: .alwaysUseAppIconForMenuBarItems)
        defer {
            if let originalValue {
                Defaults.set(originalValue, forKey: .alwaysUseAppIconForMenuBarItems)
            } else {
                Defaults.removeObject(forKey: .alwaysUseAppIconForMenuBarItems)
            }
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = true
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "WiFi"),
            windowID: 2
        )
        let capturedImage = NSImage(size: NSSize(width: 16, height: 16))

        XCTAssertFalse(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .visible,
                appState: appState,
                cachedImage: capturedImage
            )
        )
        XCTAssertTrue(
            OverflowFallbackIcon.resolvedImage(
                for: item,
                section: .visible,
                appState: appState,
                cachedImage: capturedImage
            ) === capturedImage
        )
        XCTAssertFalse(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: .hidden,
                appState: appState,
                cachedImage: nil
            )
        )
    }

    func testSiriKeepsItsCapturedPreview() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let originalValue = Defaults.object(forKey: .alwaysUseAppIconForMenuBarItems)
        defer {
            if let originalValue {
                Defaults.set(originalValue, forKey: .alwaysUseAppIconForMenuBarItems)
            } else {
                Defaults.removeObject(forKey: .alwaysUseAppIconForMenuBarItems)
            }
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = true
        let siri = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .systemUIServer, title: "Siri"),
            windowID: 3
        )

        XCTAssertTrue(OverflowFallbackIcon.usesCapturedSystemPreview(siri))
        XCTAssertFalse(
            OverflowFallbackIcon.shouldPreferAppIcon(
                for: siri,
                in: .visible,
                appState: appState,
                cachedImage: NSImage(size: NSSize(width: 16, height: 16))
            )
        )
    }

    func testVisibleControlItemUsesSelectedThawIconInAppIconMode() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("App-icon fallback is macOS 27-specific")
        }

        let originalValue = Defaults.object(forKey: .alwaysUseAppIconForMenuBarItems)
        let originalIcon = Defaults.object(forKey: .iceIcon)
        defer {
            if let originalValue {
                Defaults.set(originalValue, forKey: .alwaysUseAppIconForMenuBarItems)
            } else {
                Defaults.removeObject(forKey: .alwaysUseAppIconForMenuBarItems)
            }
            if let originalIcon {
                Defaults.set(originalIcon, forKey: .iceIcon)
            } else {
                Defaults.removeObject(forKey: .iceIcon)
            }
        }

        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = true
        appState.settings.general.iceIcon = .defaultIceIcon
        let item = visibleControlItem()
        let capturedImage = NSImage(size: NSSize(width: 64, height: 64))

        let resolved = OverflowFallbackIcon.resolvedImage(
            for: item,
            section: .visible,
            appState: appState,
            cachedImage: capturedImage,
            visibleControlItemState: .hideSection
        )
        let expected = appState.settings.general.iceIcon.hidden.nsImage(for: appState)

        XCTAssertFalse(resolved === capturedImage)
        XCTAssertEqual(resolved?.tiffRepresentation, expected?.tiffRepresentation)
    }

    func testSelectedThawIconTracksVisibleControlItemState() {
        let originalIcon = Defaults.object(forKey: .iceIcon)
        defer {
            if let originalIcon {
                Defaults.set(originalIcon, forKey: .iceIcon)
            } else {
                Defaults.removeObject(forKey: .iceIcon)
            }
        }

        let appState = AppState()
        appState.settings.general.iceIcon = .defaultIceIcon
        let item = visibleControlItem()

        let hidden = OverflowFallbackIcon.selectedThawIcon(
            for: item,
            appState: appState,
            visibleControlItemState: .hideSection
        )
        let visible = OverflowFallbackIcon.selectedThawIcon(
            for: item,
            appState: appState,
            visibleControlItemState: .showSection
        )

        XCTAssertEqual(
            hidden?.tiffRepresentation,
            appState.settings.general.iceIcon.hidden.nsImage(for: appState)?.tiffRepresentation
        )
        XCTAssertEqual(
            visible?.tiffRepresentation,
            appState.settings.general.iceIcon.visible.nsImage(for: appState)?.tiffRepresentation
        )
        XCTAssertNotEqual(hidden?.tiffRepresentation, visible?.tiffRepresentation)
    }

    func testSelectedCustomThawIconPreservesTemplateSetting() throws {
        let originalIcon = Defaults.object(forKey: .iceIcon)
        let originalTemplateValue = Defaults.object(forKey: .customIceIconIsTemplate)
        defer {
            if let originalIcon {
                Defaults.set(originalIcon, forKey: .iceIcon)
            } else {
                Defaults.removeObject(forKey: .iceIcon)
            }
            if let originalTemplateValue {
                Defaults.set(originalTemplateValue, forKey: .customIceIconIsTemplate)
            } else {
                Defaults.removeObject(forKey: .customIceIconIsTemplate)
            }
        }

        let appState = AppState()
        let symbol = try XCTUnwrap(NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil))
        let data = try XCTUnwrap(symbol.tiffRepresentation)
        appState.settings.general.iceIcon = ControlItemImageSet(name: .custom, image: .data(data))
        appState.settings.general.customIceIconIsTemplate = true

        let resolved = OverflowFallbackIcon.selectedThawIcon(
            for: visibleControlItem(),
            appState: appState,
            visibleControlItemState: .hideSection
        )

        XCTAssertEqual(resolved?.isTemplate, true)
    }

    func testOrdinaryItemDoesNotResolveSelectedThawIcon() {
        XCTAssertNil(
            OverflowFallbackIcon.selectedThawIcon(
                for: appItem(),
                appState: AppState(),
                visibleControlItemState: .hideSection
            )
        )
    }

    private func appItem() -> MenuBarItem {
        MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.example.StatusApp"), title: "Status"),
            windowID: 1
        )
    }

    private func runningAppItem() -> MenuBarItem {
        let pid = ProcessInfo.processInfo.processIdentifier
        return MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string("com.example.StatusApp"), title: "Status"),
            windowID: 6,
            sourcePID: pid,
            ownerPID: pid
        )
    }

    private func visibleControlItem() -> MenuBarItem {
        MenuBarItem.fixture(tag: .visibleControlItem, windowID: 4)
    }
}
