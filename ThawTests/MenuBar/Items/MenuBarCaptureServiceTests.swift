//
//  MenuBarCaptureServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar capture service")
struct MenuBarCaptureServiceTests {
    @Test("The service name is the reverse-DNS Mach service identifier")
    func serviceName() {
        #expect(MenuBarCaptureService.name == "com.stonerl.Thaw.MenuBarCaptureService")
    }

    @Test("A capture batch request survives a round trip")
    func captureBatchRequestRoundTrip() throws {
        let original = MenuBarCaptureService.Request.captureBatch(
            MenuBarCaptureService.CaptureBatchRequest(
                requestID: 7,
                windowIDs: [12, 34],
                optionRawValue: 1,
                expectedScale: 2
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarCaptureService.Request.self, from: data)
        #expect(decoded == original)
    }

    @Test("A capture batch response keeps frames across a round trip")
    func captureBatchResponseRoundTrip() throws {
        let frame = MenuBarCaptureService.Frame(
            windowID: 99,
            width: 2,
            height: 1,
            bytesPerRow: 8,
            scale: 2,
            pixels: Data([1, 2, 3, 4, 5, 6, 7, 8])
        )
        let original = MenuBarCaptureService.Response.captureBatch(
            MenuBarCaptureService.CaptureBatchResponse(
                requestID: 3,
                instanceID: 11,
                frames: [frame]
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarCaptureService.Response.self, from: data)
        #expect(decoded == original)
    }

    @Test("Window ID validation drops zeros, duplicates, strangers, and overflow")
    func windowIDValidation() {
        let allowed: Set<CGWindowID> = [1, 2, 3]
        #expect(
            MenuBarCaptureService.validatedWindowIDs([0, 1, 1, 2, 99, 3], allowed: allowed)
                == [1, 2, 3]
        )
        #expect(MenuBarCaptureService.validatedWindowIDs([], allowed: allowed).isEmpty)

        let tooMany = (1 ... 80).map { CGWindowID($0) }
        let manyAllowed = Set(tooMany)
        #expect(
            MenuBarCaptureService.validatedWindowIDs(tooMany, allowed: manyAllowed).count
                == MenuBarCaptureService.maxWindowCount
        )
    }

    @Test("BGRA frame validation rejects empty, oversized, and short buffers")
    func bgraValidation() {
        #expect(
            MenuBarCaptureService.isValidBGRAFrame(
                width: 2,
                height: 2,
                bytesPerRow: 8,
                pixelCount: 16
            )
        )
        #expect(
            !MenuBarCaptureService.isValidBGRAFrame(
                width: 0,
                height: 2,
                bytesPerRow: 8,
                pixelCount: 16
            )
        )
        #expect(
            !MenuBarCaptureService.isValidBGRAFrame(
                width: 2,
                height: 2,
                bytesPerRow: 4,
                pixelCount: 16
            )
        )
        #expect(
            !MenuBarCaptureService.isValidBGRAFrame(
                width: 2,
                height: 2,
                bytesPerRow: 8,
                pixelCount: 8
            )
        )
        #expect(
            !MenuBarCaptureService.isValidBGRAFrame(
                width: Bridging.maximumCaptureDimension + 1,
                height: 1,
                bytesPerRow: (Bridging.maximumCaptureDimension + 1) * 4,
                pixelCount: (Bridging.maximumCaptureDimension + 1) * 4
            )
        )
    }

    @Test("A stale capture response is dropped")
    func staleResponseIsDropped() {
        let response = MenuBarCaptureService.Response.captureBatch(
            MenuBarCaptureService.CaptureBatchResponse(
                requestID: 2,
                instanceID: 1,
                frames: []
            )
        )
        #expect(MenuBarCaptureService.acceptedResponse(requestID: 1, response: response) == nil)
        #expect(MenuBarCaptureService.acceptedResponse(requestID: 2, response: response) != nil)
        #expect(MenuBarCaptureService.acceptedResponse(requestID: 2, response: .start) == nil)
    }

    @Test("Recycle trips at the capture budget")
    func recycleBudget() {
        #expect(!MenuBarCaptureService.shouldRecycle(captureCount: 1_799, budget: 1_800))
        #expect(MenuBarCaptureService.shouldRecycle(captureCount: 1_800, budget: 1_800))
        #expect(MenuBarCaptureService.shouldRecycle(captureCount: 1_801, budget: 1_800))
    }

    @Test("BGRA encode and decode round-trips pixels")
    func bgraRoundTrip() throws {
        let source = try makeOpaqueImage(width: 4, height: 3)
        let encoded = try #require(MenuBarCaptureService.encodeBGRA(source))
        let frame = MenuBarCaptureService.Frame(
            windowID: 1,
            width: source.width,
            height: source.height,
            bytesPerRow: encoded.bytesPerRow,
            scale: 2,
            pixels: encoded.pixels
        )
        let decoded = try #require(MenuBarCaptureService.makeImage(from: frame))
        #expect(decoded.width == source.width)
        #expect(decoded.height == source.height)
        let roundTrip = try #require(MenuBarCaptureService.encodeBGRA(decoded))
        #expect(roundTrip.pixels == encoded.pixels)
    }

    @Test("A fully transparent BGRA buffer is detected")
    func transparentBGRA() {
        let pixels = Data(repeating: 0, count: 16)
        #expect(
            MenuBarCaptureService.isFullyTransparentBGRA(
                pixels: pixels,
                width: 2,
                height: 2,
                bytesPerRow: 8
            )
        )
        var opaque = pixels
        opaque[3] = 255
        #expect(
            !MenuBarCaptureService.isFullyTransparentBGRA(
                pixels: opaque,
                width: 2,
                height: 2,
                bytesPerRow: 8
            )
        )
    }
}
