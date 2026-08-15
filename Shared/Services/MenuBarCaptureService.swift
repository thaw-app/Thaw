//
//  MenuBarCaptureService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Offscreen menu-bar capture XPC vocabulary.
///
/// SkyLight's `SLWindowListCreateImageFromArray` leaks a small dictionary in
/// the calling process per successful call (commit `0e045faf`). This service
/// exists so that leak can be reclaimed by exiting the helper. Visible-section
/// icons stay on ScreenCaptureKit in the app; Always Hidden stays at 1 fps.
nonisolated enum MenuBarCaptureService {
    static let name = "com.stonerl.Thaw.MenuBarCaptureService"

    /// Exit after this many successful SkyLight composites.
    ///
    /// Commit `0e045faf` measured ~168 B per leaked dictionary. 1,800 calls is
    /// about 60 s at 30 fps and ~300 KB of helper growth before recycle.
    static let recycleAfterCaptureCount = 1_800

    static let maxWindowCount = 64
    static let maxBytesPerFrame = 4 * 1_024 * 1_024
    static let minAlwaysHiddenInterval: TimeInterval = 1

    /// Premultiplied BGRA, little-endian — the capture-path pixel layout.
    static let bgraBitmapInfo: UInt32 =
        CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue
}

nonisolated extension MenuBarCaptureService {
    struct CaptureBatchRequest: Codable, Equatable {
        var requestID: UInt64
        var windowIDs: [CGWindowID]
        var optionRawValue: UInt32
        var expectedScale: Double
    }

    struct Frame: Codable, Equatable {
        var windowID: CGWindowID
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var scale: Double
        var pixels: Data
    }

    struct CaptureBatchResponse: Codable, Equatable {
        var requestID: UInt64
        var instanceID: UInt64
        var frames: [Frame]
    }

    enum Request: Codable, Equatable {
        case start
        case configureLogging(filePath: String)
        case captureBatch(CaptureBatchRequest)
        case recycle
    }

    enum Response: Codable, Equatable {
        case start
        case configureLogging
        case captureBatch(CaptureBatchResponse)
        case recycle
    }
}

nonisolated extension MenuBarCaptureService {
    /// Drops zeros, duplicates, non-members, and anything past ``maxWindowCount``.
    static func validatedWindowIDs(
        _ ids: [CGWindowID],
        allowed: Set<CGWindowID>
    ) -> [CGWindowID] {
        var seen = Set<CGWindowID>()
        var result = [CGWindowID]()
        result.reserveCapacity(min(ids.count, maxWindowCount))
        for id in ids {
            guard id != 0, !seen.contains(id), allowed.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
            if result.count == maxWindowCount { break }
        }
        return result
    }

    static func isValidBGRAFrame(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        pixelCount: Int
    ) -> Bool {
        guard width > 0, height > 0 else { return false }
        guard width <= Bridging.maximumCaptureDimension,
              height <= Bridging.maximumCaptureDimension
        else { return false }
        guard bytesPerRow >= width * 4 else { return false }
        let expected = bytesPerRow * height
        guard pixelCount >= expected, expected <= maxBytesPerFrame else { return false }
        return true
    }

    static func shouldRecycle(
        captureCount: Int,
        budget: Int = recycleAfterCaptureCount
    ) -> Bool {
        captureCount >= budget
    }

    static func acceptedResponse(
        requestID: UInt64,
        response: Response
    ) -> CaptureBatchResponse? {
        guard case let .captureBatch(batch) = response, batch.requestID == requestID else {
            return nil
        }
        return batch
    }

    static func encodeBGRA(_ image: CGImage) -> (pixels: Data, bytesPerRow: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bgraBitmapInfo
        ), let dataPtr = context.data else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let stride = context.bytesPerRow
        let count = stride * height
        guard count > 0, count <= maxBytesPerFrame else { return nil }
        return (Data(bytes: dataPtr, count: count), stride)
    }

    static func makeImage(from frame: Frame) -> CGImage? {
        guard isValidBGRAFrame(
            width: frame.width,
            height: frame.height,
            bytesPerRow: frame.bytesPerRow,
            pixelCount: frame.pixels.count
        ) else {
            return nil
        }
        guard frame.scale > 0, frame.scale.isFinite else { return nil }
        guard let provider = CGDataProvider(data: frame.pixels as CFData) else {
            return nil
        }
        return CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bgraBitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func isFullyTransparentBGRA(
        pixels: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> Bool {
        guard isValidBGRAFrame(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            pixelCount: pixels.count
        ) else {
            return true
        }
        return pixels.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return true
            }
            for row in 0 ..< height {
                let rowBase = base + row * bytesPerRow
                for column in 0 ..< width {
                    if rowBase[column * 4 + 3] != 0 {
                        return false
                    }
                }
            }
            return true
        }
    }
}
