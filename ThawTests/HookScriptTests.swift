//
//  HookScriptTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``HookScript``'s model surface and its global-hook persistence.
///
/// `HookRunnerTests` covers what happens when a hook actually runs. What is
/// left, and what this suite pins, is everything around that: the stored shape
/// the settings UI reads and writes, and the two `UserDefaults` slots the
/// global hooks live in.
///
/// The persistence half has one property that is easy to get wrong and
/// invisible when it is: the pre- and post-hook must occupy *different* keys.
/// A copy-paste slip in `loadGlobal`/`saveGlobal` would make configuring a
/// post-hook silently replace the pre-hook, and both would then run at the
/// wrong phase. The suite also pins that a corrupt payload degrades to nil
/// rather than throwing, since these are read during profile application where
/// there is nowhere to surface an error.
///
/// `Defaults.store` is process-wide, so the suite is serialized and routes
/// every case through a scratch domain.
@MainActor
@Suite("Profile-apply hooks", .serialized)
struct HookScriptTests {
    // MARK: - Model

    @Test("A hook takes the documented defaults")
    func hookTakesTheDocumentedDefaults() {
        let hook = HookScript(path: "/tmp/hook.sh")

        #expect(hook.path == "/tmp/hook.sh")
        #expect(hook.timeoutSeconds == 5)
        #expect(hook.isEnabled)
    }

    @Test("Explicit values override the defaults")
    func explicitValuesOverrideTheDefaults() {
        let hook = HookScript(path: "/tmp/hook.sh", timeoutSeconds: 30, isEnabled: false)

        #expect(hook.timeoutSeconds == 30)
        #expect(!hook.isEnabled)
    }

    /// The path is documented as stored verbatim: the run-time decision about
    /// how to invoke it is made later, so no normalization happens here.
    @Test("The path is stored verbatim")
    func pathIsStoredVerbatim() {
        let path = "  ~/Library/Scripts/my hook.scpt  "

        #expect(HookScript(path: path).path == path)
    }

    /// The doc comment is explicit that clamping happens at run time, not on
    /// the model, so the `Stepper` binding stays straightforward.
    @Test("An out-of-range timeout is stored unclamped")
    func outOfRangeTimeoutIsStoredUnclamped() {
        #expect(HookScript(path: "/tmp/hook.sh", timeoutSeconds: 0).timeoutSeconds == 0)
        #expect(HookScript(path: "/tmp/hook.sh", timeoutSeconds: 9999).timeoutSeconds == 9999)
    }

