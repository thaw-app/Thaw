//
//  MenuBarCaptureServiceConnection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import os.lock
import XPC

extension MenuBarCaptureService {
    /// A connection to the `MenuBarCaptureService` XPC service.
    final class Connection: Sendable {
        static let shared = Connection()

        private let session: Session
        private let queue: DispatchQueue
        private let diagLog: DiagLog
        private let requestIDs = OSAllocatedUnfairLock(initialState: UInt64(0))

        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarCaptureService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let diagLog = DiagLog(category: "MenuBarCaptureService.Connection")
            self.session = Session(queue: queue, diagLog: diagLog)
            self.queue = queue
            self.diagLog = diagLog
        }

        func start() async {
            if let logFile = DiagnosticLogger.shared.currentLogFile {
                _ = await session.sendAsync(request: .configureLogging(filePath: logFile.path))
            }
            _ = await session.sendAsync(request: .start)
        }

        func recycle() async {
            _ = await session.sendAsync(request: .recycle)
            session.cancel(reason: "recycle")
        }

        func capture(
            windowIDs: [CGWindowID],
            scale: CGFloat,
            option: CGWindowImageOption
        ) async -> [Frame] {
            if let frames = await sendCapture(
                windowIDs: windowIDs,
                scale: scale,
                option: option
            ) {
                return frames
            }
            session.cancel(reason: "retry after interruption")
            return await sendCapture(
                windowIDs: windowIDs,
                scale: scale,
                option: option
            ) ?? []
        }

        private func nextRequestID() -> UInt64 {
            requestIDs.withLock { value in
                value += 1
                return value
            }
        }

        private func sendCapture(
            windowIDs: [CGWindowID],
            scale: CGFloat,
            option: CGWindowImageOption
        ) async -> [Frame]? {
            let requestID = nextRequestID()
            let request = Request.captureBatch(
                CaptureBatchRequest(
                    requestID: requestID,
                    windowIDs: windowIDs,
                    optionRawValue: option.rawValue,
                    expectedScale: Double(scale)
                )
            )
            guard let response = await session.sendAsync(request: request) else {
                return nil
            }
            guard let batch = acceptedResponse(requestID: requestID, response: response) else {
                diagLog.error("Capture request \(requestID) got a stale or invalid response")
                return []
            }
            return batch.frames.filter { frame in
                isValidBGRAFrame(
                    width: frame.width,
                    height: frame.height,
                    bytesPerRow: frame.bytesPerRow,
                    pixelCount: frame.pixels.count
                ) && frame.scale > 0 && frame.scale.isFinite
            }
        }
    }
}

extension MenuBarCaptureService {
    private final nonisolated class Session: Sendable {
        private final nonisolated class Storage: @unchecked Sendable {
            private let name = MenuBarCaptureService.name
            private var session: XPCSession?
            private let queue: DispatchQueue
            private let diagLog: DiagLog

            init(queue: DispatchQueue, diagLog: DiagLog) {
                self.queue = queue
                self.diagLog = diagLog
            }

            func getSession() throws -> XPCSession {
                if let session {
                    return session
                }
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else { return }
                    diagLog.warning("Capture session was cancelled with error \(error.localizedDescription)")
                    self.session = nil
                }
                if CodeSigningInfo.processTeamIdentifier != nil {
                    session.setPeerRequirement(.isFromSameTeam())
                }
                session.setTargetQueue(queue)
                try session.activate()
                self.session = session
                return session
            }

            func cancel(reason: String) {
                guard let session = session.take() else { return }
                session.cancel(reason: reason)
            }
        }

        private let storage: OSAllocatedUnfairLock<Storage>
        private let diagLog: DiagLog

        init(queue: DispatchQueue, diagLog: DiagLog) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue, diagLog: diagLog))
            self.diagLog = diagLog
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        func sendAsync(request: Request) async -> Response? {
            let xpcSession: XPCSession
            do {
                xpcSession = try storage.withLock { try $0.getSession() }
            } catch {
                diagLog.error("Failed to get or create capture XPC session: \(error)")
                return nil
            }

            typealias Cont = CheckedContinuation<Response?, Never>
            let box = OSAllocatedUnfairLock<Cont?>(initialState: nil)

            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: Cont) in
                    performXPCSend(xpcSession, request: request, box: box, continuation: continuation)
                }
            } onCancel: {
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
            }
        }

        private func performXPCSend(
            _ xpcSession: XPCSession,
            request: Request,
            box: OSAllocatedUnfairLock<CheckedContinuation<Response?, Never>?>,
            continuation: CheckedContinuation<Response?, Never>
        ) {
            box.withLock { $0 = continuation }
            if Task.isCancelled {
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
                return
            }

            do {
                try xpcSession.send(request) { (result: Result<XPCReceivedMessage, XPCRichError>) in
                    guard let cont = box.withLock({ $0.take() }) else { return }
                    switch result {
                    case let .success(message):
                        do {
                            cont.resume(returning: try message.decode(as: Response.self))
                        } catch {
                            self.diagLog.error("Capture XPC reply decode failed: \(error)")
                            cont.resume(returning: nil)
                        }
                    case let .failure(error):
                        self.diagLog.error("Capture XPC session send failed: \(error)")
                        cont.resume(returning: nil)
                    }
                }
            } catch {
                diagLog.error("Capture XPC session send failed: \(error)")
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
