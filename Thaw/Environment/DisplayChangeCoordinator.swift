//
//  DisplayChangeCoordinator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel

@MainActor
protocol DisplayChangeEffects: AnyObject {
    func stampDisplayChanged()
    func startSettle(reason: String)
    func awaitSettle() async
    func cleanImagesAfterRemoval() async
}

/// Runs a display change's steps once per settled generation. A newer generation abandons the rest
/// of the run and starts the steps again.
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

    /// Calling it again while listening does nothing.
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
        case .cleanImages:
            await effects.cleanImagesAfterRemoval()
        }
    }
}
