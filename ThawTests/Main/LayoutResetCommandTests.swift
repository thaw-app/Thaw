//
//  LayoutResetCommandTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the terminal escape hatch for a bar that comes back wrecked on
/// every launch (#899): a parked divider persists as an `NSStatusItem
/// Preferred Position`, so restarting restores it and the app starts moving
/// the pointer before the user can reach the Settings pane's reset.
@MainActor
@Suite("Layout reset command", .serialized)
struct LayoutResetCommandTests {
    /// Runs `body` against a throwaway defaults suite so the developer's own
    /// menu bar layout is never the thing under test.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "LayoutResetCommandTests.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create a defaults suite")
            return
        }
        let original = Defaults.store
        Defaults.store = suite
        defer {
            Defaults.store = original
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        try body(suite)
    }

    // MARK: - Argument parsing

    @Test("The flag selects the command")
    func flagSelectsTheCommand() {
        #expect(LayoutResetCommand.isRequested(arguments: ["/path/Thaw", "--reset-layout"]))
    }

    /// macOS passes its own arguments to a launched app, so the check has to
    /// tolerate company rather than expect the flag alone.
    @Test("The flag is found among other arguments")
    func flagIsFoundAmongOtherArguments() {
        #expect(LayoutResetCommand.isRequested(
            arguments: ["/path/Thaw", "-NSDocumentRevisionsDebugMode", "YES", "--reset-layout"]
        ))
    }

    @Test("A normal launch does not select the command")
    func normalLaunchDoesNotSelectTheCommand() {
        #expect(!LayoutResetCommand.isRequested(arguments: ["/path/Thaw"]))
    }

    /// A near miss must not wipe someone's layout.
    @Test("A similar-looking argument does not select the command")
    func similarArgumentDoesNotSelectTheCommand() {
        #expect(!LayoutResetCommand.isRequested(arguments: ["/path/Thaw", "--reset-layout-please"]))
        #expect(!LayoutResetCommand.isRequested(arguments: ["/path/Thaw", "reset-layout"]))
    }

    // MARK: - The reset itself

    @Test("Every persisted layout key is cleared")
    func everyPersistedLayoutKeyIsCleared() {
        withDefaults { suite in
            for key in LayoutResetCommand.layoutDefaultsKeys {
                suite.set(["stale"], forKey: key)
            }

            LayoutResetCommand.resetPersistedLayout()

            for key in LayoutResetCommand.layoutDefaultsKeys {
                #expect(suite.object(forKey: key) == nil, "\(key) survived the reset")
            }
        }
    }

    /// The parked position is the thing that makes the bar come back broken,
    /// so re-seeding it is the point of the whole command.
    @Test("A parked divider position is re-seeded")
    func parkedDividerPositionIsReseeded() {
        withDefaults { _ in
            let hidden = ControlItem.Identifier.hidden.rawValue
            ControlItemDefaults.setIgnoringSectionDividerGuard(
                .preferredPosition,
                hidden,
                to: -3950
            )
            #expect(ControlItemDefaults[.preferredPosition, hidden] == -3950)

            LayoutResetCommand.resetPersistedLayout()

            #expect(ControlItemDefaults[.preferredPosition, hidden] == 1)
        }
    }

    @Test("The visible control item is re-seeded")
    func visibleControlItemIsReseeded() {
        withDefaults { _ in
            let visible = ControlItem.Identifier.visible.rawValue
            ControlItemDefaults[.preferredPosition, visible] = 42

            LayoutResetCommand.resetPersistedLayout()

            #expect(ControlItemDefaults[.preferredPosition, visible] == 0)
        }
    }

    /// The always-hidden divider is placed dynamically and has no seed value,
    /// which is why `resetLayoutToFreshState()` leaves it alone. Matching that
    /// keeps the two resets from diverging.
    @Test("The always-hidden divider is left alone")
    func alwaysHiddenDividerIsLeftAlone() {
        withDefaults { _ in
            let alwaysHidden = ControlItem.Identifier.alwaysHidden.rawValue
            ControlItemDefaults.setIgnoringSectionDividerGuard(
                .preferredPosition,
                alwaysHidden,
                to: 7
            )

            LayoutResetCommand.resetPersistedLayout()

            #expect(ControlItemDefaults[.preferredPosition, alwaysHidden] == 7)
        }
    }

    /// Unrelated settings must survive: this is a layout reset, not a
    /// factory reset.
    @Test("Unrelated defaults survive the reset")
    func unrelatedDefaultsSurviveTheReset() {
        withDefaults { suite in
            suite.set(true, forKey: "SomeUnrelatedSetting")

            LayoutResetCommand.resetPersistedLayout()

            #expect(suite.object(forKey: "SomeUnrelatedSetting") as? Bool == true)
        }
    }

    // MARK: - Dispatch

    @Test("runIfRequested resets and reports that it ran")
    func runIfRequestedResetsAndReports() {
        withDefaults { suite in
            suite.set(["stale"], forKey: "MenuBarItemManager.savedSectionOrder")

            let ran = LayoutResetCommand.runIfRequested(
                arguments: ["/path/Thaw", LayoutResetCommand.flag]
            )

            #expect(ran)
            #expect(suite.object(forKey: "MenuBarItemManager.savedSectionOrder") == nil)
        }
    }

    /// A normal launch must leave the layout completely untouched, or every
    /// start would wipe the user's arrangement.
    @Test("A normal launch leaves the layout untouched")
    func normalLaunchLeavesLayoutUntouched() {
        withDefaults { suite in
            suite.set(["kept"], forKey: "MenuBarItemManager.savedSectionOrder")

            let ran = LayoutResetCommand.runIfRequested(arguments: ["/path/Thaw"])

            #expect(!ran)
            #expect(suite.array(forKey: "MenuBarItemManager.savedSectionOrder") as? [String] == ["kept"])
        }
    }
}
