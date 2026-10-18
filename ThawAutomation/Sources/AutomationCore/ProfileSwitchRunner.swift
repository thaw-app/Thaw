//
//  ProfileSwitchRunner.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawModuleKit

/// Runs the scripts for each profile switch: the global pair wraps the profile pair, after-switch scripts
/// wait for before-switch ones still running, and a new switch cancels the last one's scripts.
@MainActor
public final class ProfileSwitchRunner {
    public typealias Run = @MainActor (HookScript?, HookRunner.Context) async -> Void

    private let configuration: @MainActor () -> HookConfiguration
    private let run: Run
    private var current: Task<Void, Never>?

    public init(configuration: @escaping @MainActor () -> HookConfiguration, run: @escaping Run) {
        self.configuration = configuration
        self.run = run
    }

    /// Starts the scripts for one event and returns their task.
    @discardableResult
    public func handle(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch) -> Task<Void, Never> {
        let hooks = configuration()
        let profileHooks = hooks.profileHooks[event.profileID]
        let steps: [(HookScript?, HookScope)] = switch phase {
        case .willApply: [(hooks.globalPreHook, .global), (profileHooks?.preHook, .profile)]
        case .didApply: [(profileHooks?.postHook, .profile), (hooks.globalPostHook, .global)]
        }
        let hookPhase: HookPhase = phase == .willApply ? .pre : .post
        let previous = current
        if phase == .willApply {
            previous?.cancel()
        }
        let run = run
        let task = Task { @MainActor in
            if phase == .didApply {
                await previous?.value
            }
            for (hook, scope) in steps {
                guard !Task.isCancelled else { return }
                await run(hook, HookRunner.Context(
                    phase: hookPhase,
                    scope: scope,
                    profileID: event.profileID,
                    profileName: event.profileName,
                    previousProfileID: event.previousProfileID,
                    previousProfileName: event.previousProfileName
                ))
            }
        }
        current = task
        return task
    }
}
