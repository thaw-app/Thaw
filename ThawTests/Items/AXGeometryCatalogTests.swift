//
//  AXGeometryCatalogTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("AX geometry catalog correlation")
struct AXGeometryCatalogTests {
    @Test("A blank MenuBarAgent group retains its inner menu item's identity")
    func groupedSystemItemUsesInnerIdentity() {
        let identity = AXGeometryCatalog.identityTitle(
            namespace: .menuBarAgent,
            attributes: .init(),
            descendants: [.init(identifier: "com.apple.menuextra.sound")]
        )
        #expect(identity == "com.apple.menuextra.sound")
    }

    @Test("Capture resolves unnamed Time Machine beside Siri using discovery's identity")
    func timeMachineCaptureIdentity() {
        let title = AXGeometryCatalog.identityTitle(namespace: .systemUIServer, attributes: .init(), descendants: [])
        #expect(title == MenuBarItemTag.timeMachine.title)
        let rect = CGRect(x: 1642, y: 4, width: 22, height: 22)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 798, itemIndex: 1, identityTitle: title, frame: rect),
            AXGeometryCatalog.Entry(
                ownerPID: 798,
                itemIndex: 0,
                identityTitle: "Siri",
                frame: CGRect(x: 1807, y: 3, width: 17, height: 24)
            ),
        ]
        #expect(AXGeometryCatalog.match(
            ownerPID: 798, identityTitle: MenuBarItemTag.timeMachine.title, bounds: rect, in: snapshot
        ) == .frame(rect))
    }

    @Test("Legacy identity resolution leaves Siri and other anonymous hosts alone")
    func legacyIdentityIsScoped() {
        #expect(AXGeometryCatalog.identityTitle(
            namespace: .systemUIServer, attributes: .init(title: "Siri"), descendants: []
        ) == "Siri")
        #expect(AXGeometryCatalog.identityTitle(
            namespace: .menuBarAgent, attributes: .init(), descendants: []
        ) == nil)
    }

    @Test("A neighbour cannot validate another process's stale crop")
    func crossOwnerReplacementIsRejected() {
        let rect = CGRect(x: 851, y: 4.5, width: 24, height: 24)
        let snapshot = [AXGeometryCatalog.Entry(ownerPID: 2, itemIndex: 0, identityTitle: "Item-0", frame: rect)]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "Item-0", bounds: rect, in: snapshot) == .ambiguous)
    }

    @Test("Collapsed Thaw controls do not claim a neighbouring glyph", arguments: [
        "Thaw.ControlItem.Hidden", "Thaw.ControlItem.AlwaysHidden", "Thaw.ControlItem.Visible",
    ])
    func collapsedDividerDoesNotInvalidateCrop(title: String) {
        // Droppy's live crop overlapped the 2-point divider by 1.5 points.
        let rect = CGRect(x: 1582, y: 3, width: 32, height: 24)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: "DroppyMenuBar", frame: rect),
            AXGeometryCatalog.Entry(
                ownerPID: ProcessInfo.processInfo.processIdentifier,
                itemIndex: 1,
                identityTitle: title,
                frame: CGRect(x: 1581.5, y: 3, width: 2, height: 24)
            ),
        ]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "DroppyMenuBar", bounds: rect, in: snapshot) == .frame(rect))
    }

    @Test("Visible dividers and other processes still block overlapping crops", arguments: [
        ("Thaw.ControlItem.Hidden", CGFloat(3), true),
        ("Thaw.ControlItem.AlwaysHidden", CGFloat(16), true),
        ("Thaw.ControlItem.Visible", CGFloat(21), true),
        ("Thaw.ControlItem.Hidden", CGFloat(2), false),
        ("Item-0", CGFloat(2), true),
    ])
    func renderingOrForeignRootsRemainAmbiguous(title: String, width: CGFloat, isThaw: Bool) {
        let rect = CGRect(x: 1582, y: 3, width: 32, height: 24)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: "DroppyMenuBar", frame: rect),
            AXGeometryCatalog.Entry(
                ownerPID: isThaw ? ProcessInfo.processInfo.processIdentifier : 2,
                itemIndex: 1,
                identityTitle: title,
                frame: CGRect(x: 1581.5, y: 3, width: width, height: 24)
            ),
        ]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "DroppyMenuBar", bounds: rect, in: snapshot) == .ambiguous)
    }

    @Test("Separate anonymous items sharing a frame remain ambiguous")
    func sameOwnerAnonymousItemsAreNotDescendants() {
        let rect = CGRect(x: 862, y: 4.5, width: 33, height: 24)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: nil, frame: rect),
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 1, identityTitle: nil, frame: rect),
        ]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "Item#", bounds: rect, in: snapshot) == .ambiguous)
    }

    @Test("A stable identity cannot be replaced by its same-process neighbour")
    func stableIdentityRejectsSubstitution() {
        let old = CGRect(x: 100, y: 4.5, width: 24, height: 24)
        let moved = CGRect(x: 150, y: 4.5, width: 24, height: 24)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: "CPU", frame: moved),
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 1, identityTitle: "Memory", frame: old),
        ]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "CPU", bounds: old, in: snapshot) == .ambiguous)
    }

    @Test("An identified item and its descendants keep one ownership")
    func identifiedDescendantsResolve() {
        let rect = CGRect(x: 100, y: 4.5, width: 24, height: 24)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: "CPU", frame: rect),
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: "CPU", frame: rect),
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 1, identityTitle: "Memory", frame: rect.offsetBy(dx: 50, dy: 0)),
        ]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "CPU", bounds: rect, in: snapshot) == .frame(rect))
    }

    @Test("A partial walk cannot turn anonymous siblings into one identified item")
    func unreadSiblingPreventsSingletonFallback() {
        let rect = CGRect(x: 100, y: 4.5, width: 24, height: 24)
        let snapshot = [
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: nil, frame: rect),
            AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 1, identityTitle: nil, frame: .zero),
        ]
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "Item-0", bounds: rect, in: snapshot) == .ambiguous)
    }

    @Test("An anonymous singleton validates, but a missing snapshot is only unavailable")
    func singletonAndTransientAbsence() {
        let rect = CGRect(x: 100, y: 4.5, width: 24, height: 24)
        let entry = AXGeometryCatalog.Entry(ownerPID: 1, itemIndex: 0, identityTitle: nil, frame: rect)
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "Item-0", bounds: rect, in: [entry]) == .frame(rect))
        #expect(AXGeometryCatalog.match(ownerPID: 1, identityTitle: "Item-0", bounds: rect, in: []) == .unavailable)
    }

    @Test("An unmoved item resolves even when its own button shares the frame")
    func sameFrameDescendantIsNotATie() {
        let frame = CGRect(x: 1323, y: 3, width: 17, height: 24)
        // An item and the button inside it are two visited elements publishing
        // one rect. That is one answer, not an ambiguity.
        let snapshot = [frame, frame]
        #expect(AXGeometryCatalog.frame(overlapping: frame, in: snapshot) == frame)
    }

    @Test("Two distinct frames with equal overlap stay ambiguous")
    func distinctFramesWithEqualOverlapTie() {
        let target = CGRect(x: 100, y: 0, width: 20, height: 24)
        let left = CGRect(x: 90, y: 0, width: 20, height: 24)
        let right = CGRect(x: 110, y: 0, width: 20, height: 24)
        #expect(AXGeometryCatalog.frame(overlapping: target, in: [left, right]) == nil)
    }

    @Test("A stale rect with no overlap resolves to nothing")
    func staleRectHasNoLiveFrame() {
        let snapshot = [CGRect(x: 1102, y: 4.5, width: 19, height: 24)]
        let stale = CGRect(x: 1049, y: 4.5, width: 19, height: 24)
        #expect(AXGeometryCatalog.frame(overlapping: stale, in: snapshot) == nil)
    }

    @Test("A rect that mostly overlaps one neighbour resolves to that neighbour")
    func partialOverlapPicksTheLargerIntersection() {
        let a = CGRect(x: 0, y: 0, width: 30, height: 24)
        let b = CGRect(x: 30, y: 0, width: 30, height: 24)
        let target = CGRect(x: 20, y: 0, width: 30, height: 24)
        #expect(AXGeometryCatalog.frame(overlapping: target, in: [a, b]) == b)
    }
}
