//
//  HelperBundleIDAliasTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins the helper-to-app bundle identifier aliases used when deriving a
/// menu bar item's namespace.
///
/// Some apps host their status item in a nested helper, so the window's
/// owner — and therefore the namespace, `uniqueIdentifier`, saved position
/// and displayed name — is a process the user never installed. Little
/// Snitch is the verified case: the item is owned by
/// `at.obdev.littlesnitch.agent`, a helper inside
/// `/Applications/Little Snitch.app/Contents/Components/`.
///
/// These raw values are effectively a stored format: an item's persisted
/// position is keyed by the identifier this mapping produces, so changing
/// one silently orphans the entries users already have.
@Suite("Helper bundle ID aliases")
struct HelperBundleIDAliasTests {
    /// The verified case. `at.obdev.littlesnitch.agent` owns the item;
    /// `at.obdev.littlesnitch` is the app the user installed.
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

    /// OneDrive must NOT be aliased, and this is a regression test rather
    /// than a formality: `com.microsoft.OneDrive-mac` looks like a
    /// platform-suffixed variant of `com.microsoft.OneDrive`, but it is
    /// the installed app's own identifier — verified against a running
    /// OneDrive. Rewriting it renames a real app to an identifier no
    /// process reports, orphaning its saved position for good. Its status
    /// item is owned by the main app; there is no helper to fold in.
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

    /// The overwhelming majority of items are untouched: the mapping is
    /// the identity function for anything not explicitly listed.
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

    /// A "strip the last component" heuristic would fold distinct Control
    /// Center items together; the table is explicit precisely so that
    /// cannot happen. This guards against someone replacing it with one.
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
