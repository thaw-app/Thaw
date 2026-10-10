//
//  NSPanel+Waiting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI
import ThawCapture

extension NSPanel {
    /// Waits until the panel is no longer visible, or until timeout elapses.
    /// Observes isVisible with KVO rather than polling the main thread.
    @MainActor
    func waitUntilClosed(timeout: Duration = .milliseconds(200)) async {
        guard isVisible else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.waitForInvisibleWithKVO()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    @MainActor
    private func waitForInvisibleWithKVO() async {
        var bag = Set<AnyCancellable>()
        let oneShot = OneShotContinuation<Void, Never>()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                oneShot.setContinuation(cont)
                self.publisher(for: \.isVisible)
                    .filter { !$0 }
                    .first()
                    .sink { _ in
                        oneShot.settle(.success(()))
                    }
                    .store(in: &bag)
            }
        } onCancel: {
            oneShot.settle(.success(()))
        }
    }
}
