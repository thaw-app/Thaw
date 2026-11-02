//
//  BackdropCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import ThawCapture

@Suite("Backdrop capture isolation")
struct BackdropCaptureTests {
    private let display = CGRect(x: -2048, y: 0, width: 2048, height: 1152)
    private let strip = CGRect(x: -2048, y: 0, width: 2048, height: 30)

    @Test func ordinaryWindowsCanSupplyTheMenuBarBackdrop() {
        #expect(allows(strip, level: kCGNormalWindowLevel))
    }

    @Test func ordinaryWindowsCannotBeCapturedBelowTheMenuBar() {
        let preview = CGRect(x: -2048, y: 0, width: 2048, height: 240)
        #expect(!allows(preview, level: kCGNormalWindowLevel))
        #expect(allows(preview, level: CGWindowLevelForKey(.desktopWindow)))
        #expect(allows(display, level: CGWindowLevelForKey(.desktopWindow)))
    }

    @Test func menuBarAndOverlayWindowsAreNotBackdropContent() {
        #expect(!allows(strip, level: kCGMainMenuWindowLevel))
        #expect(!allows(strip, level: CGWindowLevelForKey(.screenSaverWindow)))
    }

    @Test func captureMustStayOnOneDisplayAndIntersectTheWindow() {
        #expect(!allows(CGRect(x: -2050, y: 0, width: 2048, height: 30), level: kCGNormalWindowLevel))
        #expect(!ScreenCapture.isAllowedBackdropWindow(
            captureBounds: strip,
            windowBounds: CGRect(x: 0, y: 200, width: 100, height: 100),
            windowLevel: kCGNormalWindowLevel,
            displayBounds: display,
            menuBarHeight: 30
        ))
    }

    @Test func invalidBoundsAreRejected() {
        for bounds in [CGRect.null, .infinite, .zero, CGRect(x: 0, y: 0, width: -1, height: 30)] {
            #expect(!allows(bounds, level: CGWindowLevelForKey(.desktopWindow)))
        }
    }

    @Test func notchedDisplayUsesItsLiveBarHeight() {
        let tallStrip = CGRect(x: -2048, y: 0, width: 2048, height: 49)
        #expect(ScreenCapture.isAllowedBackdropWindow(
            captureBounds: tallStrip,
            windowBounds: display,
            windowLevel: kCGNormalWindowLevel,
            displayBounds: display,
            menuBarHeight: 49
        ))
        #expect(!allows(tallStrip, level: kCGNormalWindowLevel))
    }

    @Test func backdropRequestPreservesWindowOrderBoundsAndResolution() throws {
        let request = CaptureServiceRequest.backdrop(
            ids: [42, 17],
            screenBounds: strip,
            imageOptionRawValue: CGWindowImageOption.nominalResolution.rawValue
        )
        let decoded = try JSONDecoder().decode(
            CaptureServiceRequest.self, from: JSONEncoder().encode(request)
        )
        guard case let .backdrop(ids, bounds, options) = decoded else {
            Issue.record("Backdrop request did not survive the wire round trip")
            return
        }
        #expect(ids == [42, 17])
        #expect(bounds == strip)
        #expect(options == CGWindowImageOption.nominalResolution.rawValue)
    }

    private func allows(_ bounds: CGRect, level: CGWindowLevel) -> Bool {
        ScreenCapture.isAllowedBackdropWindow(
            captureBounds: bounds,
            windowBounds: display,
            windowLevel: level,
            displayBounds: display,
            menuBarHeight: 30
        )
    }
}
