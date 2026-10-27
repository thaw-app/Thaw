//
//  ProfileImportPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Profile import policy")
struct ProfileImportPolicyTests {
    private static func contentWithHooks() -> ProfileContent {
        var content = makeTestProfileContent()
        content.automation = ProfileAutomation(
            preHook: HookScript(path: "/tmp/pre.sh"),
            postHook: HookScript(path: "/tmp/post.scpt")
        )
        content.confirmSpacingRelaunch = false
        return content
    }

    private static func gradient(stopCount: Int) -> IceGradient {
        IceGradient(stops: (0 ..< stopCount).map { index in
            .white(location: CGFloat(index) / CGFloat(max(stopCount - 1, 1)))
        })
    }

    @Test("Imported hooks arrive switched off, with their paths kept")
    func hooksArriveOff() {
        let sanitized = ProfileImportPolicy.sanitized(Self.contentWithHooks())

        #expect(sanitized.automation?.preHook?.isEnabled == false)
        #expect(sanitized.automation?.postHook?.isEnabled == false)
        #expect(sanitized.automation?.preHook?.path == "/tmp/pre.sh")
        #expect(sanitized.automation?.postHook?.path == "/tmp/post.scpt")
    }

    @Test("An imported profile can't turn off the relaunch confirmation")
    func relaunchConfirmationStaysOn() {
        #expect(ProfileImportPolicy.sanitized(Self.contentWithHooks()).confirmSpacingRelaunch)
    }

    @Test("Imported gradients keep at most the stops Thaw draws")
    func gradientsAreCapped() {
        var content = makeTestProfileContent()
        content.appearanceConfiguration.lightModeConfiguration.tintGradient = Self.gradient(stopCount: 500)
        content.appearanceConfiguration.darkModeConfiguration.backgroundGradient = Self.gradient(stopCount: 500)
        content.appearanceConfiguration.staticConfiguration.tintGradient = Self.gradient(stopCount: 3)
        content.appearanceConfiguration.thawBarAppearance.tintGradient = Self.gradient(stopCount: 500)

        let appearance = ProfileImportPolicy.sanitized(content).appearanceConfiguration

        #expect(appearance.lightModeConfiguration.tintGradient.stops.count == IceGradient.maxImportedStops)
        #expect(appearance.darkModeConfiguration.backgroundGradient.stops.count == IceGradient.maxImportedStops)
        #expect(appearance.staticConfiguration.tintGradient.stops.count == 3)
        #expect(appearance.thawBarAppearance.tintGradient.stops.count == IceGradient.maxImportedStops)
    }

    @Test("A capped gradient keeps its first and last stops")
    func cappedGradientKeepsEnds() throws {
        var content = makeTestProfileContent()
        var stops = Self.gradient(stopCount: 500).stops
        stops[stops.count - 1] = .black(location: 1)
        content.appearanceConfiguration.lightModeConfiguration.tintGradient = IceGradient(stops: stops)

        let capped = ProfileImportPolicy.sanitized(content).appearanceConfiguration.lightModeConfiguration.tintGradient.stops

        #expect(capped.count == IceGradient.maxImportedStops)
        #expect(capped.first == stops.first)
        let last = try #require(capped.last)
        #expect(last.location == 1)
        #expect(last.color == CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    }

    @Test("Sampling picks evenly across the whole range")
    func samplingIsEven() {
        #expect(ProfileImportPolicy.sampled(Array(0 ..< 10), cap: 4) == [0, 3, 6, 9])
        #expect(ProfileImportPolicy.sampled(Array(0 ..< 3), cap: 4) == [0, 1, 2])
        #expect(ProfileImportPolicy.sampled(Array(0 ..< 5), cap: 1) == [0])
        #expect(ProfileImportPolicy.sampled(Array(0 ..< 5), cap: 0).isEmpty)
    }

    @Test("A file with too many profiles is refused")
    func tooManyProfiles() {
        let entry = ProfileExportEntry(profile: makeProfile(), associatedDisplayUUID: nil, associatedDisplayName: nil)
        let bundle = ProfileExportBundle(entries: Array(repeating: entry, count: ProfileImportPolicy.maxEntries + 1))

        #expect(throws: ProfileImportPolicy.ImportError.tooManyProfiles(ProfileImportPolicy.maxEntries + 1)) {
            try ProfileImportPolicy.validate(bundle)
        }
        #expect(ProfileImportPolicy.ImportError.tooManyProfiles(101).errorDescription != nil)
    }

    @Test("A file at the limit is accepted")
    func profilesAtLimit() throws {
        let entry = ProfileExportEntry(profile: makeProfile(), associatedDisplayUUID: nil, associatedDisplayName: nil)

        try ProfileImportPolicy.validate(
            ProfileExportBundle(entries: Array(repeating: entry, count: ProfileImportPolicy.maxEntries))
        )
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileImportPolicyTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @MainActor
    @Test("Importing applies the policy and keeps each association unique")
    func importAppliesPolicy() throws {
        try withTemporaryDirectory { tmp in
            try seedManifest(with: [], into: tmp)
            let manager = ProfileManager(profilesDirectory: tmp)
            let first = Profile(name: "First", content: Self.contentWithHooks())
            let second = Profile(name: "Second", content: makeTestProfileContent())
            let bundle = ProfileExportBundle(entries: [
                ProfileExportEntry(profile: first, associatedDisplayUUID: "UUID-A", associatedDisplayName: "A"),
                ProfileExportEntry(profile: second, associatedDisplayUUID: "UUID-A", associatedDisplayName: "A"),
            ])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let url = tmp.appendingPathComponent("bundle.json")
            try encoder.encode(bundle).write(to: url, options: .atomic)

            try manager.importProfile(from: url)

            #expect(manager.profiles.count == 2)
            #expect(manager.profiles.filter { $0.associatedDisplayUUID == "UUID-A" }.map(\.name) == ["Second"])
            let importedFirst = try #require(manager.profiles.first { $0.name == "First" })
            let automation = manager.hooks(forProfileID: importedFirst.id)
            #expect(automation.preHook?.isEnabled == false)
            #expect(automation.postHook?.isEnabled == false)
        }
    }
}
