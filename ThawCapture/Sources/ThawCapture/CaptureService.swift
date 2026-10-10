//
//  CaptureService.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Shared XPC wire types move ScreenCaptureKit's per-call SkyLight dictionary leak out of the UI process.
/// Each request produces one frame; only lifecycle counters persist per client.
public enum CaptureService {
    /// The app's base bundle identifier, without any
    /// THAW_BUNDLE_ID_SUFFIX the build applies.
    public static let baseAppBundleIdentifier = "com.stonerl.Thaw"

    /// The helper's base bundle identifier, without any
    /// THAW_BUNDLE_ID_SUFFIX the build applies.
    public static let baseServiceBundleIdentifier = "com.stonerl.Thaw.MenuBarCaptureService"

    /// Append the service component after the app's debug suffix, matching the helper's bundle ID.
    /// Appending the suffix after the service component causes XPC's "No such process" failure.
    public static func serviceName(forAppBundleIdentifier appBundleIdentifier: String?) -> String {
        guard
            let appBundleIdentifier,
            appBundleIdentifier.hasPrefix(baseAppBundleIdentifier)
        else {
            return baseServiceBundleIdentifier
        }
        let serviceComponent = baseServiceBundleIdentifier.dropFirst(baseAppBundleIdentifier.count)
        return appBundleIdentifier + serviceComponent
    }
}

// MARK: - Request

/// Display requests let the helper resolve macOS 27 hosting-window or strip geometry without caller-supplied IDs.
/// Window requests mirror ScreenCapture.captureWindows; the helper re-enumerates menu-bar and wallpaper windows and rejects other IDs.
public enum CaptureServiceRequest: Codable, Sendable {
    /// Captures windows front to back; screenBounds overrides their union and imageOptionRawValue holds CGWindowImageOption.
    /// scale is advisory (0 means native); capture uses the SCK filter's scale, or 1x for nominalResolution.
    case windows(ids: [CGWindowID], screenBounds: CGRect?, imageOptionRawValue: UInt32, scale: Double)

    /// MenuBarAgent's composited menu bar hosting window on a display.
    case menuBarHostingWindow(displayID: CGDirectDisplayID)

    /// The on-screen menu bar strip of a display, with foreign overlays
    /// above the bar excluded.
    case menuBarDisplayStrip(displayID: CGDirectDisplayID)
    /// SkyLight captures app-owned bar windows that hosting-window and SCK filters cannot address.
    /// The helper re-reads the frame and rejects anything other than a menu bar strip.
    case ownerBarWindow(windowID: CGWindowID)
}

// MARK: - Reply

/// Captured pixels and crop geometry use plain BGRA bytes: strips are small and XPC Codable has no IOSurface carrier.
public struct CaptureServiceFrame: Codable, Sendable {
    /// Premultiplied BGRA (32 bits per pixel, little-endian) pixel rows.
    public let pixelData: Data

    /// Bitmap width in device pixels.
    public let pixelWidth: Int

    /// Bitmap height in device pixels.
    public let pixelHeight: Int

    /// Stride of one bitmap row in bytes.
    public let bytesPerRow: Int

    /// Global Y-down point frame; subtract its origin from an item's frame, then multiply by scale to map into pixels.
    public let windowFrame: CGRect

    /// Device pixels per point of the bitmap.
    public let scale: Double

    public init(
        pixelData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        bytesPerRow: Int,
        windowFrame: CGRect,
        scale: Double
    ) {
        self.pixelData = pixelData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.windowFrame = windowFrame
        self.scale = scale
    }

    /// The frame's size in points.
    public var pointSize: CGSize {
        windowFrame.size
    }
}

/// The helper's answer to one CaptureServiceRequest.
public struct CaptureServiceReply: Codable, Sendable {
    /// Why a capture produced no frame.
    public enum Failure: String, Codable, Sendable {
        /// Missing helper Screen Recording permission signals separate TCC attribution from the responsible app.
        case permissionDenied

        /// A requested window ID fell outside the helper's own
        /// enumeration of menu-bar-layer and wallpaper windows.
        case rejectedWindowID

        /// The SCK capture itself failed.
        case captureFailed
    }

    /// The captured frame, or nil when failure is set.
    public let frame: CaptureServiceFrame?

    /// Successful-capture count; the helper exits at its 1,800-frame budget, so a drop toward zero indicates restart.
    public let generation: Int

    /// Set when frame is nil.
    public let failure: Failure?

    public init(frame: CaptureServiceFrame?, generation: Int, failure: Failure?) {
        self.frame = frame
        self.generation = generation
        self.failure = failure
    }
}

// MARK: - Pixel Codec

public extension CaptureServiceFrame {
    /// The one bitmap layout the wire format speaks: premultiplied BGRA,
    /// 8 bits per component, little-endian.
    private static var bitmapInfo: UInt32 {
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    }

    /// Redraw into BGRA for the wire format because crop and normalization paths may change SCK's bitmap layout.
    init?(image: CGImage, windowFrame: CGRect, scale: Double) {
        guard
            image.width > 0, image.height > 0,
            let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: Self.bitmapInfo
            )
        else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let baseAddress = context.data else {
            return nil
        }
        self.init(
            pixelData: Data(bytes: baseAddress, count: context.bytesPerRow * image.height),
            pixelWidth: image.width,
            pixelHeight: image.height,
            bytesPerRow: context.bytesPerRow,
            windowFrame: windowFrame,
            scale: scale
        )
    }

    /// Reconstructs the captured image from wire form.
    func makeImage() -> CGImage? {
        guard
            pixelWidth > 0, pixelHeight > 0,
            bytesPerRow >= pixelWidth * 4,
            pixelData.count >= bytesPerRow * pixelHeight,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: pixelData as CFData)
        else {
            return nil
        }
        return CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// The frame as the crop-geometry capture type the item pipeline
    /// consumes.
    func makeHostingCapture() -> ScreenCapture.MenuBarHostingCapture? {
        guard let image = makeImage() else {
            return nil
        }
        return ScreenCapture.MenuBarHostingCapture(
            image: image,
            windowFrame: windowFrame,
            scale: scale
        )
    }
}
