//
//  LaunchAtLoginSettingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct LaunchAtLoginSettingTests {
    @Test("Rendering the cached login setting performs no status queries or writes")
    func bindingReadsAreCached() async {
        let service = LoginService()
        let setting = service.makeSetting()
        #expect(!setting.isLoaded)
        #expect(service.readCount == 0)

        await setting.refresh()
        for _ in 0 ..< 1000 {
            #expect(setting.isEnabled)
        }
        #expect(setting.isLoaded)
        #expect(service.readCount == 1)
        #expect(service.writes.isEmpty)
    }

    @Test("A later refresh picks up a change made outside Thaw")
    func refreshReadsExternalChange() async {
        let service = LoginService()
        let setting = service.makeSetting()
        await setting.refresh()
        service.enabled = false
        await setting.refresh()
        #expect(!setting.isEnabled)
        #expect(service.readCount == 2)
        #expect(service.writes.isEmpty)
    }

    @Test("Explicit toggles write once and publish the confirmed system value", arguments: [false, true])
    func settingUsesReadback(acceptsWrite: Bool) async {
        let service = LoginService()
        service.acceptsWrites = acceptsWrite
        let setting = service.makeSetting()
        await setting.refresh()
        await setting.setEnabled(false)
        #expect(service.writes == [false])
        #expect(service.readCount == 2)
        #expect(setting.isEnabled == !acceptsWrite)
        #expect(!setting.isUpdating)
    }

    @Test("A toggle cannot write before its initial status is known")
    func unloadedSettingCannotWrite() async {
        let service = LoginService()
        let setting = service.makeSetting()
        await setting.setEnabled(true)
        #expect(service.writes.isEmpty)
        #expect(service.readCount == 0)
    }

    @Test("An older refresh cannot overwrite the newest answer")
    func latestRefreshWins() async {
        let reads = PendingLoginReads()
        var requests = reads.requests.makeAsyncIterator()
        let setting = LaunchAtLoginSetting(readStatus: { await reads.read() }, writeStatus: { _ in
            Issue.record("Refreshing must not change registration")
        })
        let older = Task { await setting.refresh() }
        await requests.next()
        let newer = Task { await setting.refresh() }
        await requests.next()
        reads.finish(at: 1, enabled: true)
        await newer.value
        reads.finish(at: 0, enabled: false)
        await older.value
        #expect(setting.isEnabled)
    }

    @Test("Leaving the pane prevents a cancelled refresh from publishing")
    func cancelledRefreshDoesNotPublish() async {
        let reads = PendingLoginReads()
        var requests = reads.requests.makeAsyncIterator()
        let setting = LaunchAtLoginSetting(readStatus: { await reads.read() }, writeStatus: { _ in })
        let refresh = Task { await setting.refresh() }
        await requests.next()
        refresh.cancel()
        reads.finish(at: 0, enabled: true)
        await refresh.value
        #expect(!setting.isLoaded)
    }

    @Test("A pending read cannot undo a toggle, and overlapping toggles cannot write")
    func refreshCannotUndoToggle() async {
        let reads = PendingLoginReads()
        var requests = reads.requests.makeAsyncIterator()
        var writes = [Bool]()
        let setting = LaunchAtLoginSetting(readStatus: { await reads.read() }, writeStatus: { writes.append($0) })
        let initial = Task { await setting.refresh() }
        await requests.next()
        reads.finish(at: 0, enabled: true)
        await initial.value

        let stale = Task { await setting.refresh() }
        await requests.next()
        let update = Task { await setting.setEnabled(false) }
        await requests.next()
        #expect(setting.isUpdating)
        await setting.setEnabled(true)
        await setting.refresh()
        #expect(writes == [false])
        #expect(reads.pending.count == 2)

        // Navigation cancellation must not suppress readback after the write.
        update.cancel()
        reads.finish(at: 1, enabled: false)
        await update.value
        reads.finish(at: 0, enabled: true)
        await stale.value
        #expect(!setting.isEnabled)
        #expect(!setting.isUpdating)
    }
}

@MainActor
private final class LoginService {
    var enabled = true
    var acceptsWrites = true
    var readCount = 0
    var writes = [Bool]()

    func read() -> Bool {
        readCount += 1
        return enabled
    }

    func makeSetting() -> LaunchAtLoginSetting {
        LaunchAtLoginSetting(readStatus: { await self.read() }, writeStatus: { enabled in
            self.writes.append(enabled)
            if self.acceptsWrites {
                self.enabled = enabled
            }
        })
    }
}

@MainActor
private final class PendingLoginReads {
    let requests: AsyncStream<Void>
    private let requestContinuation: AsyncStream<Void>.Continuation
    private(set) var pending = [CheckedContinuation<Bool, Never>]()

    init() {
        (requests, requestContinuation) = AsyncStream.makeStream()
    }

    func read() async -> Bool {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            requestContinuation.yield()
        }
    }

    func finish(at index: Int, enabled: Bool) {
        pending.remove(at: index).resume(returning: enabled)
    }
}
