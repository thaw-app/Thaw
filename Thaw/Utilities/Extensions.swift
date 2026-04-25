//
//  Extensions.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import os.lock
import SwiftUI

// MARK: - Bundle

extension Bundle {
    /// The bundle's copyright string.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "NSHumanReadableCopyright" key. If a valid value cannot be found for
    /// the key, this accessor returns `nil`.
    var copyrightString: String? {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    /// The bundle's display name.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "CFBundleDisplayName" key. If a valid value cannot be found for the
    /// key, the same check is performed for the "CFBundleName" key. If a valid value
    /// cannot be found for either key, this accessor returns `Thaw`.
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            object(forInfoDictionaryKey: "CFBundleName") as? String ??
            "Thaw"
    }

    /// The bundle's version string.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "CFBundleShortVersionString" key. If a valid value cannot be found
    /// for the key, this accessor returns `nil`.
    var versionString: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The bundle's build string.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "CFBundleVersion" key. If a valid value cannot be found for the key,
    /// this accessor returns `nil`.
    var buildString: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}

// MARK: - CGColor

extension CGColor {
    /// The brightness of the color.
    var brightness: CGFloat? {
        guard
            let rgb = converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let components = rgb.components
        else {
            return nil
        }
        // Algorithm from http://www.w3.org/WAI/ER/WD-AERT/#color-contrast
        return ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
    }
}

// MARK: - CGImage

extension CGImage {
    // MARK: Color Averaging

    /// Options that effect how colors are processed when computing
    /// an average color.
    struct ColorAveragingOption: OptionSet {
        let rawValue: Int

        /// Includes the alpha component in the resulting average.
        static let ignoreAlpha = ColorAveragingOption(rawValue: 1 << 0)
    }

    /// Computes and returns the average color of the image.
    ///
    /// - Parameters:
    ///   - colorSpace: The color space used to process the colors in the image.
    ///     The returned color also uses this color space. Must be an RGB color
    ///     space, or this parameter is ignored.
    ///   - alphaThreshold: An alpha value below which pixels should be ignored.
    ///     Pixels with an alpha component greater than or equal to this value
    ///     contribute to the average.
    ///   - option: Options for computing the color.
    func averageColor(using colorSpace: CGColorSpace? = nil, alphaThreshold: CGFloat = 0.5, option: ColorAveragingOption = []) -> CGColor? {
        func createPixelData(width: Int, height: Int, colorSpace: CGColorSpace) -> [UInt32]? {
            guard width > 0, height > 0 else {
                return nil
            }
            var data = [UInt32](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(alpha: .premultipliedFirst, byteOrder: .order32Little)
            ) else {
                return nil
            }
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return data
        }

        func computeComponent(pixel: UInt32, shift: UInt32) -> UInt64 {
            UInt64((pixel >> shift) & 255)
        }

        let colorSpace: CGColorSpace = {
            if let colorSpace, colorSpace.model == .rgb {
                return colorSpace
            }
            if let colorSpace = self.colorSpace, colorSpace.model == .rgb {
                return colorSpace
            }
            if let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) {
                return colorSpace
            }
            return CGColorSpaceCreateDeviceRGB()
        }()

        // Resize the image for better performance.
        let width = min(width, 10)
        let height = min(height, 10)

        guard let pixelData = createPixelData(width: width, height: height, colorSpace: colorSpace) else {
            return nil
        }

        // Convert the alpha threshold to a valid component for comparison.
        let alphaThreshold = UInt64((alphaThreshold.clamped(to: 0 ... 1) * 255).rounded(.toNearestOrAwayFromZero))

        var count = UInt64(width * height)
        var totals: (r: UInt64, g: UInt64, b: UInt64, a: UInt64) = (0, 0, 0, 0)

