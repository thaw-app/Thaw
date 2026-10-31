//
//  SearchFieldBeamLayers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// One layer of the beam: still colour, a running light over it, or both, seen through a running window.
public struct BeamLayer {
    /// A light that runs with the window, seen through a still mask.
    public init(
        colour: [CGImage] = [],
        glint: Glint? = nil,
        window: [(Double, Double)]? = nil,
        opacity: Float
    ) {
        self.colour = colour
        self.glint = glint
        self.window = window
        self.opacity = opacity
    }

    public struct Glint {
        public let stops: [(Double, Double)]
        public let light: CGColor
        public let mask: CGImage
    }

    /// The colour at each of the two hues it drifts between, or at the one it stands still at.
    public var colour: [CGImage] = []
    public var glint: Glint?
    /// Where round the field the layer shows. Nil for all the way round.
    public var window: [(Double, Double)]?
    public var opacity: Float
}

public struct BeamLayers: NSViewRepresentable {
    public let key: BeamLayerView.Key
    public let layers: () -> [BeamLayer]

    public func makeNSView(context _: Context) -> BeamLayerView {
        BeamLayerView()
    }

    public func updateNSView(_ view: BeamLayerView, context _: Context) {
        view.show(key, layers)
    }
}

/// The beam as Core Animation layers. They are made again only when the field's size or look changes.
public final class BeamLayerView: NSView {
    public struct Key: Equatable {
        public let size: CGSize
        public let scale: CGFloat
        public let outline: Path
        public let beam: SearchFieldBeam
        public let isEdge: Bool
        public let isDark: Bool
        public let isStill: Bool
        public let frameRate: Float
    }

    // One monotonic clock for the edge, spill and rebuilt layers, independent of image-rendering time.
    private static let animationEpoch = CACurrentMediaTime()
    private var key: Key?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool {
        true
    }

    public override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    public func show(_ key: Key, _ layers: () -> [BeamLayer]) {
        guard key != self.key, key.size.width > 0, key.size.height > 0, let root = layer else { return }
        self.key = key
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let bounds = CGRect(origin: .zero, size: key.size)
        let clip = CALayer()
        clip.frame = bounds
        let shape = CAShapeLayer()
        shape.path = key.outline.cgPath
        clip.mask = shape
        for beamLayer in layers() {
            clip.addSublayer(make(beamLayer, in: bounds, key: key))
        }
        root.sublayers = [clip]
    }

    private func make(_ beamLayer: BeamLayer, in bounds: CGRect, key: Key) -> CALayer {
        let group = CALayer()
        group.frame = bounds
        group.opacity = beamLayer.opacity
        for (index, image) in beamLayer.colour.enumerated() {
            let colour = picture(image, in: bounds, scale: key.scale)
            if index > 0, !key.isStill {
                colour.add(Self.drift(at: key.frameRate), forKey: "drift")
            }
            group.addSublayer(colour)
        }
        if let glint = beamLayer.glint {
            let holder = CALayer()
            holder.frame = bounds
            holder.mask = picture(glint.mask, in: bounds, scale: key.scale)
            holder.addSublayer(running(glint.stops, light: glint.light, in: bounds, key: key))
            group.addSublayer(holder)
        }
        if let window = beamLayer.window {
            group.mask = running(window, light: NSColor.white.cgColor, in: bounds, key: key)
        }
        return group
    }

    private func picture(_ image: CGImage, in bounds: CGRect, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.contents = image
        layer.contentsScale = scale
        return layer
    }

    /// A light running along the border, drawn as stretches of it from the faint long one to the bright short one.
    /// It reaches halfway into the field, so it never lights the side across from it.
    private func running(_ stops: [(Double, Double)], light: CGColor, in bounds: CGRect, key: Key) -> CALayer {
        let path = key.outline.cgPath
        let length = Self.length(of: path)
        let holder = CALayer()
        holder.frame = bounds
        for band in Self.bands(stops) {
            let stretch = CAShapeLayer()
            stretch.frame = bounds
            stretch.path = path
            stretch.fillColor = nil
            stretch.strokeColor = light.copy(alpha: light.alpha * band.alpha) ?? light
            stretch.lineWidth = min(bounds.width, bounds.height)
            stretch.lineDashPattern = [band.to - band.from, 1 - (band.to - band.from)].map { NSNumber(value: $0 * length) }
            stretch.lineDashPhase = -band.from * length
            if !key.isStill {
                stretch.add(Self.run(from: band.from, along: length, at: key.frameRate), forKey: "run")
            }
            holder.addSublayer(stretch)
        }
        return holder
    }

