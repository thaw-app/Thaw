//
//  PrunedSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the repair pass over a persisted section order.
///
/// Two shipped fixes stop their own failure from recurring but leave what was
/// already written to disk in place: the provisional-identity guard (#788) and
/// volatile-title canonicalization (#815). Users who were affected before
/// either landed keep their damaged layout forever. This is the heal.
@Suite("Pruned section order")
struct PrunedSectionOrderTests {
    // MARK: Provisional-identity duplicates (#788)

    /// The reporter's exact pair: BetterTouchTool's item saved once under its
    /// real owner and once under the Control Center namespace it was given
    /// while its source PID would not resolve.
    @Test("A Control Center duplicate of a real owner's item is dropped")
    func dropsProvisionalDuplicate() {
        let real = "com.hegenberg.BetterTouchTool:com.hegenberg.BetterTouchTool (449CF8DD-A814-4D62-99D1-85D3F400F8B3)"
        let poisoned = "com.apple.controlcenter:com.hegenberg.BetterTouchTool (449CF8DD-A814-4D62-99D1-85D3F400F8B3)"

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": [real, poisoned, "us.zoom.xos:Item-0"]])
        #expect(pruned["hidden"] == [real, "us.zoom.xos:Item-0"])
    }

    /// The duplicate and its real owner need not share a section — the
    /// poisoned copy is filed wherever it was when resolution failed.
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

    /// The safety property. Genuine Control Center items have no real-owner
    /// twin, so nothing about them looks like a duplicate and they survive.
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

    /// Instance indexes are part of identity, so `:1` is not a duplicate of
    /// `:0` and must not be collapsed into it.
    @Test("Differing instance indexes are not duplicates")
    func instanceIndexesAreDistinct() {
        let entries = [
            "org.openvpn.client.app:Item-0",
            "com.apple.controlcenter:Item-1",
        ]
        let pruned = LayoutSolver.prunedSectionOrder(["hidden": entries])
        #expect(pruned["hidden"] == entries)
    }

    // MARK: Volatile-title accumulation (#815)

    /// A LyricsX layout accumulated one entry per lyric ever displayed. All
    /// of them canonicalize to a single key, so only the first survives.
    @Test("Per-lyric history collapses to one entry")
    func collapsesLyricHistory() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let polluted = (0 ..< 30).map { "\(owner):lyric line \($0)" }

        let pruned = LayoutSolver.prunedSectionOrder(["hidden": polluted])
        #expect(pruned["hidden"]?.count == 1)
        #expect(pruned["hidden"]?.first == polluted[0])
    }

    /// Same shape for the metric owner the canonicalizer was built for.
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

    /// Pruning must only ever remove. If it reordered a section it would
    /// itself produce the fault #885 exists to detect.
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

    /// A layout with nothing wrong with it must come back byte-identical, so
    /// running this on every launch is free and cannot churn the plist.
    @Test("A clean layout is returned unchanged")
    func cleanLayoutIsUnchanged() {
        let clean = [
            "visible": ["com.apple.controlcenter:WiFi", "net.cozic.joplin-desktop:Item-0"],
            "hidden": ["us.zoom.xos:Item-0", "com.apple.systemuiserver:Siri"],
            "alwaysHidden": [String](),
        ]
        #expect(LayoutSolver.prunedSectionOrder(clean) == clean)
    }

    /// Section keys are preserved even when a section empties out, so the
    /// caller's `pruned != stored` comparison stays meaningful.
    @Test("Sections and keys survive an empty result")
    func keysSurviveEmptying() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["real.owner:Thing"],
            "hidden": ["com.apple.controlcenter:Thing"],
        ])
        #expect(pruned.keys.sorted() == ["hidden", "visible"])
        #expect(pruned["hidden"]?.isEmpty == true)
    }

    /// A volatile-title owner saved in one section under one sample and in
    /// another section under a later one leaves two entries that canonicalize
    /// to the same key. Deduplicating per section keeps both, and the section
    /// lookups built from this order then resolve that key by whichever
    /// section the dictionary iterated last — a nondeterministic answer to
    /// "where does this item belong".
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

    /// Same shape for the metric owner, and across all three sections.
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

    /// Distinct identities from the same owner must not be collapsed into one
    /// another just because they share a namespace.
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

    /// A section key outside the known three is not part of the precedence
    /// order and must keep its entries untouched rather than being silently
    /// emptied by the dedupe pass.
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

    /// Source-PID resolution handed Control Center's WiFi item Thaw's own PID,
    /// and the layout kept the result. Nothing live will carry that name.
    @Test("A foreign item saved under Thaw's namespace is dropped")
    func dropsForeignEntryUnderOwnNamespace() {
        let own = Constants.bundleIdentifier
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(own):WiFi", "us.zoom.xos:Item-0"],
        ])
        #expect(pruned["visible"] == ["us.zoom.xos:Item-0"])
    }

    /// The reason this rule has to run before the provisional-duplicate check
    /// rather than after it. Left in place, the misattributed entry counts as a
    /// "real owner" of the title `WiFi`, which makes the genuine Control Center
    /// item look like the poisoned copy and deletes the wrong one — the exact
    /// state #927's reporter was in.
    @Test("The genuine Control Center twin survives its misattributed copy")
    func keepsGenuineTwinOfMisattributedEntry() {
        let own = Constants.bundleIdentifier
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["\(own):WiFi", "com.apple.controlcenter:WiFi"],
        ])
        #expect(pruned["visible"] == ["com.apple.controlcenter:WiFi"])
    }

    /// Thaw's own items are the point of the namespace and must survive.
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

    /// The reporter carried six clones under one owner, all planned against on
    /// every apply.
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

    /// An item that merely mentions the clone name is not one.
    @Test("A title that only resembles a clone name survives")
    func keepsLookalikeCloneTitle() {
        let entry = "com.example.app:System Status Item Clone Manager"
        let pruned = LayoutSolver.prunedSectionOrder(["visible": [entry]])
        #expect(pruned["visible"] == [entry])
    }
}
