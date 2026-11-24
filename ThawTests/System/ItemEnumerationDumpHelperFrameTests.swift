//
//  ItemEnumerationDumpHelperFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw
import ThawAXCore

@MainActor
@Suite("Item dump helper frames")
struct ItemEnumerationDumpHelperFrameTests {
    private static func item(helperFrame: CGRect?) -> ItemEnumerationDump.DumpedItem {
        ItemEnumerationDump.DumpedItem(
            index: 0, occurrence: 0, role: nil, title: nil, identifier: nil, description: nil,
            help: nil, valueDescription: nil, stringValue: nil,
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, childCount: 0, innerAttributes: nil,
            helperFrame: helperFrame.map(ItemEnumerationDump.HelperFrame.init)
        )
    }

    @Test("An item from a report without helper frames decodes, and a new one keeps its helper frame")
    func itemsDecodeWithAndWithoutHelperFrame() throws {
        let old = Data(#"{"index":0,"occurrence":0,"frameX":0,"frameY":0,"frameWidth":0,"frameHeight":0,"childCount":0}"#.utf8)
        #expect(try JSONDecoder().decode(ItemEnumerationDump.DumpedItem.self, from: old).helperFrame == nil)

        let item = Self.item(helperFrame: CGRect(x: 1264, y: 0, width: 38, height: 30))
        let decoded = try JSONDecoder().decode(ItemEnumerationDump.DumpedItem.self, from: JSONEncoder().encode(item))
        #expect(decoded.helperFrame == item.helperFrame)
        #expect(decoded.helperFrame?.frameX == 1264)
    }

    @Test("Only items the in-process walk found no frame for are read again, and only those the helper framed count")
    func helperFramesAreReadAndCountedOnlyWhenMissing() {
        let element = AXElement.application(getpid())
        #expect(ItemEnumerationDump.helperFrame(of: element, appFrame: CGRect(x: 0, y: 0, width: 20, height: 24)) == nil)
        #expect(ItemEnumerationDump.helperFrame(of: element, appFrame: nil) == nil)

        let apps = [ItemEnumerationDump.DumpedApp(
            bundleIdentifier: "com.example.app",
            processIdentifier: 42,
            items: [Self.item(helperFrame: CGRect(x: 0, y: 0, width: 20, height: 24)), Self.item(helperFrame: nil)]
        )]
        #expect(ItemEnumerationDump.helperFramedCount(apps) == 1)
    }
}
