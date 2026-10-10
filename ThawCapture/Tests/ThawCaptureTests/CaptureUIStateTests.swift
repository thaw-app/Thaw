//
//  CaptureUIStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawCapture

@Suite("Capture UI lifetime")
struct CaptureUIStateTests {
    @Test func closingUIRejectsQueuedCaptureTickets() throws {
        var state = CaptureUIState()
        let queuedRequest = try #require(state.ticket)
        state.setActive(false)
        #expect(state.ticket == nil)
        #expect(!state.accepts(queuedRequest))
    }

    @Test func reopeningDoesNotReviveWorkFromPreviousUI() throws {
        var state = CaptureUIState()
        let oldRequest = try #require(state.ticket)
        state.setActive(false)
        state.setActive(true)
        #expect(!state.accepts(oldRequest))
        #expect(try state.accepts(#require(state.ticket)))
    }

    @Test func anotherVisibleConsumerDoesNotInvalidateCurrentWork() throws {
        var state = CaptureUIState()
        let request = try #require(state.ticket)
        state.setActive(true)
        #expect(state.accepts(request))
    }

    @Test func retiringACaptorDiscardsItsFrameStorage() {
        let captor = FrameCaptor()
        captor.stopRetainingFrames()
        #expect(captor.latestCompleteFrame().stopped)
        #expect(captor.latestCompleteFrame().image == nil)
    }
}