        for column in 0 ..< width {
            for row in 0 ..< height {
                let pixel = pixelData[(row * width) + column]

                // Check alpha before computing other components.
                let alpha = computeComponent(pixel: pixel, shift: 24)

                guard alpha >= alphaThreshold else {
                    count -= 1 // Don't include this pixel.
                    continue
                }

                totals.r += computeComponent(pixel: pixel, shift: 16)
                totals.g += computeComponent(pixel: pixel, shift: 8)
                totals.b += computeComponent(pixel: pixel, shift: 0)
                totals.a += alpha
            }
        }

        // Components are currently in integer format (0 to 255), but need
        // to be converted to floating point (0 to 1). Makes more sense to
        // scale the count up to match the components, rather than scale
        // the components down to match the count.
        let scaledCount = CGFloat(count * 255)

        var components: [CGFloat] = [
            CGFloat(totals.r) / scaledCount,
            CGFloat(totals.g) / scaledCount,
            CGFloat(totals.b) / scaledCount,
            option.contains(.ignoreAlpha) ? 1 : CGFloat(totals.a) / scaledCount,
        ]

        return CGColor(colorSpace: colorSpace, components: &components)
    }

    // MARK: Transparency Trimming

    /// A context for handling transparency data in an image.
    private struct TransparencyContext: ~Copyable {
        private let image: CGImage
        private let alphaThreshold: CGFloat
        private let cgContext: CGContext
        private let data: UnsafeMutableRawPointer
        private let zeroByteBlock: UnsafeMutableRawPointer
        private let rowRange: Range<Int>
        private let columnRange: Range<Int>

        /// Creates a context with the given image and alpha threshold.
        ///
        /// - Parameters:
        ///   - image: The image to form a context around.
        ///   - alphaThreshold: The maximum alpha value to consider transparent.
        init?(image: CGImage, alphaThreshold: CGFloat) {
            guard
                image.width > 0,
                image.height > 0,
                alphaThreshold < 1,
                let cgContext = CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(alpha: .alphaOnly)
                ),
                let data = cgContext.data,
                let zeroByteBlock = calloc(image.width, MemoryLayout<UInt8>.size)
            else {
                return nil
            }

            let size = CGSize(width: image.width, height: image.height)
            cgContext.draw(image, in: CGRect(origin: .zero, size: size))

            self.image = image
            self.alphaThreshold = alphaThreshold
            self.cgContext = cgContext
            self.data = data
            self.zeroByteBlock = zeroByteBlock
            self.rowRange = 0 ..< image.height
            self.columnRange = 0 ..< image.width
        }

        deinit {
            free(zeroByteBlock)
        }

        /// Returns an image derived from the context's image that has been
        /// trimmed of transparency around the given edges.
        func trim(around edges: Set<CGRectEdge>) -> CGImage? {
            guard !edges.isEmpty else {
                return image // Nothing to trim.
            }

            guard
                let minXInset = inset(for: .minXEdge, in: edges),
                let minYInset = inset(for: .minYEdge, in: edges),
                let maxXInset = inset(for: .maxXEdge, in: edges),
                let maxYInset = inset(for: .maxYEdge, in: edges)
            else {
                return nil
            }

            guard (minXInset, minYInset, maxXInset, maxYInset) != (0, 0, 0, 0) else {
                return image // Already trimmed.
            }

            let insetRect = CGRect(
                x: minXInset,
                y: minYInset,
                width: max(image.width - (minXInset + maxXInset), 0),
                height: max(image.height - (minYInset + maxYInset), 0)
            )

            return image.cropping(to: insetRect)
        }

        /// Returns a Boolean value that indicates whether the context's
        /// image is transparent.
        func isTransparent() -> Bool {
            rowRange.allSatisfy { row in
                isRowTransparent(row: row)
            }
        }

        private func inset(for edge: CGRectEdge, in edges: Set<CGRectEdge>) -> Int? {
            guard edges.contains(edge) else {
                return 0
            }
            return switch edge {
            case .minXEdge:
                firstOpaqueColumn(in: columnRange)
            case .minYEdge:
                firstOpaqueRow(in: rowRange)
            case .maxXEdge:
                firstOpaqueColumn(in: columnRange.reversed()).map { (image.width - 1) - $0 }
            case .maxYEdge:
                firstOpaqueRow(in: rowRange.reversed()).map { (image.height - 1) - $0 }
            }
        }

        private func isPixelOpaque(row: Int, column: Int) -> Bool {
            let rawAlpha = data.load(
                fromByteOffset: (row * cgContext.bytesPerRow) + column,
                as: UInt8.self
            )
            let convertedAlpha = CGFloat(rawAlpha) / 255
            return convertedAlpha > alphaThreshold
        }

        private func isRowTransparent(row: Int) -> Bool {
            // Use memcmp to efficiently check the entire row for zeroed out alpha.
            if memcmp(data + (row * cgContext.bytesPerRow), zeroByteBlock, image.width) == 0 {
                return true
            }
            // Avoid checking individual pixels if we can.
            if alphaThreshold == 0 {
                return false
            }
            // Check each pixel in the row until we find one that is opaque.
            return !columnRange.contains { column in
                isPixelOpaque(row: row, column: column)
            }
        }

        private func firstOpaqueRow(in rowRange: some Sequence<Int>) -> Int? {
            rowRange.first { row in
                !isRowTransparent(row: row)
            }
        }

        private func firstOpaqueColumn(in columnRange: some Sequence<Int>) -> Int? {
            columnRange.first { column in
                rowRange.contains { row in
                    isPixelOpaque(row: row, column: column)
                }
            }
        }
    }

    /// Returns an image that has been trimmed of transparency around the
    /// given edges.
    ///
    /// Each edge is trimmed up to the first row or column containing pixels
    /// with an alpha component above the specified threshold.
    ///
    /// - Parameters:
    ///   - edges: A set of edges to trim from around the image.
    ///   - alphaThreshold: The maximum alpha value to consider transparent.
    func trimmingTransparency(
        around edges: Set<CGRectEdge> = [.minXEdge, .minYEdge, .maxXEdge, .maxYEdge],
        alphaThreshold: CGFloat = 0
    ) -> CGImage? {
        guard let context = TransparencyContext(image: self, alphaThreshold: alphaThreshold) else {
            return self
        }
        return context.trim(around: edges)
    }

    /// Returns a Boolean value that indicates whether the image is transparent.
    ///
    /// Uses a zero-allocation fast path that reads alpha bytes directly from
    /// the image's existing data provider, avoiding the cost of creating a
    /// `CGContext`, drawing the image, and allocating a comparison buffer.
    /// Only handles 32-bit RGBA/ARGB with known byte orders; falls back to
    /// `TransparencyContext` for all other pixel formats.
    ///
    /// - Parameter alphaThreshold: The maximum alpha value to consider transparent.
    func isTransparent(alphaThreshold: CGFloat = 0) -> Bool {
        guard width > 0, height > 0 else { return true }
        guard alphaThreshold < 1 else { return false }

        let bytesPerPixel = bitsPerPixel / 8

        // Fast path only for 32-bit (4 bytes per pixel) images.
        guard bytesPerPixel == 4 else {
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // No alpha channel — image is fully opaque.
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedFirst, .first, .premultipliedLast, .last, .alphaOnly:
            break
        @unknown default:
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // Determine the in-memory alpha byte offset, accounting for byte order.
        // macOS screen captures typically use byteOrder32Little + premultipliedFirst,
        // which stores logical ARGB as physical BGRA (alpha at byte 3).
        let byteOrder = CGBitmapInfo(rawValue: bitmapInfo.rawValue).intersection(.byteOrderMask)

        let isLittleEndian: Bool
        switch byteOrder {
        case .byteOrder32Little:
            isLittleEndian = true
        case .byteOrder32Big:
            isLittleEndian = false
        default:
            // byteOrderDefault or 16-bit orders — fall back for safety.
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        let alphaOffset: Int
        switch (alphaInfo, isLittleEndian) {
        case (.premultipliedFirst, true), (.first, true):
            alphaOffset = 3 // Logical ARGB stored as BGRA
        case (.premultipliedLast, true), (.last, true):
            alphaOffset = 0 // Logical RGBA stored as ABGR
        case (.premultipliedFirst, false), (.first, false):
            alphaOffset = 0 // Big-endian: ARGB as-is
        case (.premultipliedLast, false), (.last, false):
            alphaOffset = 3 // Big-endian: RGBA as-is
        default:
            // .alphaOnly is excluded by the bytesPerPixel == 4 guard above.
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // Read alpha directly from existing pixel data.
        // withExtendedLifetime ensures cfData (and thus the byte pointer) stays
        // alive for the entire scan, preventing ARC from releasing it early.
        guard let cfData = dataProvider?.data,
              let bytes = CFDataGetBytePtr(cfData)
        else {
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // Validate buffer is large enough to prevent out-of-bounds reads.
        let rowBytes = bytesPerRow
        let dataLength = CFDataGetLength(cfData)
        let requiredLength = (height - 1) * rowBytes + (width - 1) * bytesPerPixel + alphaOffset + 1
        guard dataLength >= requiredLength else {
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        let threshold = UInt8(min(max(alphaThreshold * 255, 0), 255))

        return withExtendedLifetime(cfData) {
            for row in 0 ..< height {
                let rowStart = row * rowBytes
                if (0 ..< width).contains(where: { col in
                    bytes[rowStart + col * bytesPerPixel + alphaOffset] > threshold
                }) {
                    return false
                }
            }
            return true
        }
    }

    /// Slow path for `isTransparent` using `TransparencyContext`.
    private func isTransparentSlow(alphaThreshold: CGFloat) -> Bool {
        guard let context = TransparencyContext(image: self, alphaThreshold: alphaThreshold) else {
            return false
        }
        return context.isTransparent()
    }
}

// MARK: - Collection where Element == MenuBarItem

extension Collection where Element == MenuBarItem {
    /// Returns the first index where the menu bar item matching the specified
    /// tag appears in the collection.
    func firstIndex(matching tag: MenuBarItemTag) -> Index? {
        firstIndex { $0.tag == tag }
    }
}

// MARK: - Comparable

extension Comparable {
    /// Returns a copy of this value, clamped to the given minimum
    /// and maximum limiting values.
    ///
    /// - Parameters:
    ///   - min: The minimum limiting value.
    ///   - max: The maximum limiting value.
    ///
    /// - Precondition: `min <= max`
    ///
    /// - Returns: The value nearest this value that is both greater
    ///   than or equal to `min` and less than or equal to `max`.
    func clamped(min: Self, max: Self) -> Self {
        precondition(min <= max, "Clamp requires min <= max")
        return Swift.min(Swift.max(self, min), max)
    }

    /// Returns a copy of this value, clamped to the given limiting
    /// range.
    ///
    /// - Parameter range: A range of values of this type, whose
    ///   lower and upper bounds represent the minimum and maximum
    ///   limiting values.
    ///
    /// - Returns: The value nearest this value that is both greater
    ///   than or equal to `range.lowerBound` and less than or equal
    ///   to `range.upperBound`.
    func clamped(to range: ClosedRange<Self>) -> Self {
        clamped(min: range.lowerBound, max: range.upperBound)
    }
}

// MARK: - DistributedNotificationCenter

extension DistributedNotificationCenter {
    /// A notification posted whenever the system-wide interface theme changes.
    static let interfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
}

// MARK: - EdgeInsets

extension EdgeInsets {
    /// A copy of this instance with only the leading and trailing
    /// edges set.
    var horizontal: EdgeInsets {
        EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
    }

    /// A copy of this instance with only the top and bottom
    /// edges set.
    var vertical: EdgeInsets {
        EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    }

    /// Creates an instance with all edges set to the given value.
    init(all: CGFloat) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }
}

// MARK: - NSApplication

extension NSApplication {
    /// Returns the window with the given identifier.
    func window(withIdentifier identifier: String) -> NSWindow? {
        windows.first { $0.identifier?.rawValue == identifier }
    }
}

// MARK: - NSBezierPath

extension NSBezierPath {
    /// Draws a shadow in the shape of the path.
    ///
    /// - Parameters:
    ///   - color: The color of the drawn shadow.
    ///   - radius: The radius of the drawn shadow.
    func drawShadow(color: NSColor, radius: CGFloat) {
        guard let context = NSGraphicsContext.current else {
            return
        }

        let bounds = bounds.insetBy(dx: -radius, dy: -radius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = radius
        shadow.shadowColor = color

        // swiftlint:disable:next force_cast
        let path = copy() as! NSBezierPath

        context.saveGraphicsState()

        shadow.set()
        NSColor.black.set()
        bounds.clip()
        path.fill()

        context.restoreGraphicsState()
    }

    /// Returns a new path filled with regions in either this path or the
    /// given path.
    ///
    /// - Parameters:
    ///   - other: A path to union with this path.
    ///   - windingRule: The winding rule used to join the paths.
    func union(_ other: NSBezierPath, using windingRule: WindingRule = .evenOdd) -> NSBezierPath {
        let fillRule: CGPathFillRule = switch windingRule {
        case .nonZero: .winding
        case .evenOdd: .evenOdd
        @unknown default: fatalError("Unknown winding rule \(windingRule)")
        }
        return NSBezierPath(cgPath: cgPath.union(other.cgPath, using: fillRule))
    }
}

// MARK: - NSImage

extension NSImage {
    /// Returns a new image that has been resized to the given size.
    ///
    /// - Note: This method retains the ``isTemplate`` property.
    ///
    /// - Parameter size: The size to resize the current image to.
    func resized(to size: CGSize) -> NSImage {
        let resizedImage = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            return true
        }
        resizedImage.isTemplate = isTemplate
        return resizedImage
    }
}

// MARK: - NSScreen

extension NSScreen {
    /// The screen containing the mouse pointer.
    static var screenWithMouse: NSScreen? {
        screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    /// The screen with the active menu bar.
    static var screenWithActiveMenuBar: NSScreen? {
        guard let displayID = Bridging.getActiveMenuBarDisplayID() else {
            return nil
        }
        return screens.first { $0.displayID == displayID }
    }

    /// The display identifier of the screen.
    var displayID: CGDirectDisplayID {
        // Value and type are guaranteed here, so force casting is okay.
        // swiftlint:disable:next force_cast
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    }

    /// A Boolean value that indicates whether the screen has a notch.
    var hasNotch: Bool {
        auxiliaryTopLeftArea != nil
    }

    /// The frame of the screen's notch, if it has one.
    var frameOfNotch: CGRect? {
        guard
            let auxiliaryTopLeftArea,
            let auxiliaryTopRightArea
        else {
            return nil
        }
        return CGRect(
            x: auxiliaryTopLeftArea.maxX,
            y: frame.maxY - safeAreaInsets.top,
            width: auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX,
            height: safeAreaInsets.top
        )
    }

    /// Per-display cache of the last known application menu frame.
    private static var applicationMenuFrameCache = [CGDirectDisplayID: CGRect]()

    /// The pid of the frontmost application when the cache was last populated.
    private static var applicationMenuFrameCachePID: pid_t?

    /// Invalidates the cached application menu frame when the frontmost app changes.
    private static func invalidateApplicationMenuFrameCacheIfNeeded() {
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if currentPID != applicationMenuFrameCachePID {
            applicationMenuFrameCache.removeAll()
            applicationMenuFrameCachePID = currentPID
        }
    }

    /// Per-display cache of the last known menu bar height.
    private static var menuBarHeightCache = [CGDirectDisplayID: CGFloat]()

    /// Invalidates the cached menu bar heights.
    static func invalidateMenuBarHeightCache() {
        menuBarHeightCache.removeAll()
    }

    /// Removes cache entries for displays that are no longer connected.
    /// This prevents memory growth when displays are reconnected (which assigns new display IDs).
    static func cleanupDisconnectedDisplayCaches() {
        let connectedDisplayIDs = Set(NSScreen.screens.map { $0.displayID })
        menuBarHeightCache = menuBarHeightCache.filter { connectedDisplayIDs.contains($0.key) }
        applicationMenuFrameCache = applicationMenuFrameCache.filter { connectedDisplayIDs.contains($0.key) }
    }

    /// Returns the height of the menu bar on this screen.
    ///
    /// Results are cached per-display. A sentinel value of `-1` is stored when
    /// the Menubar window cannot be found, preventing repeated Window Server
    /// IPC calls on every mouse-moved event when the window is temporarily
    /// unavailable (e.g. during startup). The cache is cleared on display
    /// configuration changes via `invalidateMenuBarHeightCache()`.
    func getMenuBarHeight() -> CGFloat? {
        if let cached = NSScreen.menuBarHeightCache[displayID] {
            // Negative sentinel means a previous lookup failed; don't retry
            // until the cache is invalidated.
            return cached > 0 ? cached : nil
        }
        let menuBarWindow = WindowInfo.menuBarWindow(for: displayID)
        guard let height = menuBarWindow?.bounds.height, height > 0 else {
            // Cache the failure so the next call skips the IPC round-trip.
            NSScreen.menuBarHeightCache[displayID] = -1
            return nil
        }
        NSScreen.menuBarHeightCache[displayID] = height
        return height
    }

    /// Returns the menu bar height for this screen, falling back to the last
    /// cached value for this display, then to a notch-aware estimate.
    ///
    /// Use this when a non-optional height is required (e.g. for clamping
    /// IceBar item sizes) and the live window-list query may not yet be
    /// available.
    func getMenuBarHeightEstimate() -> CGFloat {
        if let live = getMenuBarHeight() {
            return live
        }
        // Skip the sentinel (-1) stored for a failed lookup.
        if let cached = NSScreen.menuBarHeightCache[displayID], cached > 0 {
            return cached
        }
        // Notched MacBooks have a ~37-38 pt menu bar; non-notch Macs use the
        // standard status-bar thickness (22 pt).
        return hasNotch ? 37.0 : NSStatusBar.system.thickness
    }

    /// Returns the raw frame of the application menu on this screen, as
    /// reported by the Accessibility API, without any notch-capping applied.
    ///
    /// Results are cached per-display and invalidated when the frontmost
    /// application changes, avoiding repeated Accessibility API round-trips.
    /// Callers that need a notch-capped width should apply the cap themselves
    /// using `frameOfNotch`.
    ///
    /// - Parameter bypassCache: If `true`, always queries the Accessibility API
    ///   instead of using cached values. Use this when polling for changes.
    func getApplicationMenuFrame(bypassCache: Bool = false) -> CGRect? {
        NSScreen.invalidateApplicationMenuFrameCacheIfNeeded()
        if !bypassCache, let cached = NSScreen.applicationMenuFrameCache[displayID] {
            return cached
        }

        let result = computeApplicationMenuFrame()
        if !bypassCache, let result {
            NSScreen.applicationMenuFrameCache[displayID] = result
        }
        return result
    }

    /// Performs the actual Accessibility API queries to determine the
    /// application menu frame. Returns the raw frame without notch-capping.
    /// Called only on cache miss.
    private func computeApplicationMenuFrame() -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)

        // Accessibility API has trouble with secondary screens.
        // If we are not on the main screen, we can construct a
        // reasonable approximation.
        if let mainScreen = NSScreen.main, self != mainScreen {
            // Check if we can get the menu bar frame from the accessibility API.
            if
                let menuBar = AXHelpers.element(at: displayBounds.origin),
                AXHelpers.role(for: menuBar) == .menuBar
            {
                let applicationMenuFrame = AXHelpers.children(for: menuBar).reduce(into: CGRect.null) { result, child in
                    if AXHelpers.isEnabled(child), let childFrame = AXHelpers.frame(for: child) {
                        result = result.union(childFrame)
                    }
                }
                if !applicationMenuFrame.isNull, applicationMenuFrame.width > 0 {
                    // If we got a valid width, assume it starts at the screen's left edge.
                    return CGRect(x: frame.minX, y: applicationMenuFrame.minY, width: applicationMenuFrame.width, height: applicationMenuFrame.height)
                }
            }
            // Fallback: If AX fails for secondary screen, use the main screen's raw menu width.
            // No notch-capping here — callers apply any notch adjustments they need.
            if let mainFrame = mainScreen.getApplicationMenuFrame() {
                return CGRect(x: frame.minX, y: mainFrame.minY, width: mainFrame.width, height: mainFrame.height)
            }
            return nil
        }

        guard
            let menuBar = AXHelpers.element(at: displayBounds.origin),
            AXHelpers.role(for: menuBar) == .menuBar
        else {
            return nil
        }

        let applicationMenuFrame = AXHelpers.children(for: menuBar).reduce(into: CGRect.null) { result, child in
            if AXHelpers.isEnabled(child), let childFrame = AXHelpers.frame(for: child) {
                result = result.union(childFrame)
            }
        }

        if applicationMenuFrame.width <= 0 || applicationMenuFrame.isNull {
            return nil
        }

        return applicationMenuFrame
    }
}

// MARK: - NSStatusItem

extension NSStatusItem {
    /// Shows the given menu under the status item.
    func showMenu(_ menu: NSMenu) {
        let originalMenu = self.menu
        defer {
            self.menu = originalMenu
        }
        self.menu = menu
        button?.performClick(nil)
    }
}

// MARK: - OSAllocatedUnfairLock

extension OSAllocatedUnfairLock where State == Bool {
    /// Atomically sets the value to `true` and returns whether this call
    /// was the first to do so. Useful for ensuring a continuation or
    /// callback is invoked exactly once across competing code paths.
    func tryClaimOnce() -> Bool {
        withLock { claimed in
            let wasUnclaimed = !claimed
            claimed = true
            return wasUnclaimed
        }
    }
}

// MARK: - Publisher

extension Publisher {
    /// Replaces each upstream element with an element returned from
    /// the given closure.
    ///
    /// - Parameter output: A closure that returns a new element to
    ///   publish in place of the upstream element.
    func replace<T>(_ output: @escaping () -> T) -> Publishers.Map<Self, T> {
        map { _ in output() }
    }

    /// Replaces each upstream element with the given element.
    ///
    /// - Parameter output: A new element to publish in place of the
    ///   upstream elements.
    func replace<T>(with output: T) -> Publishers.Map<Self, T> {
        replace { output }
    }

    /// Publishes only non-`nil` elements.
    func removeNil<T>() -> Publishers.CompactMap<Self, T> where Output == T? {
        compactMap { $0 }
    }

    /// Publishes only elements that don't match the previous element.
    func removeDuplicates<each T: Equatable>() -> Publishers.RemoveDuplicates<Self> where Output == (repeat each T) {
        removeDuplicates { lhs, rhs in
            for (left, right) in repeat (each lhs, each rhs) {
                guard left == right else { return false }
            }
            return true
        }
    }

    /// Merges this publisher with the given publisher, replacing upstream
    /// elements with `Void` values.
    ///
    /// - Parameter other: Another publisher.
    func discardMerge<P: Publisher>(_ other: P) -> some Publisher<Void, Failure> where P.Failure == Failure {
        replace(with: ()).merge(with: other.replace(with: ()))
    }

    /// Transforms the elements of the upstream sequence into a sequence of
    /// publishers and merges the results.
    ///
    /// - Parameter transform: A closure that takes an element of the upstream
    ///   sequence as a parameter and returns a publisher.
    ///
    /// - Returns: A publisher that emits an event when any upstream publisher
    ///   emits an event.
    func mergeMap<P: Publisher>(
        _ transform: @escaping (Output.Element) -> P
    ) -> some Publisher<P.Output, P.Failure> where Output: Sequence, Failure == Never {
        flatMap { sequence in
            Publishers.MergeMany(sequence.map(transform))
        }
    }
}

// MARK: - Publisher (Defaults Persistence)

extension Publisher where Output: Equatable, Failure == Never {
    /// Binds publisher to UserDefaults, persisting each unique value.
    ///
    /// - Parameters:
    ///   - key: The Defaults key to persist to.
    ///   - cancellables: The set to store the subscription in.
    func persistToDefaults(
        key: Defaults.Key,
        in cancellables: inout Set<AnyCancellable>
    ) {
        self.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { Defaults.set($0, forKey: key) }
            .store(in: &cancellables)
    }

    /// Binds publisher to UserDefaults with transform (e.g., for RawRepresentable enums).
    ///
    /// - Parameters:
    ///   - key: The Defaults key to persist to.
    ///   - transform: A closure that transforms the output before persisting.
    ///   - cancellables: The set to store the subscription in.
    func persistToDefaults<T>(
        key: Defaults.Key,
        transform: @escaping (Output) -> T,
        in cancellables: inout Set<AnyCancellable>
    ) {
        self.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { Defaults.set(transform($0), forKey: key) }
            .store(in: &cancellables)
    }

    /// Binds publisher to UserDefaults with an additional side effect.
    ///
    /// - Parameters:
    ///   - key: The Defaults key to persist to.
    ///   - sideEffect: A closure to execute after persisting.
    ///   - cancellables: The set to store the subscription in.
    func persistToDefaults(
        key: Defaults.Key,
        sideEffect: @escaping (Output) -> Void,
        in cancellables: inout Set<AnyCancellable>
    ) {
        self.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { value in
                Defaults.set(value, forKey: key)
                sideEffect(value)
            }
            .store(in: &cancellables)
    }
}

// MARK: - RangeReplaceableCollection where Element: Hashable

extension RangeReplaceableCollection where Element: Hashable {
    /// Returns a copy of the collection with duplicate values removed.
    func removingDuplicates() -> Self {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - RangeReplaceableCollection where Element == MenuBarItem

extension RangeReplaceableCollection where Element == MenuBarItem {
    /// Removes and returns the first menu bar item that matches
    /// the specified tag.
    mutating func removeFirst(matching tag: MenuBarItemTag) -> MenuBarItem? {
        guard let index = firstIndex(matching: tag) else {
            return nil
        }
        return remove(at: index)
    }
}

// MARK: - Sequence where Element == MenuBarItem

extension Sequence where Element == MenuBarItem {
    /// Returns the first menu bar item that matches the specified tag.
    func first(matching tag: MenuBarItemTag) -> MenuBarItem? {
        first { $0.tag == tag }
    }
}

// MARK: - NSPanel

extension NSPanel {
    /// Waits until the panel is no longer visible, or until `timeout` elapses.
    ///
    /// Uses KVO on `isVisible` rather than polling, so the caller is resumed
    /// immediately when the panel hides with no busy-waiting on the main thread.
    /// A minimum of one run-loop turn is always yielded so that `orderOut`/`close`
    /// has a chance to propagate through AppKit before the continuation resumes.
    ///
    /// Must be called on the main actor because `NSPanel.isVisible` is an
    /// AppKit property that is only safe to read on the main thread.
    @MainActor
    func waitUntilClosed(timeout: Duration = .milliseconds(200)) async {
        // Fast-path: already hidden.
        guard isVisible else { return }

        await withTaskGroup(of: Void.self) { group in
            // Task 1: resume as soon as isVisible becomes false via KVO.
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                var bag = Set<AnyCancellable>()
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    self.publisher(for: \.isVisible)
                        .filter { !$0 }
                        .first()
                        .sink { _ in cont.resume() }
                        .store(in: &bag)
                }
            }
            // Task 2: timeout guard — resumes the group if the panel never
            // becomes invisible within the allotted time.
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            // Whichever task finishes first wins; cancel the other.
            _ = await group.next()
            group.cancelAll()
        }
    }
}
