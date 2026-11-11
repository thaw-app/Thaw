//
//  CaptureDiagnosticsSampleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Settings › Tools enables Show Samples when it hears that a sample was written.
@MainActor
@Suite("Capture sample notice")
struct CaptureDiagnosticsSampleTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "CaptureDiagnosticsSampleTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private static func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }

    @Test("Writing a raw or cleaned sample posts the notice, and a disabled log posts none")
    func writingASamplePostsTheNotice() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try Self.image()
        let item = LayoutEditorWorld.item("Sample \(UUID().uuidString)")

        await confirmation("a notice per written sample", expectedCount: 2) { written in
            let observer = NotificationCenter.default.addObserver(forName: CaptureDiagnostics.didWriteSample, object: nil, queue: nil) { _ in
                written()
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            CaptureDiagnostics.record(image, item: item, bounds: .zero, source: "test", isEnabled: false, directory: directory)
            CaptureDiagnostics.record(image, item: item, bounds: .zero, source: "test", isEnabled: true, directory: directory)
            CaptureDiagnostics.recordCleaned(image, item: item, source: "test", isEnabled: true, directory: directory)
        }
    }
}
