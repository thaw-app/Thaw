//
//  RevealSettleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw
import ThawCapture

@MainActor
@Suite("Reveal pixel settle")
struct RevealPixelSettleTests {
    /// Answers each read from a script, repeating its last entry.
    private final class Script {
        var reads: [[Data?]?]
        var count = 0
        init(_ reads: [[Data?]?]) {
            self.reads = reads
        }

        func next() -> [Data?]? {
            defer { count += 1 }
            return reads[min(count, reads.count - 1)]
        }
    }

    private func wait(_ script: Script, budget: Duration = .seconds(3600)) async -> RevealCaptureSession.PixelSettle {
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
        #expect(await wait(script) == .settled)
        #expect(script.count == 5)
    }

    @Test("Two matching frames that then change aren't settled; three in a row are")
    func briefPauseIsNotSettled() async {
        let a = Data([1]), b = Data([2])
        let script = Script([[a], [a], [b], [b], [b]])
        #expect(await wait(script) == .settled)
        #expect(script.count == 5)
    }

    @Test("A bar that can't be read ends the wait, and shows nothing held still")
    func unreadableBarEndsTheWait() async {
        let script = Script([nil])
        #expect(await wait(script) == .unread)
        #expect(script.count == 1)
    }

    @Test("A bar that stops being readable partway shows nothing held still")
    func barUnreadableLaterIsUnread() async {
        let a = Data([1])
        let script = Script([[a], nil])
        #expect(await wait(script) == .unread)
        #expect(script.count == 2)
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
        #expect(settled != .settled)
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
        #expect(settled != .settled)
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
        #expect(settled == .unread, "The only read never arrived")
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

@MainActor
@Suite("Reveal settle waits")
struct RevealSettleWaitTests {
    private typealias Session = RevealCaptureSession

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.settle"), title: title, windowID: 7, instanceIndex: 0),
            windowID: 7,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    private static func settleClock(_ clock: TestClock) -> Session.SettleClock {
        Session.SettleClock.driven(by: clock)
    }

    @Test("Members that hold still for one poll settle, paired with their request in request order")
    func membersSettle() async {
        let clock = TestClock()
        let first = Self.item("First", x: 1000), second = Self.item("Second", x: 1100)
        var reads = 0
        let pairs = await Session.waitForRevealedItems(matching: [first, second], clock: Self.settleClock(clock)) {
            reads += 1
            return [second, first]
        }
        #expect(pairs.map(\.requested.tag) == [first.tag, second.tag])
        #expect(pairs.map(\.live.tag) == [first.tag, second.tag])
        #expect(reads == 2)
    }

    @Test("A member that never appears is left out after the last poll")
    func missingMemberIsLeftOut() async {
        let clock = TestClock()
        let shown = Self.item("Shown", x: 1000), missing = Self.item("Missing", x: 1100)
        var reads = 0
        let pairs = await Session.waitForRevealedItems(matching: [shown, missing], clock: Self.settleClock(clock)) {
            reads += 1
            return [shown]
        }
        #expect(pairs.map(\.requested.tag) == [shown.tag])
        #expect(reads == 20)
    }

    @Test("The settle budget ends the polls when reads are slow")
    func budgetEndsThePolls() async {
        let clock = TestClock()
        let moving = Self.item("Moving", x: 1000)
        var reads = 0
        let pairs = await Session.waitForRevealedItems(matching: [moving], clock: Self.settleClock(clock)) {
            reads += 1
            clock.now = clock.now.advanced(by: .seconds(1))
            return [Self.item("Moving", x: 1000 + CGFloat(reads) * 50)]
        }
        #expect(pairs.isEmpty)
        #expect(reads == 3)
    }

    @Test("Nothing requested, or a cancelled wait, reads nothing")
    func emptyOrCancelledReadsNothing() async {
        var reads = 0
        #expect(await Session.waitForRevealedItems(matching: []) {
            reads += 1
            return []
        }.isEmpty)

        let item = Self.item("Cancelled", x: 1000)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Session.waitForRevealedItems(matching: [item]) {
                reads += 1
                return [item]
            }
        }
        #expect(await task.value.isEmpty)
        #expect(reads == 0)
    }

    @Test("Pixels that keep changing run the injected clock out to the budget")
    func pixelBudgetOnTheInjectedClock() async {
        let clock = TestClock()
        let start = clock.now
        var value: UInt8 = 0
        let settled = await Session.waitForSettledPixels(minimumSettle: .zero, budget: .seconds(1), clock: Self.settleClock(clock)) {
            value &+= 1
            return [Data([value])]
        }
        #expect(settled == .changing([0]))
        #expect(value == 10)
        #expect(clock.now - start == .seconds(1))
    }

    @Test("Only the frame that keeps changing is reported; the one that held still is settled")
    func pixelSettleIsPerFrame() async {
        let clock = TestClock()
        var value: UInt8 = 0
        let settled = await Session.waitForSettledPixels(minimumSettle: .zero, budget: .seconds(1), clock: Self.settleClock(clock)) {
            value &+= 1
            return [Data([0]), Data([value])]
        }
        #expect(settled == .changing([1]))
        #expect(!settled.mayBeChanging(at: 0))
        #expect(settled.mayBeChanging(at: 1))
    }

    @Test("A revealed batch whose pixels hold still settles after three matching screenshots")
    func revealedPixelsSettle() async throws {
        let clock = TestClock()
        let reader = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008]), strip: nil)
        await Session.settleRevealedPixels([Self.item("Still", x: 1000)], displayID: 42, reader: reader, clock: Self.settleClock(clock))
        #expect(await reader.captures == [.hosting, .hosting, .hosting])
    }
}

