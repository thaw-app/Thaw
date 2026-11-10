//
//  LazyPanelLifecycleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Lazy panel and window teardown lifecycle", .serialized, .scratchDefaults)
struct LazyPanelLifecycleTests {
    @Test("MenuBarManager leaves floating panels unallocated until first access")
    func panelsRemainNilUntilAccessed() {
        let manager = MenuBarManager()
        #expect(manager.thawBarPanelIfCreated == nil)
        #expect(manager.searchPanelIfCreated == nil)
        #expect(manager.appearanceEditorPanelIfCreated == nil)
        #expect(manager.layoutEditorPanelIfCreated == nil)

        _ = manager.thawBarPanel
        _ = manager.searchPanel
        #expect(manager.thawBarPanelIfCreated != nil)
        #expect(manager.searchPanelIfCreated != nil)
    }

    @Test("ThawBarPanel tears down its SwiftUI hosting view on idle and rebuilds on show")
    func thawBarIdleTeardownAndReopen() throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        let panel = ThawBarPanel()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            panel.close()
            panel.tearDownForIdle()
            NSApp.setActivationPolicy(originalPolicy)
        }
        NSApp.setActivationPolicy(.accessory)
        panel.performSetup(
            with: appState,
            displayInvalidations: Empty<Void, Never>(completeImmediately: false),
            displaySettlements: Empty<EnvironmentChange, Never>(completeImmediately: false)
        )
        panel.dismissesOnOutsideClick = false

        panel.show(section: .hidden, on: screen)
        #expect(panel.contentView != nil)

        panel.close()
        panel.tearDownForIdle()
        #expect(panel.contentView == nil)
        #expect(panel.contentViewController == nil)

        panel.show(section: .hidden, on: screen)
        #expect(panel.isVisible)
        #expect(panel.contentView != nil)
    }

    @Test("MenuBarSearchPanel releases its hosting view and cached rows on idle teardown")
    func searchPanelIdleTeardownAndReopen() throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        let panel = MenuBarSearchPanel()
        defer {
            panel.close()
            panel.tearDownForIdle()
        }
        panel.performSetup(
            with: appState,
            displayInvalidations: Empty<Void, Never>(completeImmediately: false)
        )

        panel.show(on: screen)
        #expect(panel.contentView != nil)

        panel.close()
        panel.tearDownForIdle()
        #expect(panel.contentView == nil)
        #expect(panel.contentViewController == nil)
        #expect(panel.model.displayedItems.isEmpty)
        #expect(panel.model.launcherCandidates.isEmpty)
        #expect(panel.model.selection == nil)

        panel.show(on: screen)
        #expect(panel.isVisible)
        #expect(panel.contentView != nil)
    }

    @Test("MenuBarSearchPanel close without hosted content does not arm teardown or wipe external model rows")
    func searchPanelCloseWhenUnshownPreservesExternalModel() async {
        let appState = AppState()
        let panel = MenuBarSearchPanel()
        panel.performSetup(
            with: appState,
            displayInvalidations: Empty<Void, Never>(completeImmediately: false)
        )
        panel.model.displayedItems = [
            SectionedListItem(content: .header(.visible), id: .header(.visible), isSelectable: false, action: nil),
        ]

        panel.close()
        try? await Task.sleep(for: MenuBarSearchPanel.idleTeardownDelay + .milliseconds(150))

        #expect(panel.model.displayedItems.count == 1)
    }

    @Test("ThawBarPanel deallocates after performSetup, show, close, and idle teardown")
    func thawBarDeallocatesAfterIdleTeardown() async throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            NSApp.setActivationPolicy(originalPolicy)
        }
        NSApp.setActivationPolicy(.accessory)
        weak var weakBar: ThawBarPanel?
        autoreleasepool {
            let panel = ThawBarPanel()
            weakBar = panel
            panel.performSetup(
                with: appState,
                displayInvalidations: Empty<Void, Never>(completeImmediately: false),
                displaySettlements: Empty<EnvironmentChange, Never>(completeImmediately: false)
            )
            panel.dismissesOnOutsideClick = false
            panel.show(section: .hidden, on: screen)
            panel.close()
            panel.tearDownForIdle()
        }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(weakBar == nil)
    }

    @Test("MenuBarSearchPanel deallocates after performSetup, show, close, and idle teardown")
    func searchPanelDeallocatesAfterIdleTeardown() async throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        weak var weakPanel: MenuBarSearchPanel?
        autoreleasepool {
            let panel = MenuBarSearchPanel()
            weakPanel = panel
            panel.performSetup(
                with: appState,
                displayInvalidations: Empty<Void, Never>(completeImmediately: false)
            )
            panel.show(on: screen)
            panel.close()
            panel.tearDownForIdle()
        }
        // Allow SwiftUI's focus task and main-actor teardown drain to settle.
        for _ in 0 ..< 20 where weakPanel != nil {
            try? await Task.sleep(for: .milliseconds(25))
        }

        #expect(weakPanel == nil)
    }

    @Test("tearDownWindowHierarchy clears controller, content view, and toolbar")
    func tearDownWindowHierarchyClearsRetainedGraphs() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        window.contentViewController = controller
        window.toolbar = NSToolbar(identifier: "TestToolbar")

        AppState.tearDownWindowHierarchy(window)

        #expect(window.contentViewController == nil)
        #expect(window.contentView == nil)
        #expect(window.toolbar == nil)
    }

    @Test("AppState creates managed windows lazily, reuses within grace, and tears down cleanly on close")
    func managedWindowLazyLifecycleGraceAndFreshReopen() async {
        let appState = AppState()
        let originalPolicy = NSApp.activationPolicy()
        var createdCount = 0
        appState.windowFactory = { id, _, delegate in
            createdCount += 1
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
            window.isReleasedWhenClosed = false
            let controller = NSViewController()
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 220))
            window.contentViewController = controller
            window.delegate = delegate
            return window
        }
        defer {
            appState.dismissWindow(.whatsNew)
            appState.tearDownClosedWindow(for: .whatsNew)
            NSApp.setActivationPolicy(originalPolicy)
        }

        #expect(appState.trackedWindows[.whatsNew] == nil)
        #expect(!appState.isWindowOpen(.whatsNew))

        weak var weakFirstWindow: NSWindow?
        weak var weakController: NSViewController?
        autoreleasepool {
            appState.openWindow(.whatsNew)
            let firstWindow = appState.trackedWindows[.whatsNew]
            weakFirstWindow = firstWindow
            weakController = firstWindow?.contentViewController
            #expect(firstWindow != nil)
            #expect(createdCount == 1)
            #expect(appState.isWindowOpen(.whatsNew))

            firstWindow?.close()
            #expect(!appState.isWindowOpen(.whatsNew))

            appState.openWindow(.whatsNew)
            #expect(appState.trackedWindows[.whatsNew] === firstWindow)
            #expect(createdCount == 1)
            #expect(appState.isWindowOpen(.whatsNew))

            firstWindow?.close()
            appState.tearDownClosedWindow(for: .whatsNew)
        }
        await Task.yield()

        #expect(appState.trackedWindows[.whatsNew] == nil)
        #expect(weakController == nil)
        #expect(weakFirstWindow == nil)

        appState.openWindow(.whatsNew)
        let reopenedWindow = appState.trackedWindows[.whatsNew]
        #expect(createdCount == 2)
        #expect(reopenedWindow != nil)
        #expect(reopenedWindow?.contentViewController != nil)
    }

    @Test("SettingsWindow AppKit host releases NSWindow and NSHostingController on teardown and reopens non-blank")
    func settingsWindowRealHostDeallocAndReopen() async {
        let appState = AppState()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            appState.dismissWindow(.settings)
            appState.tearDownClosedWindow(for: .settings)
            NSApp.setActivationPolicy(originalPolicy)
        }

        weak var weakWindow: NSWindow?
        weak var weakController: NSViewController?
        autoreleasepool {
            appState.openWindow(.settings, allowSettingsProcess: false)
            let window = appState.trackedWindows[.settings]
            weakWindow = window
            weakController = window?.contentViewController
            #expect(window != nil)
            #expect(window?.contentViewController != nil)
            #expect(appState.navigationState.isSettingsPresented)

            window?.layoutIfNeeded()
            window?.displayIfNeeded()
            window?.close()
            #expect(!appState.isWindowOpen(.settings))
            #expect(!appState.navigationState.isSettingsPresented)

            appState.tearDownClosedWindow(for: .settings)
        }
        await Task.yield()

        #expect(appState.trackedWindows[.settings] == nil)
        #expect(weakController == nil)
        #expect(weakWindow == nil)

        appState.openWindow(.settings, allowSettingsProcess: false)
        let reopened = appState.trackedWindows[.settings]
        #expect(reopened != nil)
        #expect(reopened?.contentViewController != nil)
        #expect(appState.isWindowOpen(.settings))
    }

    @Test("Reading and permissions AppKit hosts release cleanly on teardown and reopen non-blank")
    func secondaryWindowsRealHostDeallocAndReopen() async {
        let appState = AppState()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            for id in [ThawWindowIdentifier.whatsNew, .acknowledgements, .permissions] {
                appState.dismissWindow(id)
                appState.tearDownClosedWindow(for: id)
            }
            NSApp.setActivationPolicy(originalPolicy)
        }

        for id in [ThawWindowIdentifier.whatsNew, .acknowledgements, .permissions] {
            weak var weakWindow: NSWindow?
            weak var weakController: NSViewController?
            autoreleasepool {
                appState.openWindow(id, allowSettingsProcess: false)
                let window = appState.trackedWindows[id]
                weakWindow = window
                weakController = window?.contentViewController
                #expect(window != nil)
                #expect(window?.contentViewController != nil)
                #expect(appState.isWindowOpen(id))

                window?.layoutIfNeeded()
                window?.displayIfNeeded()
                window?.close()
                #expect(!appState.isWindowOpen(id))

                appState.tearDownClosedWindow(for: id)
            }
            await Task.yield()

            #expect(appState.trackedWindows[id] == nil)
            #expect(weakController == nil)
            #expect(weakWindow == nil)

            appState.openWindow(id, allowSettingsProcess: false)
            let reopened = appState.trackedWindows[id]
            #expect(reopened != nil)
            #expect(reopened?.contentViewController != nil)
            #expect(appState.isWindowOpen(id))
            reopened?.close()
            appState.tearDownClosedWindow(for: id)
        }
    }
}
