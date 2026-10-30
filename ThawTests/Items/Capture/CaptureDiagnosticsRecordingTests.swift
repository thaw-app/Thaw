//
//  CaptureDiagnosticsRecordingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import ImageIO
import MenuBarModel
import Testing
@testable import Thaw

/// Sampled crops land in a folder the test owns; the budgets are process-wide, so each test uses its own owner PID.
@Suite("Capture diagnostics save sampled crops")
struct CaptureDiagnosticsRecordingTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: ScratchDefaults.name("CaptureDiagnosticsRecordingTests"), directoryHint: .isDirectory)

    private static func item(ownerPID: pid_t) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.diagnostics"), title: "Item", instanceIndex: 0),
            windowID: 7778,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: CGRect(x: 800, y: 0, width: 22, height: 24),
            title: "Item",
            isOnScreen: true
        )
    }

    private static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func savedImages(prefix: String) throws -> [CGImage] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .compactMap { url in
                CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            }
    }

    @Test("A cleaned crop is saved as a PNG of its own size, three per item at most")
    func cleanedCropIsSaved() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = Self.item(ownerPID: 999_801)
        for _ in 0 ..< 4 {
            CaptureDiagnostics.recordCleaned(Self.image(width: 18, height: 12), item: item, source: "test", isEnabled: true, directory: directory)
        }
        let saved = try savedImages(prefix: "cleaned-")
        #expect(saved.count == 3)
        #expect(saved.allSatisfy { $0.width == 18 && $0.height == 12 })
    }

    @Test("A raw crop is saved under its own name")
    func rawCropIsSaved() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        CaptureDiagnostics.record(
            Self.image(width: 10, height: 8), item: Self.item(ownerPID: 999_802),
            bounds: CGRect(x: 0, y: 0, width: 10, height: 8), source: "test", isEnabled: true, directory: directory
        )
        let saved = try savedImages(prefix: "crop-")
        #expect(saved.map(\.width) == [10])
        #expect(try savedImages(prefix: "cleaned-").isEmpty)
    }

    @Test("Nothing is saved with diagnostics off or for an image larger than a menu bar item")
    func skippedCrops() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = Self.item(ownerPID: 999_803)
        CaptureDiagnostics.recordCleaned(Self.image(width: 10, height: 8), item: item, source: "test", isEnabled: false, directory: directory)
        CaptureDiagnostics.recordCleaned(Self.image(width: 513, height: 8), item: item, source: "test", isEnabled: true, directory: directory)
        CaptureDiagnostics.recordCleaned(Self.image(width: 10, height: 129), item: item, source: "test", isEnabled: true, directory: directory)
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 8)
        CaptureDiagnostics.record(Self.image(width: 10, height: 8), item: item, bounds: bounds, source: "test", isEnabled: false, directory: directory)
        CaptureDiagnostics.record(Self.image(width: 600, height: 8), item: item, bounds: bounds, source: "test", isEnabled: true, directory: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("A folder that cannot be made saves nothing and does not throw")
    func uncreatableFolder() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker", directoryHint: .notDirectory)
        try Data("x".utf8).write(to: blocker)
        let item = Self.item(ownerPID: 999_804)
        let target = blocker.appending(path: "samples", directoryHint: .isDirectory)
        CaptureDiagnostics.recordCleaned(Self.image(width: 10, height: 8), item: item, source: "test", isEnabled: true, directory: target)
        CaptureDiagnostics.record(
            Self.image(width: 10, height: 8), item: item, bounds: .zero, source: "test", isEnabled: true, directory: target
        )
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("Frame comparisons are off with diagnostics off and limited to three per item")
    func frameComparisonBudget() {
        #expect(!CaptureDiagnostics.shouldCompareFrame(ownerPID: 999_805, identity: "frame", isEnabled: false))
        let answers = (0 ..< 4).map { _ in
            CaptureDiagnostics.shouldCompareFrame(ownerPID: 999_805, identity: "frame", isEnabled: true)
        }
        #expect(answers == [true, true, true, false])
    }

    @Test("Samples go to a folder named for this process")
    func sampleDirectoryIsPerProcess() {
        let directory = CaptureDiagnostics.sampleDirectory
        #expect(directory.lastPathComponent == "ThawCaptureDiagnostics-\(ProcessInfo.processInfo.processIdentifier)")
        #expect(directory.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL)
    }
}
