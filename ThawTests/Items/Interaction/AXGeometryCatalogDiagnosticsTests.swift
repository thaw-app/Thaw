//
//  AXGeometryCatalogDiagnosticsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("The AX geometry catalog explains why a crop was not validated")
struct AXGeometryCatalogDiagnosticsTests {
    private let rect = CGRect(x: 1000, y: 3, width: 22, height: 22)

    private func entry(_ pid: pid_t, _ root: Int, _ title: String?, _ frame: CGRect) -> AXGeometryCatalog.Entry {
        AXGeometryCatalog.Entry(ownerPID: pid, itemIndex: root, identityTitle: title, frame: frame)
    }

    @Test("A missing owner is named as absent")
    func ownerAbsent() {
        let summary = AXGeometryCatalog.diagnosticSummary(
            ownerPID: 10,
            identityTitle: "Clock",
            bounds: rect,
            in: [entry(20, 0, "Other", rect)]
        )
        #expect(summary.hasPrefix("reason=requested-owner-absent"))
        #expect(summary.contains("requestedPID=10"))
        #expect(summary.contains("overlappingEntries=1"))
        #expect(summary.contains("pid=20,root=0,identity=Other"))
    }

    @Test("An owner without the identity is unresolved")
    func identityUnresolved() {
        let summary = AXGeometryCatalog.diagnosticSummary(
            ownerPID: 10,
            identityTitle: "Clock",
            bounds: rect,
            in: [entry(10, 0, "A", rect), entry(10, 1, "B", rect.offsetBy(dx: 40, dy: 0))]
        )
        #expect(summary.hasPrefix("reason=identity-unresolved"))
        #expect(summary.contains("ownedRoots=2"))
        #expect(summary.contains("relevantTotal=2"))
    }

    @Test("An identity two roots share is reported as shared")
    func identitySharedByRoots() {
        let summary = AXGeometryCatalog.diagnosticSummary(
            ownerPID: 10,
            identityTitle: "Clock",
            bounds: rect,
            in: [entry(10, 0, "Clock", rect), entry(10, 1, "Clock", rect)]
        )
        #expect(summary.hasPrefix("reason=identity-shared-by-roots"))
        #expect(summary.contains("identifiedEntries=2"))
    }

    @Test("A single identified root blocked by another root overlaps it")
    func overlappingOtherRoot() {
        let summary = AXGeometryCatalog.diagnosticSummary(
            ownerPID: 10,
            identityTitle: "Clock",
            bounds: rect,
            in: [entry(10, 0, "Clock", rect), entry(30, 0, nil, rect)]
        )
        #expect(summary.hasPrefix("reason=overlapping-other-root"))
        #expect(summary.contains("identity=nil"))
    }

    @Test("Long titles are cut and at most six entries are listed")
    func summaryIsBounded() {
        let longTitle = String(repeating: "x", count: 300)
        let entries = (0 ..< 10).map { entry(10, $0, longTitle, rect) }
        let summary = AXGeometryCatalog.diagnosticSummary(ownerPID: 10, identityTitle: longTitle, bounds: rect, in: entries)
        #expect(summary.contains("requestedTitle=\(String(repeating: "x", count: 100)) "))
        #expect(summary.components(separatedBy: "pid=10,root=").count - 1 == 6)
        #expect(summary.contains("snapshotEntries=10"))
    }

    @Test("A snapshot of processes that are not running is empty")
    func snapshotOfAbsentProcesses() async {
        let entries = await AXGeometryCatalog.snapshot(hostProcessIdentifiers: [999_981, 999_982])
        #expect(entries.isEmpty)
    }

    @Test("Only Thaw's own collapsed dividers are collapsed")
    func collapsedDividerNeedsOwnProcess() {
        let own = ProcessInfo.processInfo.processIdentifier
        let thin = CGRect(x: 0, y: 0, width: 2, height: 22)
        #expect(entry(own, 0, MenuBarItemTag.hiddenControlItem.title, thin).isCollapsedThawDivider)
        #expect(entry(own, 0, MenuBarItemTag.visibleControlItem.title, .zero).isCollapsedThawDivider)
        #expect(!entry(own, 0, MenuBarItemTag.hiddenControlItem.title, rect).isCollapsedThawDivider)
        #expect(!entry(own + 1, 0, MenuBarItemTag.alwaysHiddenControlItem.title, thin).isCollapsedThawDivider)
        #expect(!entry(own, 0, "Something", thin).isCollapsedThawDivider)
    }
}
