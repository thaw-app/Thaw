//
//  ScreenCapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import os.lock
@_exported import ThawConcurrency

typealias ProbeLoggingProvider = @Sendable () -> Bool

/// A namespace for screen capture operations.
public enum ScreenCapture {
    static let diagLog = DiagLog(category: "ScreenCapture")
    static let cachedPermissionResult = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    static let probeLoggingProvider = OSAllocatedUnfairLock<ProbeLoggingProvider>(initialState: { false })

    /// Registers a live predicate for diagnostic probe logging.
    public static func setProbeLoggingEnabled(_ f: @escaping @Sendable () -> Bool) {
        probeLoggingProvider.withLock { $0 = f }
    }

    static func isProbeLoggingEnabled() -> Bool {
        probeLoggingProvider.withLock { $0() }
    }
}

public extension ScreenCapture {
    /// Set once at launch before capture to safely route through MenuBarCaptureService.
    /// The helper leaves this off so its own captures stay in-process.
    static nonisolated(unsafe) var routesThroughCaptureService = false
}

public extension ScreenCapture {
    /// Whether a capture asked for now would run. With no Thaw surface open it is refused, which is not a failed read.
    static var acceptsCaptures: Bool {
        captureUITicket() != nil
    }

    /// Call synchronously whenever the set of visible capture consumers changes.
    /// Closing the final UI invalidates queued requests before stream cleanup runs.
    static func setCaptureUIActive(_ active: Bool) {
        let ticket = captureUIState.withLock { state -> UInt64? in
            guard state.uiActive != active else { return nil }
            state.setActive(active)
            return state.generation
        }
        guard let ticket else { return }
        diagLog.info("CaptureUI: active=\(active) generation=\(ticket)")
        if !active {
            Task {
                await DisplayStripCaptureSession.shared.retireBeforeVisibilityGeneration(ticket)
                await MenuBarCaptureServiceClient.shared.closeForHiddenUI(generation: ticket)
            }
        }
    }
}

extension ScreenCapture {
    private static let captureUIState = OSAllocatedUnfairLock(initialState: CaptureUIState())

    static func captureUITicket() -> UInt64? {
        captureUIState.withLock { $0.ticket }
    }

    static func isCaptureUITicketCurrent(_ ticket: UInt64) -> Bool {
        captureUIState.withLock { $0.accepts(ticket) }
    }

    static func isCaptureUIClosed(at generation: UInt64) -> Bool {
        captureUIState.withLock { !$0.isCapturing && $0.generation == generation }
    }

    /// Borrows a ticket with no UI open so the Clock bridge can capture a reveal mask without exposing the reveal.
    /// Does not retire strip sessions or close the helper; this is a one-shot lease, not a UI transition.
    public static func withOneshotCaptureTicket<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        captureUIState.withLock { $0.beginOneshot() }
        let result = await body()
        captureUIState.withLock { $0.endOneshot() }
        return result
    }
}

struct CaptureUIState {
    /// Whether an actual Thaw surface is open and consuming capture.
    private(set) var uiActive = true

    /// Number of one-shot captures borrowing a ticket while no UI is open.
    private(set) var oneshotLeases = 0

    private(set) var generation: UInt64 = 0

    var isCapturing: Bool {
        uiActive || oneshotLeases > 0
    }

    var ticket: UInt64? {
        isCapturing ? generation : nil
    }

    mutating func setActive(_ value: Bool) {
        guard uiActive != value else { return }
        let wasCapturing = isCapturing
        uiActive = value
        if isCapturing != wasCapturing {
            generation &+= 1
        }
    }

    mutating func beginOneshot() {
        oneshotLeases += 1
        if oneshotLeases == 1, !uiActive {
            generation &+= 1
        }
    }

    mutating func endOneshot() {
        oneshotLeases = max(0, oneshotLeases - 1)
        if oneshotLeases == 0, !uiActive {
            generation &+= 1
        }
    }

    func accepts(_ ticket: UInt64) -> Bool {
        isCapturing && generation == ticket
    }
}
