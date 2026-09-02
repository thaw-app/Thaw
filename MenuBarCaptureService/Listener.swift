//
//  Listener.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import XPC

/// XPC listener for offscreen SkyLight capture.
///
/// Explicitly nonisolated: XPC callbacks arrive on arbitrary threads, and the
/// target's default actor isolation is MainActor.
final nonisolated class Listener: @unchecked Sendable {
    private let diagLog = DiagLog(category: "CaptureListener")
    static let shared = Listener()

    private let name = MenuBarCaptureService.name
    private var xpcListener: XPCListener?
    private let captureLock = NSLock()
    private let instanceID = UInt64.random(in: .min ... .max)
    private var captureCount = 0

    private init() {
        // Intentionally empty: the Connection is a singleton whose state
        // initializes at its property declarations, so there is nothing to
        // do here. The private visibility keeps external callers on `shared`.
    }

    deinit {
        cancel()
    }

    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarCaptureService.Response? {
        do {
            let request = try message.decode(as: MenuBarCaptureService.Request.self)
            switch request {
            case .start:
                return .start
            case let .configureLogging(filePath, rotationPolicy):
                if let rotationPolicy {
                    // The app owns the shared log directory's retention, so
                    // pruning here follows its policy instead of this
                    // target's defaults.
                    DiagnosticLogger.shared.setRotationPolicy(rotationPolicy)
                }
                guard let filePath else {
                    // Diagnostic logging is off in the app; stop holding the
                    // shared file open here too.
                    DiagnosticLogger.shared.isEnabled = false
                    return .configureLogging
                }
                let requested = URL(fileURLWithPath: filePath)
                    .standardizedFileURL.resolvingSymlinksInPath()
                let approvedDir = DiagnosticLogger.shared.logDirectory
                    .standardizedFileURL.resolvingSymlinksInPath()
                guard requested.path.hasPrefix(approvedDir.path + "/") else {
                    diagLog.error(
                        "Capture listener rejected configureLogging path outside approved log directory: \(filePath)"
                    )
                    return nil
                }
                guard DiagnosticLogger.shared.attachToFile(at: requested) else {
                    // Answering success here would leave the app believing
                    // both processes share a file while this one keeps
                    // writing to the previous segment — which retention
                    // eventually deletes out from under it. Failing the
                    // request makes the app retry.
                    diagLog.error(
                        "Capture listener failed to attach diagnostic logging to \(requested.path)"
                    )
                    return nil
                }
                return .configureLogging
            case let .captureBatch(batch):
                return capture(batch)
            case .recycle:
                scheduleExit()
                return .recycle
            }
        } catch {
            diagLog.error("Capture listener failed to handle message with error \(error)")
            return nil
        }
    }

    private func capture(_ request: MenuBarCaptureService.CaptureBatchRequest) -> MenuBarCaptureService.Response {
        captureLock.lock()
        defer { captureLock.unlock() }

        let frames = autoreleasepool { () -> [MenuBarCaptureService.Frame] in
            captureFrames(request)
        }
        if MenuBarCaptureService.shouldRecycle(captureCount: captureCount) {
            scheduleExit()
        }
        return .captureBatch(
            MenuBarCaptureService.CaptureBatchResponse(
                requestID: request.requestID,
                instanceID: instanceID,
                frames: frames
            )
        )
    }

    private func captureFrames(
        _ request: MenuBarCaptureService.CaptureBatchRequest
    ) -> [MenuBarCaptureService.Frame] {
        let scale = CGFloat(request.expectedScale)
        guard scale > 0, scale.isFinite else { return [] }

        let allowed = Set(Bridging.getMenuBarWindowList(option: .itemsOnly))
        let windowIDs = MenuBarCaptureService.validatedWindowIDs(request.windowIDs, allowed: allowed)
        guard !windowIDs.isEmpty else { return [] }

        var storage = [CGWindowID: CGRect]()
        var orderedIDs = [CGWindowID]()
        var boundsUnion = CGRect.null
        for windowID in windowIDs {
            guard let bounds = Bridging.getWindowBounds(for: windowID) else { continue }
            guard Bridging.isValidCaptureBounds(bounds, scale: scale) else { continue }
            storage[windowID] = bounds
            orderedIDs.append(windowID)
            boundsUnion = boundsUnion.union(bounds)
        }
        guard !orderedIDs.isEmpty,
              Bridging.isValidCaptureBounds(boundsUnion, scale: scale)
        else {
            return []
        }

        let options = CGWindowImageOption(rawValue: request.optionRawValue)
        let composite = Bridging.captureWindowsImage(
            windowIDs: orderedIDs,
            options: options
        )
        guard let composite else {
            diagLog.debug("captureFrames: SkyLight returned nil for \(orderedIDs.count) windows")
            return []
        }
        captureCount += 1

        let expectedWidth = boundsUnion.width * scale
        guard abs(CGFloat(composite.width) - expectedWidth) < 1 else {
            diagLog.debug(
                "captureFrames: width mismatch (expected \(expectedWidth), got \(composite.width))"
            )
            return []
        }

        if let encoded = MenuBarCaptureService.encodeBGRA(composite),
           MenuBarCaptureService.isFullyTransparentBGRA(
               pixels: encoded.pixels,
               width: composite.width,
               height: composite.height,
               bytesPerRow: encoded.bytesPerRow
           )
        {
            return []
        }

        var frames = [MenuBarCaptureService.Frame]()
        var batchBytes = 0
        for windowID in orderedIDs {
            guard let bounds = storage[windowID] else { continue }
            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * scale,
                y: (bounds.origin.y - boundsUnion.origin.y) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            guard let cropped = composite.cropping(to: cropRect),
                  let encoded = MenuBarCaptureService.encodeBGRA(cropped)
            else {
                continue
            }
            batchBytes += encoded.pixels.count
            guard batchBytes <= 16 * 1024 * 1024 else { break }
            frames.append(
                MenuBarCaptureService.Frame(
                    windowID: windowID,
                    width: cropped.width,
                    height: cropped.height,
                    bytesPerRow: encoded.bytesPerRow,
                    scale: request.expectedScale,
                    pixels: encoded.pixels
                )
            )
        }
        return frames
    }

    private func scheduleExit() {
        DispatchQueue.main.async {
            exit(0)
        }
    }

    private func uncheckedActivateWithSameTeamRequirement() throws {
        xpcListener = try XPCListener(service: name, requirement: .isFromSameTeam()) { request in
            request.accept { [self] message in
                self.handleMessage(message)
            }
        }
    }

    private func uncheckedActivateWithoutPeerRequirement() throws {
        xpcListener = try XPCListener(service: name) { request in
            request.accept { [self] message in
                self.handleMessage(message)
            }
        }
        diagLog.warning(
            "Capture listener is active WITHOUT peer validation (ad-hoc/teamless build): any local process may connect"
        )
    }

    func activate() {
        guard xpcListener == nil else {
            diagLog.notice("Capture listener is already active")
            return
        }
        do {
            if CodeSigningInfo.processTeamIdentifier == nil {
                try uncheckedActivateWithoutPeerRequirement()
            } else {
                try uncheckedActivateWithSameTeamRequirement()
            }
        } catch {
            diagLog.error("Failed to activate capture listener with error \(error)")
        }
    }

    func cancel() {
        xpcListener.take()?.cancel()
    }
}
