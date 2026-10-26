//
//  DisplayChangeCoordinator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel

/// What the coordinator's steps do to the rest of the app.
@MainActor
protocol DisplayChangeEffects: AnyObject {
    func stampDisplayChanged()
    func startSettle(reason: String)
    func awaitSettle() async
    func refreshCaches(cleansImages: Bool) async
}

/// Runs the work a display change owes once per settled generation, in the order ``DisplayChangePlan`` gives.
/// Each step first checks the generation it started for: a newer one abandons the rest, and its own run
/// starts the order again.
@MainActor
final class DisplayChangeCoordinator {
    private let snapshot: EnvironmentSnapshot
    private let settlements: AnyPublisher<EnvironmentChange, Never>
    private let effects: any DisplayChangeEffects
    private let slot = TaskSlot()
    private var subscription: AnyCancellable?
    private let diagLog = DiagLog(category: "DisplayChangeCoordinator")

    init(snapshot: EnvironmentSnapshot, settlements: some Publisher<EnvironmentChange, Never>, effects: any DisplayChangeEffects) {
        self.snapshot = snapshot
        self.settlements = settlements.eraseToAnyPublisher()
        self.effects = effects
    }

    convenience init(environment: DisplayEnvironment, effects: any DisplayChangeEffects) {
        self.init(snapshot: environment.snapshot, settlements: environment.settlements, effects: effects)
    }

    /// Starts listening for settles. Calling it again while listening does nothing.
    func start() {
        guard subscription == nil else { return }
        subscription = settlements.sink { [weak self] change in
            self?.run(change)
        }
    }

    func stop() {
        subscription = nil
        slot.cancel()
    }

    /// Returns once no run is in progress.
    func waitUntilIdle() async {
        await slot.waitUntilFinished()
    }

    private func run(_ change: EnvironmentChange) {
        let steps = DisplayChangePlan.steps(for: change)
        guard !steps.isEmpty else { return }
        let generation = snapshot.generation
        slot.replace { [weak self] _ in
            await self?.perform(steps, for: change, generation: generation)
        }
    }

    private func perform(_ steps: [DisplayChangeStep], for change: EnvironmentChange, generation: Int) async {
        diagLog.info("Display change generation \(generation) (\(change.rawValue)): running \(steps.count) steps")
        for step in steps {
            guard snapshot.generation == generation else {
                diagLog.info("Display change generation \(generation) superseded by \(snapshot.generation) before \(step); abandoning")
                return
            }
            await perform(step)
        }
        diagLog.info("Display change generation \(generation) (\(change.rawValue)) done")
    }

    private func perform(_ step: DisplayChangeStep) async {
        switch step {
        case .stampDisplayChanged:
            effects.stampDisplayChanged()
        case let .startSettle(reason):
            effects.startSettle(reason: reason)
        case .awaitSettle:
            await effects.awaitSettle()
        case let .refreshCaches(cleansImages):
            await effects.refreshCaches(cleansImages: cleansImages)
        }
    }
}
