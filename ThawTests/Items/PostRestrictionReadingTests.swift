//
//  PostRestrictionReadingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw
import ThawCapture

@MainActor
@Suite("The post-restriction repair brings its picture of the bar into the lane")
struct PostRestrictionReadingTests {
    private let barFrame = CGRect(x: 0, y: 0, width: 200, height: 24)

    private func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: CGWindowID(100 + Int(x)),
            ownerPID: 999_991,
            sourcePID: 999_991,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// A bar that is transparent except for an opaque block where `drawn` sits.
    private func capture(drawing drawn: MenuBarItem) throws -> ScreenCapture.MenuBarHostingCapture {
        let context = try #require(CGContext(
            data: nil, width: Int(barFrame.width), height: Int(barFrame.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(drawn.bounds)
        return try ScreenCapture.MenuBarHostingCapture(image: #require(context.makeImage()), windowFrame: barFrame, scale: 1)
    }

    @Test("An item that drew nothing in the picture is blank, and one that drew is not")
    func blankItemsComeFromThePicture() throws {
        let drawn = item("drawn", x: 20)
        let blank = item("blank", x: 120)
        let reading = try PostRestrictionReading(items: [drawn, blank], displayID: 1, barCapture: capture(drawing: drawn))

        #expect(reading.blankTags(among: [drawn, blank]) == [blank.tag])
    }

    @Test("Only the items asked about are judged")
    func onlyAskedItemsAreJudged() throws {
        let drawn = item("drawn", x: 20)
        let blank = item("blank", x: 120)
        let reading = try PostRestrictionReading(items: [drawn, blank], displayID: 1, barCapture: capture(drawing: drawn))

        #expect(reading.blankTags(among: [drawn]).isEmpty)
    }

    @Test("A reading without a picture calls nothing blank")
    func missingPictureCallsNothingBlank() {
        let blank = item("blank", x: 120)
        let reading = PostRestrictionReading(items: [blank], displayID: 1, barCapture: nil)

        #expect(reading.blankTags(among: [blank]).isEmpty)
    }

    @Test("A picture of another display is not used")
    func otherDisplayIsNotCovered() {
        let reading = PostRestrictionReading(items: [], displayID: 1, barCapture: nil)

        #expect(reading.covers(1))
        #expect(!reading.covers(2))
    }
}
