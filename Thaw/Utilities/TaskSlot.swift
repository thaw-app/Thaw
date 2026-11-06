//
//  TaskSlot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The newest request wins; check its ticket after every await before touching shared state.
/// Cancellation alone cannot stop a task past its last cancellation point.
@MainActor
final class TaskSlot {
    /// A ticket stays current until replacement or cancellation.
    struct Ticket: Equatable, Sendable {
        fileprivate let id = UUID()
    }

    private var task: Task<Void, Never>?
    private var ticket: Ticket?

    /// Whether an operation is still running. False once the current
    /// operation finishes, and false immediately after cancel().
    var isRunning: Bool {
        task != nil
    }

    /// Replace with a fresh ticket; use isCurrent after awaits to reject superseded work.
    func replace(_ operation: @escaping @MainActor (Ticket) async -> Void) {
        task?.cancel()
        let ticket = Ticket()
        self.ticket = ticket
        task = Task { [weak self] in
            await operation(ticket)
            // A superseded operation must not clear its replacement's slot.
            guard let self, self.ticket == ticket else { return }
            self.ticket = nil
            self.task = nil
        }
    }

    /// Whether ticket still identifies the operation in the slot. Call it
    /// after every await before writing shared state.
    func isCurrent(_ ticket: Ticket) -> Bool {
        self.ticket == ticket
    }

    /// Cancels the current operation and makes its ticket stale. Safe to call
    /// when the slot is already empty.
    func cancel() {
        task?.cancel()
        task = nil
        ticket = nil
    }

    /// Wait through replacements until the slot is empty, not just until the original task finishes.
    func waitUntilFinished() async {
        while let task {
            await task.value
        }
    }

    deinit {
        task?.cancel()
    }
}