    /// One lap every turn seconds at one speed, at the same place in the lap for every layer, the field's and the glow's.
    public static func run(from start: Double, along length: CGFloat, at frameRate: Float) -> CAAnimation {
        let lap = CABasicAnimation(keyPath: "lineDashPhase")
        lap.fromValue = -start * length
        lap.toValue = -(start + 1) * length
        lap.duration = SearchFieldBeamView<Rectangle>.turn
        lap.timingFunction = CAMediaTimingFunction(name: .linear)
        lap.beginTime = animationEpoch
        lap.repeatCount = .infinity
        lap.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        return lap
    }

    /// The second hue fades in and out over the first, as the colours drift one way and back.
    public static func drift(at frameRate: Float) -> CAAnimation {
        let period = SearchFieldBeamView<Rectangle>.drift.period
        let drift = interpolated("opacity", over: period, at: frameRate) { (1 - cos(2 * .pi * $0)) / 2 }
        drift.timeOffset = period / 4
        return drift
    }

    /// The light's stops as nested stretches of a lap, each with the opacity that, laid over the ones under it,
    /// brings the light to its level there.
    public static func bands(_ stops: [(Double, Double)], levels: Int = 32) -> [(from: Double, to: Double, alpha: Double)] {
        let peak = stops.map(\.1).max() ?? 0
        guard peak > 0 else { return [] }
        var below = 0.0
        return (1 ... levels).compactMap { step in
            let level = peak * Double(step) / Double(levels)
            guard let from = crossing(stops, at: level, rising: true), let to = crossing(stops, at: level, rising: false), to > from else { return nil }
            let alpha = level >= 1 ? 1 : 1 - (1 - level) / (1 - below)
            below = level
            return (from, min(to, from + 0.999), alpha)
        }
    }

    /// Where the light first comes up to level, or last goes down from it.
    private static func crossing(_ stops: [(Double, Double)], at level: Double, rising: Bool) -> Double? {
        let pairs = Array(zip(stops, stops.dropFirst()))
        for (a, b) in rising ? pairs : pairs.reversed() {
            let (low, high) = rising ? (a, b) : (b, a)
            guard low.1 < level, high.1 >= level else { continue }
            return low.0 + (high.0 - low.0) * (level - low.1) / (high.1 - low.1)
        }
        return (rising ? stops.first { $0.1 >= level } : stops.last { $0.1 >= level }).map(\.0)
    }

    /// How long a path is, with its curves followed in short straight steps.
    public static func length(of path: CGPath) -> CGFloat {
        var total: CGFloat = 0
        var start = CGPoint.zero
        var point = CGPoint.zero
        func walk(_ position: (CGFloat) -> CGPoint) {
            for step in 1 ... 24 {
                let next = position(CGFloat(step) / 24)
                total += hypot(next.x - point.x, next.y - point.y)
                point = next
            }
        }
        path.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                start = p[0]
                point = p[0]
            case .addLineToPoint:
                total += hypot(p[0].x - point.x, p[0].y - point.y)
                point = p[0]
            case .addQuadCurveToPoint:
                let from = point
                walk { t in
                    let u = 1 - t
                    return CGPoint(x: u * u * from.x + 2 * u * t * p[0].x + t * t * p[1].x, y: u * u * from.y + 2 * u * t * p[0].y + t * t * p[1].y)
                }
            case .addCurveToPoint:
                let from = point
                walk { t in
                    let u = 1 - t
                    let x = u * u * u * from.x + 3 * u * u * t * p[0].x + 3 * u * t * t * p[1].x + t * t * t * p[2].x
                    let y = u * u * u * from.y + 3 * u * u * t * p[0].y + 3 * u * t * t * p[1].y + t * t * t * p[2].y
                    return CGPoint(x: x, y: y)
                }
            case .closeSubpath:
                total += hypot(start.x - point.x, start.y - point.y)
                point = start
            @unknown default:
                break
            }
        }
        return total
    }

    /// Samples describe the curve and don't cap the frame rate. Interpolation lets the compositor follow its cadence.
    private static func interpolated(_ keyPath: String, over duration: Double, at frameRate: Float, value: (Double) -> Double) -> CAKeyframeAnimation {
        let steps = max(1, Int((duration * 120).rounded()))
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0 ... steps).map { value(Double($0) / Double(steps)) }
        animation.keyTimes = (0 ... steps).map { NSNumber(value: Double($0) / Double(steps)) }
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = duration
        animation.beginTime = animationEpoch
        animation.repeatCount = .infinity
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        return animation
    }
}
