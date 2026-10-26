//
//  StartedTask.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Starts body in a task on the main actor and returns once that task has run up to its first
/// suspension, however busy the main actor is.
///
/// A task that waits for a held lane queues before it suspends, so it is in line when this returns,
/// where yielding a fixed number of times only makes that likely.
@MainActor
func startedTask<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> Task<T, Never> {
    let (begun, signal) = AsyncStream<Void>.makeStream()
    let task = Task { @MainActor in
        signal.finish()
        return await body()
    }
    for await _ in begun {}
    return task
}

/// Returns once every job queued on the main actor before this call has run to its next suspension.
///
/// The main actor runs its jobs in the order they were queued, so a task that code under test started
/// on it has begun, and a hop it made there has landed, by the time this returns.
@MainActor
func mainActorQueueDrained() async {
    await Task { @MainActor in }.value
}
