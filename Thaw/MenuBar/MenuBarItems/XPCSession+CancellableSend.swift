//
//  XPCSession+CancellableSend.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import os.lock
import XPC

extension XPCSession {
    /// Sends `request` and returns the decoded reply, or nil on failure or cancellation.
    ///
    /// Non-blocking, so cooperative threads are never stranded. Exactly one
    /// of the reply or cancellation handler resumes the continuation, so
    /// Task cancellation unblocks the caller immediately.
    ///
    /// - Parameters:
    ///   - onDecodeFailure: Called when the reply can't be decoded.
    ///   - onSendFailure: Called when the send throws or the reply is an error.
    nonisolated func sendCancellable<Response: Decodable & Sendable>(
        _ request: some Encodable & Sendable,
        as _: Response.Type,
        onDecodeFailure: @escaping @Sendable (any Error) -> Void,
        onSendFailure: @escaping @Sendable (any Error) -> Void
    ) async -> Response? {
        // Whichever path takes the continuation out of the box resumes it;
        // the other sees nil.
        typealias Cont = CheckedContinuation<Response?, Never>
        let box = OSAllocatedUnfairLock<Cont?>(initialState: nil)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: Cont) in
                performCancellableSend(
                    request,
                    box: box,
                    continuation: continuation,
                    onDecodeFailure: onDecodeFailure,
                    onSendFailure: onSendFailure
                )
            }
        } onCancel: {
            // Arbitrary thread.
            if let cont = box.withLock({ $0.take() }) {
                cont.resume(returning: nil)
            }
        }
    }

    private nonisolated func performCancellableSend<Response: Decodable & Sendable>(
        _ request: some Encodable & Sendable,
        box: OSAllocatedUnfairLock<CheckedContinuation<Response?, Never>?>,
        continuation: CheckedContinuation<Response?, Never>,
        onDecodeFailure: @escaping @Sendable (any Error) -> Void,
        onSendFailure: @escaping @Sendable (any Error) -> Void
    ) {
        box.withLock { $0 = continuation }

        // Cancelled already: claim and resume without sending.
        if Task.isCancelled {
            if let cont = box.withLock({ $0.take() }) {
                cont.resume(returning: nil)
            }
            return
        }

        do {
            try send(request) { (result: Result<XPCReceivedMessage, XPCRichError>) in
                guard let cont = box.withLock({ $0.take() }) else { return }
                switch result {
                case let .success(message):
                    do {
                        let decoded = try message.decode(as: Response.self)
                        cont.resume(returning: decoded)
                    } catch {
                        onDecodeFailure(error)
                        cont.resume(returning: nil)
                    }
                case let .failure(error):
                    onSendFailure(error)
                    cont.resume(returning: nil)
                }
            }
        } catch {
            onSendFailure(error)
            if let cont = box.withLock({ $0.take() }) {
                cont.resume(returning: nil)
            }
        }
    }
}
