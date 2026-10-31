//
//  SearchFieldBeamLayersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

@testable import ThawUI
import SwiftUI
import Testing

@MainActor
struct SearchFieldBeamLayersTests {
    @Test func reduceMotionStopsTheRunAndColourDrift() throws {
        let view = BeamLayerView()
        let beam = try fixture()
        view.show(key(isStill: false)) { [beam] }
        let root = try #require(view.layer)
        #expect(keyPaths(of: animations(in: root)) == ["opacity", "lineDashPhase"])

        view.show(key(isStill: true)) { [beam] }
        #expect(animations(in: root).isEmpty)

        view.show(key(isStill: false)) { [beam] }
        let resumed = animations(in: root)
        #expect(keyPaths(of: resumed) == ["opacity", "lineDashPhase"])
        #expect(Set(resumed.map(\.beginTime)).count == 1)
    }

    @Test func unchangedAppearanceReusesTheRenderedLayers() throws {
        let view = BeamLayerView()
        let beam = try fixture()
        var renders = 0
        for _ in 0 ..< 3 {
            view.show(key(isStill: false)) {
                renders += 1
                return [beam]
            }
        }
        #expect(renders == 1)
        #expect(view.hitTest(.zero) == nil)
    }

    private func key(isStill: Bool) -> BeamLayerView.Key {
        let size = CGSize(width: 680, height: 44)
        return BeamLayerView.Key(
            size: size,
            scale: 2,
            outline: RoundedRectangle(cornerRadius: 12).path(in: CGRect(origin: .zero, size: size)),
            beam: .colorful,
            isEdge: true,
            isDark: true,
            isStill: isStill,
            frameRate: 60
        )
    }

    private func fixture() throws -> BeamLayer {
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        return BeamLayer(
            colour: [image, image],
            glint: BeamLayer.Glint(stops: BeamLight.glint, light: NSColor.white.cgColor, mask: image),
            window: BeamLight.hairlineWindow,
            opacity: 1
        )
    }

    private func animations(in layer: CALayer) -> [CAAnimation] {
        let own = (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) }
        let children = (layer.sublayers ?? []) + [layer.mask].compactMap(\.self)
        return own + children.flatMap { animations(in: $0) }
    }

    private func keyPaths(of animations: [CAAnimation]) -> Set<String> {
        Set(animations.compactMap { ($0 as? CAPropertyAnimation)?.keyPath })
    }
}
