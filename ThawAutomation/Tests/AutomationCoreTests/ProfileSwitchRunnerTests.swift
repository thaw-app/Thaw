//
//  ProfileSwitchRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AutomationCore
import Foundation
import Testing
import ThawModuleKit

@MainActor
@Suite("Profile switch runner")
struct ProfileSwitchRunnerTests {
    private let event = ProfileSwitch(
        profileID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        profileName: "Work",
        previousProfileID: nil,
        previousProfileName: nil
    )

    private func configuration() -> HookConfiguration {
        HookConfiguration(
            globalPreHook: HookScript(path: "/global-pre"),
            globalPostHook: HookScript(path: "/global-post"),
            profileHooks: [event.profileID: ProfileAutomation(
                preHook: HookScript(path: "/profile-pre"),
                postHook: HookScript(path: "/profile-post")
            )]
        )
    }

    /// Records each script the runner asks for, with the context it passed.
    @MainActor
    final class Recorder {
        var runs: [(path: String, context: HookRunner.Context)] = []
    }

    @Test("Before a switch the global script runs, then the profile's")
    func runsPreHooksInOrder() async {
        let recorder = Recorder()
        let runner = ProfileSwitchRunner(configuration: configuration) { hook, context in
            if let hook {
                recorder.runs.append((hook.path, context))
            }
        }

        await runner.handle(.willApply, event).value

        #expect(recorder.runs.map(\.path) == ["/global-pre", "/profile-pre"])
        #expect(recorder.runs.map(\.context.scope) == [.global, .profile])
        #expect(recorder.runs.allSatisfy { $0.context.phase == .pre && $0.context.profileName == "Work" })
    }

    @Test("After a switch the profile's script runs, then the global one")
    func runsPostHooksInReverseOrder() async {
        let recorder = Recorder()
        let runner = ProfileSwitchRunner(configuration: configuration) { hook, context in
            if let hook {
                recorder.runs.append((hook.path, context))
            }
        }

        await runner.handle(.didApply, event).value

        #expect(recorder.runs.map(\.path) == ["/profile-post", "/global-post"])
        #expect(recorder.runs.allSatisfy { $0.context.phase == .post })
    }

    @Test("After-switch scripts wait for the before-switch scripts still running")
    func postWaitsForPre() async {
        let recorder = Recorder()
        let runner = ProfileSwitchRunner(configuration: configuration) { hook, context in
            if context.phase == .pre {
                await Task.yield()
            }
            if let hook {
                recorder.runs.append((hook.path, context))
            }
        }

        _ = runner.handle(.willApply, event)
        await runner.handle(.didApply, event).value

        #expect(recorder.runs.map(\.path) == ["/global-pre", "/profile-pre", "/profile-post", "/global-post"])
    }

    @Test("A new switch cancels the scripts of the one before it")
    func newSwitchCancelsTheOld() async {
        let recorder = Recorder()
        let runner = ProfileSwitchRunner(configuration: configuration) { hook, context in
            guard let hook else { return }
            if hook.path == "/global-pre", context.profileName == "Work" {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled {
                    return
                }
            }
            recorder.runs.append((hook.path, context))
        }
        let next = ProfileSwitch(profileID: UUID(), profileName: "Home", previousProfileID: event.profileID, previousProfileName: "Work")

        let first = runner.handle(.willApply, event)
        await runner.handle(.willApply, next).value
        await first.value

        #expect(recorder.runs.map(\.path) == ["/global-pre"])
        #expect(recorder.runs.first?.context.profileName == "Home")
    }

    @Test("A profile with no scripts of its own runs only the global ones")
    func profileWithoutHooks() async {
        let recorder = Recorder()
        let runner = ProfileSwitchRunner(configuration: configuration) { hook, context in
            if let hook {
                recorder.runs.append((hook.path, context))
            }
        }
        let other = ProfileSwitch(profileID: UUID(), profileName: "Home", previousProfileID: nil, previousProfileName: nil)

        await runner.handle(.willApply, other).value

        #expect(recorder.runs.map(\.path) == ["/global-pre"])
    }
}