    @Test("Two hooks with identical fields are equal and hash alike")
    func identicalHooksAreEqual() {
        let first = HookScript(path: "/tmp/hook.sh", timeoutSeconds: 12, isEnabled: false)
        let second = HookScript(path: "/tmp/hook.sh", timeoutSeconds: 12, isEnabled: false)

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("Every field participates in equality")
    func everyFieldParticipatesInEquality() {
        let base = HookScript(path: "/tmp/hook.sh", timeoutSeconds: 12, isEnabled: true)

        #expect(base != HookScript(path: "/tmp/other.sh", timeoutSeconds: 12, isEnabled: true))
        #expect(base != HookScript(path: "/tmp/hook.sh", timeoutSeconds: 13, isEnabled: true))
        #expect(base != HookScript(path: "/tmp/hook.sh", timeoutSeconds: 12, isEnabled: false))
    }

    // MARK: - Codable

    @Test("A hook survives a round trip")
    func hookSurvivesARoundTrip() throws {
        let hook = HookScript(path: "/tmp/hook.sh", timeoutSeconds: 12.5, isEnabled: false)

        let decoded = try JSONDecoder().decode(
            HookScript.self,
            from: JSONEncoder().encode(hook)
        )

        #expect(decoded == hook)
    }

    /// The keys are the stored format for both the global hooks and every
    /// profile on disk.
    @Test("The encoded keys are the stored format")
    func encodedKeysAreTheStoredFormat() throws {
        let data = try JSONEncoder().encode(HookScript(path: "/tmp/hook.sh"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(try Set(#require(object).keys) == ["path", "timeoutSeconds", "isEnabled"])
    }

    @Test("A payload missing a field is rejected")
    func payloadMissingAFieldIsRejected() {
        let payload = Data(#"{"path":"/tmp/hook.sh"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HookScript.self, from: payload)
        }
    }

    // MARK: - Profile Automation

    @Test("A default automation container is empty")
    func defaultAutomationContainerIsEmpty() {
        let automation = ProfileAutomation()

        #expect(automation.preHook == nil)
        #expect(automation.postHook == nil)
        #expect(automation.isEmpty)
    }

    @Test("A container holding either hook is not empty")
    func containerHoldingEitherHookIsNotEmpty() {
        let hook = HookScript(path: "/tmp/hook.sh")

        #expect(!ProfileAutomation(preHook: hook).isEmpty)
        #expect(!ProfileAutomation(postHook: hook).isEmpty)
        #expect(!ProfileAutomation(preHook: hook, postHook: hook).isEmpty)
    }

    @Test("An automation container survives a round trip")
    func automationContainerSurvivesARoundTrip() throws {
        let automation = ProfileAutomation(
            preHook: HookScript(path: "/tmp/pre.sh", timeoutSeconds: 3, isEnabled: true),
            postHook: HookScript(path: "/tmp/post.sh", timeoutSeconds: 7, isEnabled: false)
        )

        let decoded = try JSONDecoder().decode(
            ProfileAutomation.self,
            from: JSONEncoder().encode(automation)
        )

        #expect(decoded == automation)
        #expect(decoded.preHook?.path == "/tmp/pre.sh")
        #expect(decoded.postHook?.path == "/tmp/post.sh")
    }

    /// Profiles written before the field existed decode with both hooks nil,
    /// which is the forward compatibility the type's doc comment promises.
    @Test("An empty payload decodes to an empty container")
    func emptyPayloadDecodesToAnEmptyContainer() throws {
        let decoded = try JSONDecoder().decode(ProfileAutomation.self, from: Data("{}".utf8))

        #expect(decoded.isEmpty)
    }

    // MARK: - Phase And Scope

    /// Both raw values reach the hook process as environment values, so they
    /// are an external contract rather than an implementation detail.
    @Test("Phase and scope raw values are pinned")
    func phaseAndScopeRawValuesArePinned() {
        #expect(HookPhase.pre.rawValue == "pre")
        #expect(HookPhase.post.rawValue == "post")
        #expect(HookScope.global.rawValue == "global")
        #expect(HookScope.profile.rawValue == "profile")
    }

    @Test("Phase and scope round-trip through their raw values")
    func phaseAndScopeRoundTripThroughRawValues() {
        #expect(HookPhase(rawValue: "pre") == .pre)
        #expect(HookPhase(rawValue: "post") == .post)
        #expect(HookPhase(rawValue: "during") == nil)
        #expect(HookScope(rawValue: "global") == .global)
        #expect(HookScope(rawValue: "profile") == .profile)
        #expect(HookScope(rawValue: "display") == nil)
    }

    // MARK: - Global Persistence

    /// The two defaults keys are a stored format: users may already have them
    /// written, so renaming the enum case must not move the slot.
    @Test("The global hook defaults keys are pinned")
    func globalHookDefaultsKeysArePinned() {
        #expect(Defaults.Key.globalPreProfileHook.rawValue == "GlobalPreProfileHook")
        #expect(Defaults.Key.globalPostProfileHook.rawValue == "GlobalPostProfileHook")
    }

    @Test("An unconfigured global hook loads as nil", arguments: [HookPhase.pre, .post])
    func unconfiguredGlobalHookLoadsAsNil(_ phase: HookPhase) throws {
        try withScratchDefaults { _ in
            #expect(HookScript.loadGlobal(phase) == nil)
        }
    }

    @Test("A saved global hook loads back", arguments: [HookPhase.pre, .post])
    func savedGlobalHookLoadsBack(_ phase: HookPhase) throws {
        try withScratchDefaults { _ in
            let hook = HookScript(path: "/tmp/hook.sh", timeoutSeconds: 42, isEnabled: false)

            HookScript.saveGlobal(hook, phase: phase)

            #expect(HookScript.loadGlobal(phase) == hook)
        }
    }

    /// The copy-paste hazard: a slip in either accessor would make the two
    /// phases share a slot.
    @Test("The two phases occupy separate slots")
    func phasesOccupySeparateSlots() throws {
        try withScratchDefaults { _ in
            let pre = HookScript(path: "/tmp/pre.sh", timeoutSeconds: 1, isEnabled: true)
            let post = HookScript(path: "/tmp/post.sh", timeoutSeconds: 2, isEnabled: false)

            HookScript.saveGlobal(pre, phase: .pre)
            HookScript.saveGlobal(post, phase: .post)

            #expect(HookScript.loadGlobal(.pre) == pre)
            #expect(HookScript.loadGlobal(.post) == post)
        }
    }

    @Test("Clearing one phase leaves the other standing")
    func clearingOnePhaseLeavesTheOtherStanding() throws {
        try withScratchDefaults { _ in
            let pre = HookScript(path: "/tmp/pre.sh")
            let post = HookScript(path: "/tmp/post.sh")
            HookScript.saveGlobal(pre, phase: .pre)
            HookScript.saveGlobal(post, phase: .post)

            HookScript.saveGlobal(nil, phase: .pre)

            #expect(HookScript.loadGlobal(.pre) == nil)
            #expect(HookScript.loadGlobal(.post) == post)
        }
    }

    @Test("Saving nil removes the stored value rather than writing an empty one")
    func savingNilRemovesTheStoredValue() throws {
        try withScratchDefaults { _ in
            HookScript.saveGlobal(HookScript(path: "/tmp/hook.sh"), phase: .pre)

            HookScript.saveGlobal(nil, phase: .pre)

            #expect(Defaults.data(forKey: .globalPreProfileHook) == nil)
        }
    }

    @Test("Saving over an existing hook replaces it")
    func savingOverAnExistingHookReplacesIt() throws {
        try withScratchDefaults { _ in
            HookScript.saveGlobal(HookScript(path: "/tmp/first.sh"), phase: .post)
            let replacement = HookScript(path: "/tmp/second.sh", timeoutSeconds: 9, isEnabled: false)

            HookScript.saveGlobal(replacement, phase: .post)

            #expect(HookScript.loadGlobal(.post) == replacement)
        }
    }

    /// A hand-edited plist or a payload from a future build must not throw out
    /// of a profile application; the hook is skipped instead.
    @Test("An undecodable payload loads as nil rather than throwing")
    func undecodablePayloadLoadsAsNil() throws {
        try withScratchDefaults { _ in
            Defaults.set(Data("not json".utf8), forKey: .globalPreProfileHook)

            #expect(HookScript.loadGlobal(.pre) == nil)
        }
    }

    @Test("A well-formed payload of the wrong shape loads as nil")
    func wrongShapePayloadLoadsAsNil() throws {
        try withScratchDefaults { _ in
            Defaults.set(Data(#"{"path":"/tmp/hook.sh"}"#.utf8), forKey: .globalPostProfileHook)

            #expect(HookScript.loadGlobal(.post) == nil)
        }
    }

    /// A non-`Data` value in the slot — the shape a `defaults write` produces —
    /// must not trap on the way out.
    @Test("A non-data value in the slot loads as nil")
    func nonDataValueLoadsAsNil() throws {
        try withScratchDefaults { _ in
            Defaults.set("/tmp/hook.sh", forKey: .globalPreProfileHook)

            #expect(HookScript.loadGlobal(.pre) == nil)
        }
    }
}
