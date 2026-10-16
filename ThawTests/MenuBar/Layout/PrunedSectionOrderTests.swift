//
//  PrunedSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Repairs a persisted section order. The provisional-identity guard (#788) and
/// title canonicalization (#815) stop new damage but leave old damage on disk.
@Suite("Pruned section order")
struct PrunedSectionOrderTests {
    // MARK: Provisional-identity duplicates (#788)

    /// BetterTouchTool saved under its real owner and again under the Control
    /// Center namespace it got while its source PID was unresolved.
    @Test("A Control Center duplicate of a real owner's item is dropped")
    func dropsProvisionalDuplicate() {
        let real = "com.hegenberg.BetterTouchTool:com.hegenberg.BetterTouchTool (449CF8DD-A814-4D62-99D1-85D3F400F8B3)"
        let poisoned = "com.apple.controlcenter:com.hegenberg.BetterTouchTool (449CF8DD-A814-4D62-99D1-85D3F400F8B3)"

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": [real, poisoned, "us.zoom.xos:Item-0"]])
        #expect(pruned["hidden"] == [real, "us.zoom.xos:Item-0"])
    }

    /// The poisoned copy sits wherever it was when resolution failed.
    @Test("The duplicate is dropped across section boundaries")
    func dropsProvisionalDuplicateAcrossSections() {
        let real = "com.hegenberg.BetterTouchTool:BetterTouchTool"
        let poisoned = "com.apple.controlcenter:BetterTouchTool"

        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": [real],
            "hidden": [poisoned],
        ])
        #expect(pruned["visible"] == [real])
        #expect(pruned["hidden"] == [])
    }

    /// Genuine Control Center items have no real-owner twin, so they survive.
    @Test("Genuine Control Center items are never pruned")
    func keepsGenuineControlCenterItems() {
        let system = [
            "com.apple.controlcenter:WiFi",
            "com.apple.controlcenter:Battery",
            "com.apple.controlcenter:Sound",
            "com.apple.controlcenter:Clock",
            "com.apple.controlcenter:BentoBox-0",
            "com.apple.controlcenter:FocusModes",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["visible": system])
        #expect(pruned["visible"] == system)
    }

    /// Instance indexes are identity, so `:1` is not a duplicate of `:0`.
    @Test("Differing instance indexes are not duplicates")
    func instanceIndexesAreDistinct() {
        let entries = [
            "org.openvpn.client.app:Item-0",
            "com.apple.controlcenter:Item-1",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["hidden": entries])
        #expect(pruned["hidden"] == entries)
    }

    // MARK: Localized display-name ghosts (#949)

    /// An en-GB machine minted `Control Centre:WiFi` while the bundle ID read nil,
    /// and treating it as a real owner deleted the genuine `com.apple.controlcenter:WiFi` (#949).
    @Test("A localized ghost never deletes its genuine Control Center twin")
    func localizedGhostDoesNotDeleteGenuineTwin() {
        let ghost = "Control Centre:WiFi"
        let genuine = "com.apple.controlcenter:WiFi"

        let pruned = LayoutSolver.prunedSectionOrder(["visible": [ghost, genuine]])
        #expect(pruned["visible"] == [genuine])
    }

    /// A mis-tagged chevron: control item titles only exist in Thaw's namespace.
    @Test("A localized ghost of a Thaw control item is dropped")
    func localizedGhostOfControlItemIsDropped() {
        let ghost = "Control Centre:Thaw.ControlItem.Visible"
        let genuine = "com.stonerl.Thaw:Thaw.ControlItem.Visible"

        let pruned = LayoutSolver.prunedSectionOrder(["visible": [ghost, genuine]])
        #expect(pruned["visible"] == [genuine])
    }

    /// It may be the only identity a bundle-ID-less app ever got.
    @Test("A display-name entry without a twin survives")
    func displayNameEntryWithoutTwinSurvives() {
        let entries = ["Docker Desktop:Item-0", "com.if.Amphetamine:Amphetamine"]

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": entries])
        #expect(pruned["hidden"] == entries)
    }

    /// Some locales have no whitespace (German: Kontrollzentrum), so the caller passes
    /// the live localized name as an alias.
    @Test("A whitespace-free localized alias is recognized via the alias set")
    func whitespaceFreeAliasIsRecognized() {
        let ghost = "Kontrollzentrum:WiFi"
        let genuine = "com.apple.controlcenter:WiFi"

        let withAlias = LayoutSolver.prunedSectionOrder(
            ["visible": [ghost, genuine]],
            displayNameAliases: ["Kontrollzentrum"]
        )
        #expect(withAlias["visible"] == [genuine])
    }

    /// `Control Centre:Alcove` next to `com.henrikruscon.Alcove:Alcove`: a third-party
    /// twin found only via the claimed-title rule (#949).
    @Test("A localized ghost of a real owner's item is dropped")
    func localizedGhostOfRealOwnerIsDropped() {
        let ghost = "Control Centre:Alcove"
        let genuine = "com.henrikruscon.Alcove:Alcove"

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": [ghost, genuine]])
        #expect(pruned["hidden"] == [genuine])
    }

    /// Every owner has an Item-0, so a generic title is no evidence of a twin.
    @Test("A generic title never counts as a claimed-title twin")
    func genericTitleIsNotAClaimedTitleTwin() {
        let entries = ["Docker Desktop:Item-0", "org.openvpn.client.app:Item-0"]

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": entries])
        #expect(pruned["hidden"] == entries)
    }

    /// The ghost sits wherever the item was when the bundle ID failed to read.
    @Test("The localized ghost is dropped across section boundaries")
    func localizedGhostDroppedAcrossSections() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["com.apple.controlcenter:Battery"],
            "hidden": ["Control Centre:Battery"],
        ])
        #expect(pruned["visible"] == ["com.apple.controlcenter:Battery"])
        #expect(pruned["hidden"] == [])
    }

    // MARK: Volatile-title accumulation (#815)

    /// LyricsX saved one entry per lyric shown; all canonicalize to one key.
    @Test("Per-lyric history collapses to one entry")
    func collapsesLyricHistory() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let polluted = (0 ..< 30).map { "\(owner):lyric line \($0)" }

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": polluted])
        #expect(pruned["hidden"]?.count == 1)
        #expect(pruned["hidden"]?.first == polluted[0])
    }

    /// The same for the metric owner.
    @Test("Per-sample metric history collapses per distinct metric")
    func collapsesMetricHistory() {
        let owner = MenuBarItemTag.iStatMenusStatusBundleID
        let polluted = [
            "\(owner):CPU 12%", "\(owner):CPU 43%", "\(owner):CPU 7%",
            "\(owner):Network 3.4 MB/s", "\(owner):Network 918 KB/s",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["hidden": polluted])
        #expect(pruned["hidden"] == ["\(owner):CPU 12%", "\(owner):Network 3.4 MB/s"])
    }

    // MARK: Invariants

    /// Reordering would itself produce the fault #885 detects.
    @Test("Surviving entries keep their relative order")
    func preservesOrder() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let entries = [
            "a.app:Item-0",
            "\(owner):first lyric",
            "b.app:Item-0",
            "\(owner):second lyric",
            "c.app:Item-0",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["visible": entries])
        #expect(pruned["visible"] == ["a.app:Item-0", "\(owner):first lyric", "b.app:Item-0", "c.app:Item-0"])
    }

    /// Runs every launch, so a clean layout must come back identical and never churn the plist.
    @Test("A clean layout is returned unchanged")
    func cleanLayoutIsUnchanged() {
        let clean = [
            "visible": ["com.apple.controlcenter:WiFi", "net.cozic.joplin-desktop:Item-0"],
            "hidden": ["us.zoom.xos:Item-0", "com.apple.systemuiserver:Siri"],
            "alwaysHidden": [String](),
        ]
        #expect(LayoutSolver.prunedSectionOrder(clean) == clean)
    }

    /// Keeps the caller's `pruned != stored` comparison meaningful.
    @Test("Sections and keys survive an empty result")
    func keysSurviveEmptying() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["real.owner:Thing"],
            "hidden": ["com.apple.controlcenter:Thing"],
        ])
        #expect(pruned.keys.sorted() == ["hidden", "visible"])
        #expect(pruned["hidden"]?.isEmpty == true)
    }

    /// A volatile-title owner saved in two sections under different samples
    /// canonicalizes to one key in both, and lookups would pick whichever section
    /// iterated last.
    @Test("The same canonical identity is kept in only one section")
    func canonicalDuplicateAcrossSectionsIsResolved() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(owner):a lyric from earlier"],
            "hidden": ["\(owner):a different lyric"],
        ])

        let survivors = (pruned["visible"] ?? []) + (pruned["hidden"] ?? [])
        #expect(survivors.count == 1, "one identity must not occupy two sections")
        #expect(pruned["visible"]?.count == 1, "the more visible section wins")
        #expect(pruned["hidden"]?.isEmpty == true)
    }

    /// The metric owner, across all three sections.
    @Test("Section precedence is visible, then hidden, then always-hidden")
    func sectionPrecedenceIsDeterministic() {
        let owner = MenuBarItemTag.iStatMenusStatusBundleID
        let pruned = LayoutSolver.prunedSectionOrder([
            "alwaysHidden": ["\(owner):CPU 3%"],
            "hidden": ["\(owner):CPU 55%"],
            "visible": ["\(owner):CPU 12%"],
        ])

        #expect(pruned["visible"] == ["\(owner):CPU 12%"])
        #expect(pruned["hidden"]?.isEmpty == true)
        #expect(pruned["alwaysHidden"]?.isEmpty == true)
    }

    /// Sharing a namespace does not make identities the same.
    @Test("Distinct metrics from one owner survive in their own sections")
    func distinctMetricsAreNotCollapsed() {
        let owner = MenuBarItemTag.iStatMenusStatusBundleID
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(owner):CPU 12%"],
            "hidden": ["\(owner):Network 3.4 MB/s"],
        ])

        #expect(pruned["visible"] == ["\(owner):CPU 12%"])
        #expect(pruned["hidden"] == ["\(owner):Network 3.4 MB/s"])
    }

    /// Unknown section keys are outside the precedence order and keep their entries.
    @Test("An unknown section key keeps its own entries")
    func unknownSectionKeyIsPreserved() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["us.zoom.xos:Item-0"],
            "legacy": ["com.example.app:Item-0", "us.zoom.xos:Item-0"],
        ])

        #expect(pruned["visible"] == ["us.zoom.xos:Item-0"])
        #expect(pruned["legacy"] == ["com.example.app:Item-0", "us.zoom.xos:Item-0"])
    }

    // MARK: Misattributed own-namespace entries (#927)

    /// Source-PID resolution gave Control Center's WiFi Thaw's own PID; nothing live will carry that name.
    @Test("A foreign item saved under Thaw's namespace is dropped")
    func dropsForeignEntryUnderOwnNamespace() {
        let own = Constants.bundleIdentifier
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(own):WiFi", "us.zoom.xos:Item-0"],
        ])
        #expect(pruned["visible"] == ["us.zoom.xos:Item-0"])
    }

    /// This rule runs before the duplicate check: otherwise the misattributed entry
    /// owns `WiFi` and the genuine Control Center item is deleted instead (#927).
    @Test("The genuine Control Center twin survives its misattributed copy")
    func keepsGenuineTwinOfMisattributedEntry() {
        let own = Constants.bundleIdentifier
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(own):WiFi", "com.apple.controlcenter:WiFi"],
        ])
        #expect(pruned["visible"] == ["com.apple.controlcenter:WiFi"])
    }

    @Test("Thaw's own control items and spacers survive")
    func keepsOwnControlItemsAndSpacers() {
        let own = Constants.bundleIdentifier
        let entries = [
            "\(own):Thaw.ControlItem.Visible",
            "\(own):Thaw.ControlItem.Hidden",
            "\(own):Thaw.ControlItem.AlwaysHidden",
            "\(own):Thaw.ControlItem.Visible.Spacer.0",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["visible": entries])
        #expect(pruned["visible"] == entries)
    }

    /// An instance index does not make a control item foreign.
    @Test("An indexed control item is not treated as foreign")
    func keepsIndexedControlItem() {
        let own = Constants.bundleIdentifier
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(own):Thaw.ControlItem.Visible:1"],
        ])
        #expect(pruned["visible"] == ["\(own):Thaw.ControlItem.Visible:1"])
    }

    // MARK: System clones (#927)

    /// Six clones under one owner were planned against on every apply.
    @Test("System clone entries are dropped under any namespace")
    func dropsSystemClones() {
        let owner = "info.marcel-dierkes.KeepingYouAwake"
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": [
                "\(owner):Item-0",
                "\(owner):System Status Item Clone",
                "\(owner):System Status Item Clone:1",
                "\(owner):System Status Item Clone:6",
            ],
        ])
        #expect(pruned["visible"] == ["\(owner):Item-0"])
    }

    @Test("A title that only resembles a clone name survives")
    func keepsLookalikeCloneTitle() {
        let entry = "com.example.app:System Status Item Clone Manager"
        let pruned = LayoutSolver.prunedSectionOrder(["visible": [entry]])
        #expect(pruned["visible"] == [entry])
    }

    // MARK: Self-titled entries (#881, #927)

    /// Four entries from #881, verbatim; the degradation hits siblings, hence the indexes.
    @Test("Entries titled after their own namespace are dropped")
    func dropsSelfTitledEntries() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "hidden": [
                "com.steipete.codexbar:codexbar-claude",
                "com.steipete.codexbar:com.steipete.codexbar",
                "com.steipete.codexbar:com.steipete.codexbar:2",
                "eu.exelban.Stats:eu.exelban.Stats:3",
                "leits.MeetingBar:Item-0",
            ],
        ])
        #expect(pruned["hidden"] == ["com.steipete.codexbar:codexbar-claude", "leits.MeetingBar:Item-0"])
    }

    /// Pruning runs after ``LayoutSolver/canonicalizedSectionOrder(_:)``, which
    /// rewrites the helper namespace but not the title, so they no longer match literally.
    @Test("A canonicalized helper namespace still reads as self-titled")
    func dropsSelfTitledEntryAfterNamespaceCanonicalization() {
        let degraded = ["hidden": ["at.obdev.littlesnitch.agent:at.obdev.littlesnitch.agent"]]
        let pruned = LayoutSolver.prunedSectionOrder(LayoutSolver.canonicalizedSectionOrder(degraded))
        #expect(pruned["hidden"] == [])
    }

    /// A self-titled entry is not a real owner and must not license the #788 rule
    /// to delete the genuine Control Center item.
    @Test("A self-titled entry does not condemn a Control Center twin")
    func selfTitledEntryDoesNotCondemnControlCenterTwin() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": [
                "com.microsoft.OneDrive:com.microsoft.OneDrive",
                "com.apple.controlcenter:com.microsoft.OneDrive",
            ],
        ])
        #expect(pruned["visible"] == ["com.apple.controlcenter:com.microsoft.OneDrive"])
    }

    /// BetterTouchTool's UUID-suffixed title starts with its bundle ID, so only exact equality counts.
    @Test("A title that merely begins with its namespace survives")
    func keepsTitleThatOnlyBeginsWithNamespace() {
        let entries = [
            "com.hegenberg.BetterTouchTool:com.hegenberg.BetterTouchTool (449CF8DD-A814-4D62-99D1-85D3F400F8B3)",
            "com.apple.TextInputMenuAgent:com.apple.TextInputMenuAgent.Extra",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["visible": entries])
        #expect(pruned["visible"] == entries)
    }
}
