//
//  FeatureTipsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Feature tips configure once and never reach TipKit in tests")
struct FeatureTipsTests {
    @MainActor
    private final class Recorder {
        var setups = [FeatureTips.Setup]()
        var retirements = 0
        var failure: (any Error)?
    }

    private struct ConfigureFailure: Error {}

    private static let appSupport = URL(filePath: "/Users/someone/Library/Application Support", directoryHint: .isDirectory)

    private func tips(_ recorder: Recorder) -> FeatureTips {
        FeatureTips(
            apply: { setup in
                if let failure = recorder.failure { throw failure }
                recorder.setups.append(setup)
            },
            retireMultiSelectTip: { recorder.retirements += 1 }
        )
    }

    private func configure(_ tips: FeatureTips, environment: [String: String] = [:], previousVersion: String? = nil) {
        tips.configure(
            environment: environment,
            applicationSupport: Self.appSupport,
            bundleIdentifier: "com.stonerl.Thaw.debug",
            previousVersion: previousVersion
        )
    }

    @Test("Upgrades count only from a recorded version older than the one that brought multi-select on its line")
    func upgradeDetection() {
        #expect(LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-alpha.9"))
        #expect(LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-alpha.1"))
        #expect(LayoutMultiSelectTip.isUpgrade(previousVersion: "2.4.1"))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-alpha.10"))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-alpha.11"))
        #expect(LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-beta.1"))
        #expect(LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-beta.2"))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-beta.3"))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0-beta.4"))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: "3.0.0"))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: nil))
        #expect(!LayoutMultiSelectTip.isUpgrade(previousVersion: ""))
    }

    @Test("The datastore sits in the build's own Application Support folder")
    func datastoreLocation() {
        let url = FeatureTips.datastoreURL(applicationSupport: Self.appSupport, bundleIdentifier: "com.stonerl.Thaw.debug")
        #expect(url.path(percentEncoded: false).hasSuffix("/Application Support/com.stonerl.Thaw.debug/Tips/"))
    }

    @Test("Tips stay off under the test runner and in previews")
    func disabledUnderTestsAndPreviews() {
        #expect(FeatureTips.isEnabled(environment: [:]))
        #expect(!FeatureTips.isEnabled(environment: ["XCTestConfigurationFilePath": "/x"]))
        #expect(!FeatureTips.isEnabled(environment: ["XCTestSessionIdentifier": "1"]))
        #expect(!FeatureTips.isEnabled(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        #expect(!FeatureTips.isEnabled(environment: ProcessInfo.processInfo.environment))
        #expect(!FeatureTips.shared.isConfigured)
    }

    @Test("Configuration happens once and carries the upgrade")
    func configuresOnce() {
        let recorder = Recorder()
        let tips = tips(recorder)
        configure(tips, previousVersion: "3.0.0-alpha.9")
        configure(tips, previousVersion: "3.0.0-alpha.10")

        #expect(tips.isConfigured)
        #expect(recorder.setups == [
            FeatureTips.Setup(
                datastoreURL: FeatureTips.datastoreURL(applicationSupport: Self.appSupport, bundleIdentifier: "com.stonerl.Thaw.debug"),
                isMultiSelectUpgrade: true
            ),
        ])
    }

    @Test("A failed configuration leaves tips off and can be retried")
    func failureLeavesTipsOff() {
        let recorder = Recorder()
        recorder.failure = ConfigureFailure()
        let tips = tips(recorder)
        configure(tips)
        tips.noteMultiSelect()
        #expect(!tips.isConfigured)
        #expect(recorder.retirements == 0)

        recorder.failure = nil
        configure(tips)
        #expect(tips.isConfigured)
        #expect(recorder.setups.map(\.isMultiSelectUpgrade) == [false])
    }

    @Test("Under the test runner nothing is configured and multi-select retires nothing")
    func testRunnerSkipsTipKit() {
        let recorder = Recorder()
        let tips = tips(recorder)
        configure(tips, environment: ["XCTestConfigurationFilePath": "/x"], previousVersion: "3.0.0-alpha.9")
        tips.noteMultiSelect()
        #expect(recorder.setups.isEmpty)
        #expect(recorder.retirements == 0)
    }

    @Test("A multi-selection retires the tip once TipKit is configured")
    func multiSelectRetiresTip() {
        let recorder = Recorder()
        let tips = tips(recorder)
        configure(tips)
        tips.noteMultiSelect()
        #expect(recorder.retirements == 1)
    }

    @Test("The tip says what it announces, has no display limit and waits only for an upgrade")
    func tipContent() {
        let tip = LayoutMultiSelectTip()
        #expect(String(localized: LayoutMultiSelectTip.titleResource) == "New: select several items")
        #expect(String(localized: LayoutMultiSelectTip.messageResource).contains("right-click"))
        #expect(tip.message != nil)
        #expect(tip.image != nil)
        #expect(tip.options.isEmpty)
        #expect(tip.rules.count == 1)
        _ = tip.title
    }
}
