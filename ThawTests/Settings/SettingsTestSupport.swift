//
//  SettingsTestSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// What the settings process sent, as the app would receive it.
@MainActor
final class SettingsLinkOutbox {
    private(set) var messages = [SettingsLinkMessage]()
    private(set) lazy var remote = SettingsRemote { [weak self] in self?.messages.append($0) }

    /// The payloads of the commands sent under this name, decoded, in the order they were sent.
    func commands<Payload: Decodable>(_ name: String, as _: Payload.Type = Payload.self) -> [Payload] {
        messages.compactMap { message in
            guard case .command(name, let payload) = message else { return nil }
            return SettingsLinkPayload.decode(Payload.self, from: payload)
        }
    }
}

extension MenuBarItem {
    /// An on-screen item of a made-up app, placed at x, whose window ID follows from x.
    static func fixture(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}

extension MenuBarItemGlyphCapture {
    /// A capture of the given pixel size, filled black inside inset, or left transparent.
    static func sample(
        width: Int,
        height: Int = 16,
        inset: Int = 0,
        filled: Bool = true,
        scale: CGFloat = 1
    ) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if filled {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset))
        }
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
    }
}
