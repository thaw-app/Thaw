//
//  LauncherURILiveEnvironmentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// How the launcher operations read a real AppState: which items they list and
/// which stores each answer comes from.
@MainActor
@Suite("Launcher URI live environment", .serialized)
struct LauncherURILiveEnvironmentTests {
    private func item(_ tag: MenuBarItemTag, ownerPID: pid_t = pid_t.max, sourcePID: pid_t? = nil) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 1,
            ownerPID: ownerPID,
            sourcePID: sourcePID,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    private func appTag(_ title: String = "Item") -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("com.example.thawtests.\(UUID().uuidString)"), title: title, instanceIndex: 0)
    }

    @Test("Only items a user can act on are listed, each under its identifier and section")
    func listsActionableItems() {
        let first = item(appTag())
        let second = item(appTag("Other"))
        let divider = item(.visibleControlItem)

        let listed = SettingsURIHandler.launcherItems(from: [first, divider, second]) { item in
            item == first ? .hidden : .alwaysHidden
        }

        #expect(listed.map(\.id) == [first.uniqueIdentifier, second.uniqueIdentifier])
        #expect(listed.map(\.section) == ["hidden", "alwaysHidden"])
        #expect(listed.map(\.name) == [first.displayName, second.displayName])
        #expect(listed.allSatisfy { !$0.name.isEmpty })
    }

    @Test("An item names the app that created it, falling back to its window's owner")
    func namesTheCreatingApp() throws {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = try #require(Bundle.main.bundleIdentifier)
        let created = item(appTag(), sourcePID: ownPID)
        let owned = item(appTag(), ownerPID: ownPID)
        let orphan = item(appTag())

        let listed = SettingsURIHandler.launcherItems(from: [created, owned, orphan]) { _ in .visible }

        #expect(listed.map(\.bundleId) == [ownBundle, ownBundle, nil])
    }

    @Test("The live environment answers from the app state's own stores")
    func readsTheAppState() async {
        let appState = AppState()
        let environment = SettingsURIHandler.LauncherEnvironment(appState: appState)
        let listed = item(appTag())
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [listed, item(.visibleControlItem)]
        appState.itemManager.itemCache = cache

        #expect(environment.hasAccessibilityPermission() == appState.permissions.accessibility.hasPermission)
        let items = environment.items()
        #expect(items.map(\.id) == [listed.uniqueIdentifier])
        #expect(items.first?.section == appState.menuBarManager.sectionController.section(for: listed).rawValue)
        #expect(environment.profiles() == appState.profileManager.profiles)
        #expect(environment.activeProfileID() == appState.profileManager.activeProfileID)

        let configuration = appState.appearanceManager.effectiveConfiguration
        #expect(environment.appearance() == SharedAppearance(
            configuration: configuration.current,
            shapeKind: configuration.shapeKind,
            hasRoundedShape: configuration.hasRoundedShape,
            isDark: SystemAppearance.current == .dark
        ))
    }

    @Test("Activation through a manager that was never set up fails instead of pressing anything")
    func activationNeedsASetUpManager() async {
        let appState = AppState()
        let environment = SettingsURIHandler.LauncherEnvironment(appState: appState)
        let listed = item(appTag())
        appState.itemManager.itemCache[.visible] = [listed]

        #expect(await environment.activateItem(listed.uniqueIdentifier) == .activationFailed)
    }

    @Test("Applying an identifier with no profile file fails and leaves the active profile alone")
    func applyingAMissingProfileThrows() async {
        let appState = AppState()
        let environment = SettingsURIHandler.LauncherEnvironment(appState: appState)
        let active = appState.profileManager.activeProfileID

        await #expect(throws: (any Error).self) {
            try await environment.applyProfile(UUID())
        }

        #expect(appState.profileManager.activeProfileID == active)
        #expect(appState.profileManager.layoutTask == nil)
    }
}

extension SettingsURIResponseSuites {
    @MainActor
    @Suite("Launcher URI through the app state")
    struct LauncherURIAppStateEntryTests {
        @Test("The app state entry point answers from that app state's profiles")
        func unknownProfileIsReportedThroughTheAppState() async throws {
            let appState = AppState()
            let identifier = UUID().uuidString
            let url = try #require(URL(string: "thaw://apply-profile?profile-id=\(identifier)&callback=floe://thaw-response"))
            let request = try #require(LauncherURIRequest(url: url))
            let active = appState.profileManager.activeProfileID
            let capture = URIDeliveryCapture()

            await capture.run {
                await SettingsURIHandler.handleLauncherRequest(request, sender: nil, appState: appState)
            }

            let response = try capture.callbackResponse()
            #expect(response["operation"] as? String == "apply-profile")
            #expect(response["error"] as? String == "profileUnavailable")
            #expect(appState.profileManager.activeProfileID == active)
        }
    }
}
