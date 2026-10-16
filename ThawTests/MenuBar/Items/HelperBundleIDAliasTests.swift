//
//  HelperBundleIDAliasTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins the helper-to-app bundle identifier aliases used when deriving a
/// menu bar item's namespace.
///
/// Some apps host their status item in a nested helper, so the namespace,
/// saved position and name would name a process the user never installed
/// (e.g. `at.obdev.littlesnitch.agent`).
///
/// These values are a stored format: changing one orphans saved positions.
@Suite("Helper bundle ID aliases")
struct HelperBundleIDAliasTests {
    /// `at.obdev.littlesnitch.agent` owns the item; `at.obdev.littlesnitch`
    /// is the installed app.
    @Test("The Little Snitch agent resolves to the Little Snitch app")
    func littleSnitchAgentResolvesToApp() {
        #expect(
            MenuBarItemTag.Namespace.canonicalBundleID("at.obdev.littlesnitch.agent")
                == "at.obdev.littlesnitch"
        )
    }

    /// The app's own identifier is already canonical and must not be
    /// rewritten into something else.
    @Test("An already-canonical identifier is unchanged")
    func canonicalIdentifierUnchanged() {
        #expect(
            MenuBarItemTag.Namespace.canonicalBundleID("at.obdev.littlesnitch")
                == "at.obdev.littlesnitch"
        )
    }

    /// `com.microsoft.OneDrive-mac` looks like a suffixed variant, but it is
    /// the installed app's own identifier. Rewriting it orphans its saved
    /// position for good.
    @Test(
        "OneDrive identifiers are left alone",
        arguments: [
            "com.microsoft.OneDrive-mac",
            "com.microsoft.OneDrive-mac.FinderSync",
            "com.microsoft.OneDriveLauncher",
        ]
    )
    func oneDriveIdentifiersUntouched(bundleID: String) {
        #expect(MenuBarItemTag.Namespace.canonicalBundleID(bundleID) == bundleID)
    }

    /// Anything not explicitly listed is unchanged.
    @Test(
        "Unlisted identifiers pass through unchanged",
        arguments: [
            "com.apple.controlcenter",
            "com.apple.controlcenter.helper",
            "eu.exelban.Stats",
            "at.obdev.littlesnitch.daemon",
            "",
        ]
    )
    func unlistedIdentifiersPassThrough(bundleID: String) {
        #expect(MenuBarItemTag.Namespace.canonicalBundleID(bundleID) == bundleID)
    }

    /// A "strip the last component" heuristic would fold distinct items
    /// together, which is why the table is explicit.
    @Test("Sibling identifiers of an aliased app are not folded in")
    func siblingIdentifiersNotFolded() {
        // The daemon is a different process with a different lifetime; it
        // is not the app, and it is not in the table.
        #expect(
            MenuBarItemTag.Namespace.canonicalBundleID("at.obdev.littlesnitch.daemon")
                != "at.obdev.littlesnitch"
        )
    }

    /// Aliasing must be idempotent: every value in the table has to be a
    /// canonical identifier itself, or a second pass would keep rewriting.
    @Test("Aliasing is idempotent")
    func aliasingIsIdempotent() {
        for (helper, app) in MenuBarItemTag.Namespace.helperBundleIDAliases {
            let once = MenuBarItemTag.Namespace.canonicalBundleID(helper)
            #expect(once == app)
            #expect(MenuBarItemTag.Namespace.canonicalBundleID(once) == app,
                    "\(app) must not itself be a key in the alias table")
        }
    }
}
