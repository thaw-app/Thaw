//
//  RevealPixelSettleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw
import ThawCapture

@MainActor
@Suite("Reveal pixel settle")
struct RevealPixelSettleTests {
    /// Answers each read from a script, repeating its last entry.
    private final class Script {
        var reads: [[Data]?]
        var count = 0
        init(_ reads: [[Data]?]) {
            self.reads = reads
        }

        func next() -> [Data]? {
            defer { count += 1 }
            return reads[min(count, reads.count - 1)]
        }
    }

    private func wait(_ script: Script, budget: Duration = .seconds(3600)) async -> Bool {
        await RevealCaptureSession.waitForSettledPixels(
            minimumSettle: .zero,
            interval: .zero,
            budget: budget,
            clock: .init(sleep: { _ in await Task.yield() }),
            read: { script.next() }
        )
    }

    @Test("Keeps reading while a glyph slides, and stops at the first three matching frames")
    func waitsOutASlide() async {
        let a = Data([1]), b = Data([2]), c = Data([3])
        let script = Script([[a], [b], [c], [c], [c], [a]])
        #expect(await wait(script))
        #expect(script.count == 5)
    }

    @Test("Two matching frames that then change aren't settled; three in a row are")
    func briefPauseIsNotSettled() async {
        let a = Data([1]), b = Data([2])
        let script = Script([[a], [a], [b], [b], [b]])
        #expect(await wait(script))
        #expect(script.count == 5)
    }

    @Test("A bar that can't be read ends the wait")
    func unreadableBarEndsTheWait() async {
        let script = Script([nil])
        #expect(await wait(script))
        #expect(script.count == 1)
    }

    @Test("With the default sleep, an icon that keeps changing still runs out the budget")
    func realClockBudget() async {
        var value: UInt8 = 0
        let settled = await RevealCaptureSession.waitForSettledPixels(
            minimumSettle: .zero,
            interval: .milliseconds(1),
            budget: .milliseconds(5),
            read: {
                value &+= 1
                return [Data([value])]
            }
        )
        #expect(!settled)
    }

    @Test("An icon that never stops changing runs out the budget")
    func constantChangeHitsTheBudget() async {
        var value: UInt8 = 0
        let settled = await RevealCaptureSession.waitForSettledPixels(
            minimumSettle: .zero,
            interval: .zero,
            budget: .milliseconds(20),
            clock: .init(sleep: { _ in await Task.yield() }),
            read: {
                value &+= 1
                return [Data([value])]
            }
        )
        #expect(!settled)
    }

    /// The read stays suspended until the test opens the gate, which it does only after the wait
    /// returns. No wall-clock check: a stalled runner can't fail it.
    @Test("A read slower than the budget doesn't count, and doesn't hold the wait")
    func slowReadEndsAtTheBudget() async {
        let gate = ReadGate()
        let settled = await RevealCaptureSession.waitForSettledPixels(
            minimumSettle: .zero,
            interval: .zero,
            budget: .milliseconds(20),
            clock: .init(sleep: { _ in await Task.yield() }),
            read: { await gate.read() }
        )
        #expect(!settled)
        #expect(!gate.finished, "the wait returned while the read was still suspended")
        gate.open()
    }

    @Test("The fingerprint sees a glyph move inside its frame, and ignores the rest of the bar")
    func fingerprintFollowsTheFrame() throws {
        let frame = CGRect(x: 10, y: 0, width: 10, height: 10)
        let inPlace = try capture(inkAtX: 12)
        let sameAgain = try capture(inkAtX: 12)
        let moved = try capture(inkAtX: 14)
        #expect(RevealCaptureSession.pixelFingerprint(of: [frame], in: inPlace)
            == RevealCaptureSession.pixelFingerprint(of: [frame], in: sameAgain))
        #expect(RevealCaptureSession.pixelFingerprint(of: [frame], in: inPlace)
            != RevealCaptureSession.pixelFingerprint(of: [frame], in: moved))

        let elsewhere = try capture(inkAtX: 12, extraInkAtX: 30)
        #expect(RevealCaptureSession.pixelFingerprint(of: [frame], in: inPlace)
            == RevealCaptureSession.pixelFingerprint(of: [frame], in: elsewhere))
    }

    @Test("A tag counts as captured across a window ID change")
    func capturedTagMatching() {
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "Item", windowID: 1)
        let rebuilt = MenuBarItemTag(namespace: .string("com.example.app"), title: "Item", windowID: 2)
        #expect(MenuBarItemImageCache.isTag(tag, in: [tag]))
        #expect(MenuBarItemImageCache.isTag(rebuilt, in: [tag]))
        #expect(!MenuBarItemImageCache.isTag(rebuilt, in: []))
    }

    /// A read that suspends until the gate opens. Opening it before the read starts lets the read
    /// return at once, so no task is left suspended after the test.
    @MainActor
    private final class ReadGate {
        private(set) var finished = false
        private var isOpen = false
        private var waiting: CheckedContinuation<Void, Never>?

        func read() async -> [Data]? {
            if !isOpen {
                await withCheckedContinuation { waiting = $0 }
            }
            finished = true
            return [Data([1])]
        }

        func open() {
            isOpen = true
            waiting?.resume()
            waiting = nil
        }
    }

    private func capture(inkAtX x: Int, extraInkAtX extra: Int? = nil) throws -> ScreenCapture.MenuBarHostingCapture {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: x, y: 2, width: 3, height: 6))
        if let extra {
            context.fill(CGRect(x: extra, y: 2, width: 3, height: 6))
        }
        let image = try #require(context.makeImage())
        return ScreenCapture.MenuBarHostingCapture(
            image: image,
            windowFrame: CGRect(x: 0, y: 0, width: 40, height: 10),
            scale: 1
        )
    }
}
