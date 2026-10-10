//
//  ThawGradient.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - ThawGradient

/// The persisted form of the menu bar's tint and background fills.
nonisolated struct ThawGradient: Codable, Hashable {
    /// - Important: The name of this property is part of the gradient's
    ///   encoded representation. Renaming it invalidates stored settings.
    var stops: [ColorStop]

    /// The direction the stops run in, in degrees, as Floe counts them: 0 is
    /// top to bottom, 90 leading to trailing, 180 bottom to top.
    ///
    /// - Important: Encoded under its property name, like stops.
    var angle: Double

    init(stops: [ColorStop] = [], angle: Double = ThawGradient.horizontalAngle) {
        self.stops = stops
        self.angle = angle
    }

    /// Gradients saved before angle existed have no key for it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            stops: container.decode([ColorStop].self, forKey: .stops),
            angle: container.decodeIfPresent(Double.self, forKey: .angle) ?? Self.horizontalAngle
        )
    }

    func withAlpha(_ alpha: CGFloat) -> ThawGradient {
        ThawGradient(stops: stops.map { $0.withAlpha(alpha) }, angle: angle)
    }

    /// NSGradient counts from leading to trailing and, in an unflipped
    /// context, turns the other way.
    var drawingAngle: CGFloat {
        CGFloat(angle - Self.horizontalAngle)
    }

    /// Paints along angle in an unflipped context.
    @MainActor
    func draw(in rect: CGRect, using colorSpace: NSColorSpace) {
        nsGradient(using: colorSpace)?.draw(in: rect, angle: drawingAngle)
    }

    /// Skips stops that cannot be represented; nil when none are left.
    @MainActor
    func nsGradient(using colorSpace: NSColorSpace) -> NSGradient? {
        let resolved: [(color: NSColor, location: CGFloat)] = stops.compactMap { stop in
            guard let color = NSColor(cgColor: stop.color) else {
                return nil
            }
            return (color: color, location: stop.location)
        }
        guard !resolved.isEmpty else {
            return nil
        }
        var locations = resolved.map(\.location)
        return NSGradient(
            colors: resolved.map(\.color),
            atLocations: &locations,
            colorSpace: colorSpace
        )
    }

    /// Rasterizes through AppKit so previews match what the overlay paints.
    @MainActor
    func swiftUIView(using colorSpace: Color.RGBColorSpace) -> some View {
        GradientPreview(gradient: self, colorSpace: colorSpace)
    }

    /// Always left to right, for a track whose handles sit along its width.
    @MainActor
    func horizontalSwiftUIView(using colorSpace: Color.RGBColorSpace) -> some View {
        GradientPreview(gradient: ThawGradient(stops: stops), colorSpace: colorSpace)
    }

    /// - Parameters:
    ///   - location: A position between 0 and 1 along the gradient.
    ///   - colorSpace: The interpolation space, also used for the result.
    @MainActor
    func color(at location: CGFloat, using colorSpace: CGColorSpace) -> CGColor? {
        guard let space = NSColorSpace(cgColorSpace: colorSpace) else {
            return nil
        }
        return nsGradient(using: space)?
            .interpolatedColor(atLocation: location)
            .cgColor
    }

    /// Interpolated and returned in extended Display P3. Use color(at:using:)
    /// for another space rather than converting afterwards.
    @MainActor
    func color(at location: CGFloat) -> CGColor? {
        Color.RGBColorSpace.displayP3.cgColorSpace.flatMap { space in
            color(at: location, using: space)
        }
    }

    /// - Parameters:
    ///   - colorSpace: An RGB space to sample and return the color in.
    ///     Non-RGB spaces, and nil, fall back to extended Display P3.
    ///   - option: Options that adjust how the components are combined.
    @MainActor
    func averageColor(
        using colorSpace: CGColorSpace? = nil,
        option: CGImage.ColorAveragingOption = []
    ) -> CGColor? {
        guard !stops.isEmpty else {
            return nil
        }

        let space = Self.rgbColorSpace(preferring: colorSpace)
        let key = AverageColorKey(gradient: self, colorSpaceName: space.name as String?, option: option.rawValue)

        // Memoized: view bodies re-read it per row on every search keystroke.
        return averageColorMemo.value(forKey: key) {
            averagedSamples(in: space, option: option)
        }
    }

    @MainActor
    private func averagedSamples(in space: CGColorSpace, option: CGImage.ColorAveragingOption) -> CGColor? {
        guard
            let nsSpace = NSColorSpace(cgColorSpace: space),
            let gradient = nsGradient(using: nsSpace)
        else {
            return nil
        }

        // One more sample than stops, so both ends are measured.
        let intervals = stops.count
        let samples: [[CGFloat]] = (0 ... intervals).compactMap { step in
            let location = CGFloat(step) / CGFloat(intervals)
            let color = gradient.interpolatedColor(atLocation: location).cgColor
            guard let components = color.components, components.count >= 4 else {
                return nil
            }
            return components
        }

        guard !samples.isEmpty else {
            return nil
        }

        var components = (0 ..< 4).map { channel in
            samples.reduce(0) { $0 + $1[channel] } / CGFloat(samples.count)
        }
        if option.contains(.ignoreAlpha) {
            components[3] = 1
        }

        return CGColor(colorSpace: space, components: &components)
    }

    @MainActor
    private static func rgbColorSpace(preferring colorSpace: CGColorSpace?) -> CGColorSpace {
        colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? Color.RGBColorSpace.displayP3.cgColorSpace
            ?? CGColorSpaceCreateDeviceRGB()
    }
}

