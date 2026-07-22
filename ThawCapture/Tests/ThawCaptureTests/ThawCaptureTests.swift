//
//  ThawCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
@testable import ThawCapture
import Testing

@Suite("Thaw capture")
struct ThawCaptureTests {
    @Test
    func screenCapturePermissionChecksAllEligibleWindows() {
        #expect(
            ScreenCapture.permissionGranted(
                windowTitles: [nil, "Clock"],
                preflightResult: false
            )
        )
    }

    @Test
    func screenCapturePermissionUsesPreflightFallback() {
        #expect(
            ScreenCapture.permissionGranted(
                windowTitles: [nil],
                preflightResult: true
            )
        )
    }

    @Test
    func screenCapturePermissionRejectsUntitledWindowsWithoutPreflight() {
        #expect(
            !ScreenCapture.permissionGranted(
                windowTitles: [nil, nil],
                preflightResult: false
            )
        )
    }

    @Test
    func screenCapturePermissionPromptTemporarilyUsesRegularActivationPolicy() {
        var appliedPolicies = [NSApplication.ActivationPolicy]()
        var didActivate = false
        let restore = ScreenCapture.restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: .accessory,
            setActivationPolicy: { policy in
                appliedPolicies.append(policy)
                return true
            },
            activate: { didActivate = true }
        )
        #expect(appliedPolicies == [.regular])
        #expect(didActivate)
        restore?()
        #expect(appliedPolicies == [.regular, .accessory])
    }

    @Test
    func screenCapturePermissionPromptDoesNotRestoreAlreadyRegularApp() {
        var appliedPolicies = [NSApplication.ActivationPolicy]()
        var didActivate = false
        let restore = ScreenCapture.restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: .regular,
            setActivationPolicy: { policy in
                appliedPolicies.append(policy)
                return true
            },
            activate: { didActivate = true }
        )
        #expect(appliedPolicies.isEmpty)
        #expect(didActivate)
        #expect(restore == nil)
    }

    @Test
    func probeLoggingDefaultsToDisabled() {
        #expect(!ScreenCapture.isProbeLoggingEnabled())
    }

    @Test
    @available(macOS 27, *)
    func pixelBackedWindowFrameDoesNotDoubleScaleCaptureSize() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pixelWindowFrame = CGRect(x: 0, y: 0, width: 3024, height: 74)
        #expect(
            ScreenCapture.windowFrameAppearsPixelBacked(pixelWindowFrame, displayFrame: displayFrame)
        )
        let size = ScreenCapture.hostingCapturePixelSize(
            windowFrame: pixelWindowFrame,
            displayFrame: displayFrame,
            reportedScale: 2
        )
        #expect(size.width == 3024)
        #expect(size.height == 74)
    }

    @Test
    @available(macOS 27, *)
    func pointSpaceWindowFrameMultipliesByReportedScale() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pointWindowFrame = CGRect(x: 0, y: 0, width: 1512, height: 37)
        #expect(
            !ScreenCapture.windowFrameAppearsPixelBacked(pointWindowFrame, displayFrame: displayFrame)
        )
        let size = ScreenCapture.hostingCapturePixelSize(
            windowFrame: pointWindowFrame,
            displayFrame: displayFrame,
            reportedScale: 2
        )
        #expect(size.width == 3024)
        #expect(size.height == 74)
    }

    @Test
    @available(macOS 27, *)
    func normalizedHostingCaptureRewritesPixelBackedFrameToPoints() throws {
        let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pixelWindowFrame = CGRect(x: 0, y: 0, width: 3024, height: 74)
        let image = try #require(makeTestImage(width: 3024, height: 74))

        let normalized = try #require(
            ScreenCapture.normalizedHostingCapture(
                image: image,
                windowFrame: pixelWindowFrame,
                displayFrame: displayFrame,
                reportedScale: 2
            )
        )
        #expect(abs(normalized.scale - 2) < 0.001)
        #expect(abs(normalized.windowFrame.width - 1512) < 0.001)
        #expect(abs(normalized.windowFrame.height - 37) < 0.001)
        #expect(normalized.windowFrame.origin == displayFrame.origin)
    }

    @Test
    @available(macOS 27, *)
    func normalizedHostingCaptureDerivesScaleFromBitmapForPointFrames() throws {
        let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pointWindowFrame = CGRect(x: 0, y: 0, width: 1512, height: 37)
        let image = try #require(makeTestImage(width: 3024, height: 74))

        let normalized = try #require(
            ScreenCapture.normalizedHostingCapture(
                image: image,
                windowFrame: pointWindowFrame,
                displayFrame: displayFrame,
                reportedScale: 1 // deliberately wrong — bitmap says 2×
            )
        )
        #expect(abs(normalized.scale - 2) < 0.001)
        #expect(normalized.windowFrame == pointWindowFrame)
    }

    @Test
    @available(macOS 27, *)
    func windowMatchesMenuBarStripGeometryAcceptsPointAndPixelFrames() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(
            ScreenCapture.windowMatchesMenuBarStripGeometry(
                CGRect(x: 0, y: 0, width: 1512, height: 37),
                displayFrame: displayFrame
            )
        )
        #expect(
            ScreenCapture.windowMatchesMenuBarStripGeometry(
                CGRect(x: 0, y: 0, width: 3024, height: 74),
                displayFrame: displayFrame
            )
        )
        #expect(
            !ScreenCapture.windowMatchesMenuBarStripGeometry(
                CGRect(x: 0, y: 0, width: 200, height: 24),
                displayFrame: displayFrame
            )
        )
    }

    @Test
    @available(macOS 27, *)
    func menuBarDisplayStripFramePinsToDisplayTop() {
        let displayFrame = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let strip = ScreenCapture.menuBarDisplayStripFrame(displayFrame: displayFrame, height: 40)
        #expect(strip.origin == displayFrame.origin)
        #expect(strip.width == displayFrame.width)
        #expect(strip.height == 40)
    }

    @Test
    @available(macOS 27, *)
    func menuBarDisplayStripFrameClampsToDisplayHeight() {
        let displayFrame = CGRect(x: 0, y: 0, width: 800, height: 24)
        let strip = ScreenCapture.menuBarDisplayStripFrame(displayFrame: displayFrame, height: 40)
        #expect(strip.height == 24)
    }

    private func makeTestImage(width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        return context.makeImage()
    }
}
