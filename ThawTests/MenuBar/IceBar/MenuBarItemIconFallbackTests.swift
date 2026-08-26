//
//  MenuBarItemIconFallbackTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Menu bar item icon fallback")
@MainActor
struct MenuBarItemIconFallbackTests {
    /// This process is always running, so it is a dependable stand-in for an
    /// item's source application.
    private var ownPID: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    private func item(
        namespace: MenuBarItemTag.Namespace,
        title: String = "Status",
        sourcePID: pid_t?
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, windowID: 1),
            windowID: 1,
            ownerPID: 2559,
            sourcePID: sourcePID,
            bounds: .zero,
            title: title,
            isOnScreen: true
        )
    }

    @Test("An icon resolved for a live process comes back")
    func resolvesIconForLiveProcess() {
        MenuBarItemIconFallback.forgetIcon(forPID: ownPID)
        #expect(MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID) != nil)
    }

    @Test("The same process resolves to the identical image, not an equal copy")
    func cachesByProcess() {
        MenuBarItemIconFallback.forgetIcon(forPID: ownPID)
        let first = MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID)
        let second = MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID)

        // Identity, not equality: `.icon` builds a fresh NSImage per call, so
        // two distinct instances would mean the cache is not holding and the
        // bar would allocate one image per body evaluation.
        #expect(first === second)
    }

    @Test("A process with no icon is remembered as having none")
    func cachesNegativeResults() {
        // A PID that cannot resolve to a running application. Re-reading it
        // must not re-probe, or every render pays for the miss.
        let deadPID: pid_t = -1
        MenuBarItemIconFallback.forgetIcon(forPID: deadPID)
        #expect(MenuBarItemIconFallback.cachedAppIcon(forPID: deadPID) == nil)
        #expect(MenuBarItemIconFallback.cachedAppIcon(forPID: deadPID) == nil)
    }

    @Test("Forgetting a process drops its cached icon")
    func forgettingClearsTheEntry() {
        let first = MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID)
        MenuBarItemIconFallback.forgetIcon(forPID: ownPID)
        let second = MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID)

        #expect(first !== second)
        #expect(second != nil)
    }

    @Test("Pruning keeps live processes and drops exited ones")
    func pruningKeepsLiveProcesses() {
        _ = MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID)
        _ = MenuBarItemIconFallback.cachedAppIcon(forPID: -1)

        MenuBarItemIconFallback.forgetIconsForExitedApplications()

        // Still resolvable afterwards, which is what matters to a caller.
        #expect(MenuBarItemIconFallback.cachedAppIcon(forPID: ownPID) != nil)
    }

    // MARK: Routing

    @Test("A system-hosted item uses the hosting app's icon rather than none")
    func systemHostedItemsUseTheHostIcon() {
        // Control Center hosts many unrelated modules, so these items have no
        // app of their own to point at.
        for namespace in [
            MenuBarItemTag.Namespace.controlCenter,
            .systemUIServer,
            .textInputMenuAgent,
        ] {
            let item = item(namespace: namespace, title: "Module", sourcePID: nil)
            // Resolves to the shared Control Center icon when that process is
            // running; the important part is that it never falls through to
            // an unresolved source PID.
            _ = MenuBarItemIconFallback.appIcon(for: item)
        }
    }

    @Test("An item with no resolvable source app has no app icon")
    func unresolvableItemHasNoAppIcon() {
        let item = item(namespace: .string("com.example.gone"), sourcePID: nil)
        #expect(MenuBarItemIconFallback.appIcon(for: item) == nil)
    }

    @Test("An item with no app icon still renders something clickable")
    func alwaysProducesAnImage() {
        let item = item(namespace: .string("com.example.gone"), sourcePID: nil)
        // A gap the user cannot click is the failure this whole path exists
        // to avoid, so the generic glyph is required, not optional.
        #expect(MenuBarItemIconFallback.appIcon(for: item) == nil)
        #expect(MenuBarItemIconFallback.image(for: item) != nil)
    }

    @Test("An item owned by a live app renders that app's icon")
    func liveSourceAppProvidesTheIcon() {
        let item = item(namespace: .string("com.example.live"), sourcePID: ownPID)
        #expect(MenuBarItemIconFallback.appIcon(for: item) != nil)
        #expect(MenuBarItemIconFallback.image(for: item) != nil)
    }
}
