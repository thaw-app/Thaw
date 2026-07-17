//
//  AboutSettingsPaneUpdateChannelBindingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
@testable import Thaw
import XCTest

/// Tests for the update-channel `Picker` binding in `AboutSettingsPane`.
///
/// The pane's `updateChannel` view no longer exposes a `Bool`-backed
/// `Toggle`; it now drives a three-way `Picker` via a manually constructed
/// `Binding<UpdateChannel>` that reads and writes
/// `UpdatesManager.updateChannel`:
///
/// ```swift
/// Binding(
///     get: { updatesManager.updateChannel },
///     set: { updatesManager.updateChannel = $0 }
/// )
/// ```
///
/// `AboutSettingsPane` has no view-rendering test harness in this project
/// (no ViewInspector/snapshot infrastructure), so these tests reconstruct
/// that exact binding shape against a real `UpdatesManager` to verify the
/// wiring the diff introduced, without needing to render the SwiftUI body.
@MainActor
final class AboutSettingsPaneUpdateChannelBindingTests: XCTestCase {
    private let channelKey = "UpdateChannel"
    private let legacyKey = "AllowsBetaUpdates"

    private var originalChannelValue: Any?
    private var originalLegacyValue: Any?
    private var updatesManager: UpdatesManager!

    override func setUp() {
        super.setUp()
        originalChannelValue = UserDefaults.standard.object(forKey: channelKey)
        originalLegacyValue = UserDefaults.standard.object(forKey: legacyKey)
        UserDefaults.standard.removeObject(forKey: channelKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        updatesManager = UpdatesManager()
    }

    override func tearDown() {
        updatesManager = nil
        UserDefaults.standard.removeObject(forKey: channelKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        if let originalChannelValue {
            UserDefaults.standard.set(originalChannelValue, forKey: channelKey)
        }
        if let originalLegacyValue {
            UserDefaults.standard.set(originalLegacyValue, forKey: legacyKey)
        }
        super.tearDown()
    }

    /// Builds the same `Binding<UpdateChannel>` shape used by the
    /// `updateChannel` Picker in `AboutSettingsPane`.
    private func makePickerBinding(for updatesManager: UpdatesManager) -> Binding<UpdateChannel> {
        Binding(
            get: { updatesManager.updateChannel },
            set: { updatesManager.updateChannel = $0 }
        )
    }

    func testBindingGetterReflectsTheManagersCurrentChannel() {
        updatesManager.updateChannel = .beta
        let binding = makePickerBinding(for: updatesManager)

        XCTAssertEqual(binding.wrappedValue, .beta)
    }

    func testBindingSetterUpdatesTheManagersChannel() {
        let binding = makePickerBinding(for: updatesManager)

        binding.wrappedValue = .alpha

        XCTAssertEqual(updatesManager.updateChannel, .alpha)
        XCTAssertEqual(UserDefaults.standard.string(forKey: channelKey), "alpha")
    }

    func testBindingRoundTripsThroughEveryPickerOption() {
        // Mirrors the three `Text(...).tag(...)` options wired up in the
        // segmented Picker: Stable, Development (beta), Nightly (alpha).
        let binding = makePickerBinding(for: updatesManager)

        for channel in [UpdateChannel.stable, .beta, .alpha] {
            binding.wrappedValue = channel
            XCTAssertEqual(binding.wrappedValue, channel)
            XCTAssertEqual(updatesManager.updateChannel, channel)
        }
    }

    func testBindingIsLiveRatherThanASnapshot() {
        let binding = makePickerBinding(for: updatesManager)

        // Mutating the manager directly (as another observer might) should
        // be visible through the binding without recreating it.
        updatesManager.updateChannel = .stable
        XCTAssertEqual(binding.wrappedValue, .stable)

        updatesManager.updateChannel = .beta
        XCTAssertEqual(binding.wrappedValue, .beta)
    }

    // MARK: - View construction smoke test

    func testAboutSettingsPaneCanBeInitializedWithAnUpdatesManager() {
        // `updatesSection` (which hosts the channel Picker) is no longer
        // hidden behind `#unavailable(macOS 27)`; the pane must at minimum
        // accept an `UpdatesManager` and be constructible on every OS this
        // test runs on.
        let pane = AboutSettingsPane(updatesManager: updatesManager)

        XCTAssertNotNil(pane)
    }
}