/// A hidden section's first pictures after a reveal wait for its icons to finish sliding in.
@MainActor
@Suite("Revealed section settle", .serialized, .scratchDefaults)
struct RevealedSectionSettleTests {
    private typealias Cache = MenuBarItemImageCache

    private static func item(windowID: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.settle"), title: "Item", windowID: windowID, instanceIndex: 0),
            windowID: windowID, ownerPID: 501, sourcePID: 501,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22), title: "Item", isOnScreen: true
        )
    }

    @Test("The wait reads the bar until the icons hold still, on the frames read now, and skips items not on the bar")
    func settleReadsLiveFrames() async throws {
        let clock = TestClock()
        let settleClock = RevealCaptureSession.SettleClock.driven(by: clock)
        let parked = Self.item(windowID: 7, x: -2000)
        let live = Self.item(windowID: 9, x: 1000)
        let reader = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008]), strip: nil, items: [live])
        await Cache().settleRevealedSection([parked], appState: AppState(), reader: reader, clock: settleClock)
        #expect(await reader.captures.count == 3, "three matching reads, and it settles")

        let empty = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008]), strip: nil)
        await Cache().settleRevealedSection([live], appState: AppState(), reader: empty, clock: settleClock)
        #expect(await empty.captures.isEmpty, "nothing on the bar to wait for")
    }

    @Test("A reflowing bar skips a pass, until enough were skipped in a row")
    func reflowSkipIsBounded() {
        #expect(Cache.skipsPassForReflow(reflowing: true, consecutiveSkips: 0))
        #expect(Cache.skipsPassForReflow(reflowing: true, consecutiveSkips: Cache.maximumReflowSkips - 1))
        #expect(Cache.skipsPassForReflow(reflowing: true, consecutiveSkips: Cache.maximumReflowSkips) == false)
        #expect(Cache.skipsPassForReflow(reflowing: false, consecutiveSkips: 0) == false)
    }

    @Test("A section just revealed waits; the visible section and later passes don't")
    func waitsOnlyRightAfterAReveal() {
        let now = ContinuousClock.now
        let justNow = now - .milliseconds(300)
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: .hidden, lastRevealChange: justNow, now: now))
        #expect(Cache.settlesRevealedPixels(for: .alwaysHidden, revealedSection: .alwaysHidden, lastRevealChange: justNow, now: now))
        #expect(Cache.settlesRevealedPixels(for: .visible, revealedSection: .hidden, lastRevealChange: justNow, now: now) == false)
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: nil, lastRevealChange: justNow, now: now) == false)
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: .hidden, lastRevealChange: nil, now: now) == false)
        let longAgo = now - Cache.revealedSettleWindow
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: .hidden, lastRevealChange: longAgo, now: now) == false)
    }
}