// MARK: ThawGradient Static Members

nonisolated extension ThawGradient {
    /// Leading to trailing, which is how every gradient painted before it had an angle.
    static let horizontalAngle = 90.0

    static let defaultMenuBarTint = ThawGradient(stops: [
        .white(location: 0),
        .black(location: 1),
    ])
}

// MARK: - ThawGradient.ColorStop

nonisolated extension ThawGradient {
    nonisolated struct ColorStop: Hashable {
        var color: CGColor

        /// From 0 at the start to 1 at the end.
        var location: CGFloat

        static func stop(_ color: CGColor, location: CGFloat) -> ColorStop {
            ColorStop(color: color, location: location)
        }

        static func white(location: CGFloat) -> ColorStop {
            stop(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), location: location)
        }

        static func black(location: CGFloat) -> ColorStop {
            stop(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), location: location)
        }

        func withAlpha(_ alpha: CGFloat) -> ColorStop {
            Self.stop(color.copy(alpha: alpha) ?? color, location: location)
        }

        func withLocation(_ location: CGFloat) -> ColorStop {
            Self.stop(color, location: location)
        }
    }
}

// MARK: ThawGradient.ColorStop: Codable

nonisolated extension ThawGradient.ColorStop: Codable {
    /// Part of the on-disk format for saved appearances: keys and value types
    /// must not change.
    private enum CodingKeys: CodingKey {
        case color
        case location
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            color: container.decode(ThawColor.self, forKey: .color).cgColor,
            location: container.decode(CGFloat.self, forKey: .location)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ThawColor(cgColor: color), forKey: .color)
        try container.encode(location, forKey: .location)
    }
}

// MARK: - GradientPreview

private struct GradientPreview: View {
    let gradient: ThawGradient
    let colorSpace: Color.RGBColorSpace

    var body: some View {
        GeometryReader { proxy in
            if let image = rasterized(at: proxy.size) {
                Image(nsImage: image)
            } else {
                Color.clear
            }
        }
    }

    /// Memoized: dragging a stop relayouts on every mouse move, and a fresh
    /// image each pass would also defeat SwiftUI's view reuse.
    private func rasterized(at size: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let key = PreviewImageKey(gradient: gradient, colorSpace: colorSpace, size: size)
        return previewImageMemo.value(forKey: key) {
            guard
                let space = colorSpace.nsColorSpace,
                let nsGradient = gradient.nsGradient(using: space)
            else {
                return nil
            }
            return NSImage(size: size, flipped: false) { rect in
                nsGradient.draw(in: rect, angle: gradient.drawingAngle)
                return true
            }
        }
    }
}

// MARK: - Color Space Helpers

private extension Color.RGBColorSpace {
    /// Extended range, so out-of-gamut components survive interpolation.
    var cgColorSpace: CGColorSpace? {
        let name: CFString? = switch self {
        case .sRGB: CGColorSpace.extendedSRGB
        case .sRGBLinear: CGColorSpace.extendedLinearSRGB
        case .displayP3: CGColorSpace.extendedDisplayP3
        @unknown default: nil
        }
        return name.flatMap { CGColorSpace(name: $0) }
    }

    var nsColorSpace: NSColorSpace? {
        cgColorSpace.flatMap { NSColorSpace(cgColorSpace: $0) }
    }
}

// MARK: - Memoization

private nonisolated struct AverageColorKey: Hashable {
    let gradient: ThawGradient
    let colorSpaceName: String?
    let option: Int
}

private nonisolated struct PreviewImageKey: Hashable {
    let gradient: ThawGradient
    let colorSpace: Color.RGBColorSpace
    let size: CGSize
}

@MainActor private var averageColorMemo = BoundedMemo<AverageColorKey, CGColor?>(limit: 16)

@MainActor private var previewImageMemo = BoundedMemo<PreviewImageKey, NSImage?>(limit: 8)

/// Empties itself wholesale past limit. Dragging mints a new gradient per
/// mouse move, so there is no long-lived working set worth aging out.
private struct BoundedMemo<Key: Hashable, Value> {
    private let limit: Int
    private var storage: [Key: Value] = [:]

    init(limit: Int) {
        self.limit = limit
    }

    mutating func value(forKey key: Key, computedBy compute: () -> Value) -> Value {
        if let cached = storage[key] {
            return cached
        }
        let value = compute()
        if storage.count >= limit {
            storage.removeAll()
        }
        storage[key] = value
        return value
    }
}
