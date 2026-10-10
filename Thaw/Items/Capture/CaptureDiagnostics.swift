//
//  CaptureDiagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ImageIO
import MenuBarModel
import os.lock
import UniformTypeIdentifiers

nonisolated enum CaptureDiagnostics {
    struct SamplingBudget {
        private var counts: [String: Int] = [:]
        private var total = 0

        mutating func reserve(for key: String) -> Int? {
            guard total < 96, counts[key, default: 0] < 3 else { return nil }
            counts[key, default: 0] += 1
            total += 1
            return total
        }
    }

    private static let pixelSamples = OSAllocatedUnfairLock(initialState: SamplingBudget())
    private static let cleanedSamples = OSAllocatedUnfairLock(initialState: SamplingBudget())
    private static let frameSamples = OSAllocatedUnfairLock(initialState: SamplingBudget())
    private static let log = DiagLog(category: "CaptureDiagnostics")

    /// Records the cached crop after background removal to distinguish separation failures from other pixel pollution.
    static func recordCleaned(_ image: CGImage, item: MenuBarItem, source: String) {
        guard DiagnosticLogger.shared.isEnabled,
              image.width <= 512, image.height <= 128,
              let sample = cleanedSamples.withLock({ $0.reserve(for: "\(item.ownerPID):\(item.uniqueIdentifier)") })
        else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThawCaptureDiagnostics-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("cleaned-\(sample).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            log.info(
                "[CapturePixelTrace] cleaned item=\(item.uniqueIdentifier) source=\(source) " +
                    "presence=\(String(describing: image.glyphPresenceOverNearUniformBackground())) " +
                    "raw=\(url.path)"
            )
        } catch {
            log.debug("[CapturePixelTrace] could not save cleaned crop: \(error)")
        }
    }

    static func shouldCompareFrame(ownerPID: pid_t, identity: String) -> Bool {
        guard DiagnosticLogger.shared.isEnabled else { return false }
        return frameSamples.withLock { $0.reserve(for: "\(ownerPID):\(identity)") != nil }
    }

    /// Keep a few raw item crops so geometry failures can be distinguished
    /// from background-removal failures without recording the whole display.
    static func record(_ image: CGImage, item: MenuBarItem, bounds: CGRect, source: String) {
        guard DiagnosticLogger.shared.isEnabled,
              image.width <= 512, image.height <= 128
        else { return }
        let key = "\(item.ownerPID):\(item.uniqueIdentifier)"
        let sample = pixelSamples.withLock { $0.reserve(for: key) }
        guard let sample else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThawCaptureDiagnostics-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("crop-\(sample).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            log.info(
                "[CapturePixelTrace] item=\(item.uniqueIdentifier) owner=\(item.ownerPID) " +
                    "source=\(source) bounds=\(bounds) " +
                    "presence=\(String(describing: image.glyphPresenceOverNearUniformBackground())) " +
                    "raw=\(url.path)"
            )
        } catch {
            log.debug("[CapturePixelTrace] could not save crop: \(error)")
        }
    }
}
