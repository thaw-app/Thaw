//
//  SettingsSectionRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// Sections of the General, Tools, Visibility and Advanced pages drawn off screen against an
/// AppState that is never started. Anything that would open a panel, Finder or System Settings,
/// relaunch Thaw or read the live recovery records goes through a stand-in instead.
@MainActor
@Suite("Settings section rendering", .serialized, .scratchDefaults)
struct SettingsSectionRenderTests {
    private static let size = CGSize(width: 760, height: 1600)

    private typealias Page = OffscreenRender<AnyView>

    private func page(_ view: some View, appState: AppState) -> Page {
        OffscreenRender(
            AnyView(
                view
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
    }

    /// Waits until the page shows text, and returns it.
    private func shownTexts(_ page: Page, containing text: String) async -> [String] {
        await page.settle { page.texts().contains { $0.contains(text) } }
        return page.texts()
    }

    // MARK: General

    @Test("Both placement warnings say why the icon is missing")
    func placementWarnings() async {
        let appState = AppState()
        let page = page(
            VStack {
                ThawPlacementWarning(block: .deniedBySystem)
                ThawPlacementWarning(block: .unknown)
            },
            appState: appState
        )
        let texts = await shownTexts(page, containing: "isn't in the menu bar")
        #expect(texts.contains { $0.contains("isn't allowing \(Constants.displayName)") })
        #expect(texts.contains { $0.contains("icon isn't in the menu bar") })
    }

    @Test("The hide-again picker draws for each kind of choice")
    func rehideChoice() async {
        let appState = AppState()
        let visibility = appState.settings.visibility
        let page = page(ThawForm { RehideChoiceRow(settings: visibility) }, appState: appState)
        visibility.autoRehide = false
        await page.settle { page.elements(role: .popUpButton, label: "Hide items again").count == 1 }
        #expect(page.elements(role: .popUpButton, label: "Hide items again").count == 1)
        for strategy in [RehideStrategy.smart, .timed, .focusedApp] {
            visibility.autoRehide = true
            visibility.rehideStrategy = strategy
            await page.settle { page.elements(role: .popUpButton, label: "Hide items again").count == 1 }
            #expect(page.elements(role: .popUpButton, label: "Hide items again").count == 1)
        }
    }

    @Test("A custom icon shows its appearance switch, and a built-in one hides it")
    func thawIconPicker() async throws {
        let appState = AppState()
        let general = appState.settings.general
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        let data = try #require(image.tiffRepresentation)
        let custom = ControlItemImageSet(name: .custom, image: .data(data))
        general.lastCustomThawIcon = custom
        general.thawIcon = custom
        let page = page(ThawForm { ThawIconPicker(settings: general) }, appState: appState)
        let texts = await shownTexts(page, containing: "dynamic appearance")
        #expect(texts.contains { $0.contains("Custom icon uses dynamic appearance") })

        let builtIn = try #require(ControlItemImageSet.userSelectableThawIcons.first)
        general.thawIcon = builtIn
        await page.settle { !page.texts().contains { $0.contains("dynamic appearance") } }
        #expect(!page.texts().contains { $0.contains("dynamic appearance") }, "a built-in icon has no appearance switch")
    }

    // MARK: Tools

    /// Stand-ins for everything the diagnostics buttons reach, recording what they were asked.
    private final class DiagnosticsRecorder {
        var destination: URL?
        var suggestedNames: [String] = []
        var opened: [URL] = []
        var revealed: [URL] = []
        var exported: [URL] = []
        var savedLists: [URL] = []

        @MainActor var actions: DiagnosticFilesSection.Actions {
            DiagnosticFilesSection.Actions(
                chooseDestination: { name, _ in
                    self.suggestedNames.append(name)
                    return self.destination
                },
                open: { self.opened.append($0) },
                reveal: { self.revealed.append($0) },
                exportDiagnostics: { self.exported.append($0) },
                saveItemList: { self.savedLists.append($0) }
            )
        }
    }

    @Test("Diagnostics buttons open the log folder, export, save the item list, and show samples once one is written")
    func diagnosticFiles() async throws {
        let appState = AppState()
        let recorder = DiagnosticsRecorder()
        let page = page(ThawForm { DiagnosticFilesSection(actions: recorder.actions) }, appState: appState)
        await page.settle { !page.elements(role: .button, label: "Export Logs").isEmpty }

        try page.press("Show Log Files in Finder")
        #expect(recorder.opened == [DiagnosticLogger.shared.logDirectory])

        try page.press("Export Logs")
        try page.press("Save Item List")
        #expect(recorder.suggestedNames == ["\(Constants.displayName) Diagnostics.zip", "\(Constants.displayName) Items.json"])
        #expect(recorder.exported.isEmpty && recorder.savedLists.isEmpty, "a cancelled chooser writes nothing")

        let zip = URL(fileURLWithPath: "/tmp/diagnostics-test.zip")
        recorder.destination = zip
        try page.press("Export Logs")
        await page.settle { recorder.revealed == [zip] }
        #expect(recorder.exported == [zip])
        #expect(recorder.revealed == [zip])

        let list = URL(fileURLWithPath: "/tmp/items-test.json")
        recorder.destination = list
        try page.press("Save Item List")
        #expect(recorder.savedLists == [list])
        #expect(recorder.revealed == [zip, list])

        NotificationCenter.default.post(name: CaptureDiagnostics.didWriteSample, object: nil)
        await page.settle {
            (try? page.press("Show Capture Samples")) != nil && recorder.opened.contains(CaptureDiagnostics.sampleDirectory)
        }
        #expect(recorder.opened.last == CaptureDiagnostics.sampleDirectory)
    }

    /// Records the recovery model reads, so the view never touches the live ones.
    private final class RecoveryRecords {
        struct Unreadable: Error {}

        var disabled = ["com.example.manual"]
        var recorded: Set<String> = ["com.example.recorded"]
        var isUnreadable = false
        var conflictsLeft = 0
        var inspections = 0
        var restored: Set<String>?
        var waitTime = Duration.milliseconds(200)

        @MainActor func model(bypass: Bool = false) -> NativeVisibilityRecoveryModel {
            NativeVisibilityRecoveryModel(environment: .init(
                conflictingApplications: {
                    guard self.conflictsLeft > 0 else { return [] }
                    self.conflictsLeft -= 1
                    return ["com.example.other"]
                },
                disableNativeHiding: { /* Nothing live to switch off. */ },
                requestAccess: { true },
                inspect: {
                    self.inspections += 1
                    if self.isUnreadable {
                        throw Unreadable()
                    }
                    return (self.disabled, self.recorded)
                },
                restore: {
                    self.restored = $0
                    return $0.count
                },
                displayName: { "App \($0)" },
                wait: { try await Task.sleep(for: self.waitTime) },
                isUnreadableRecord: { $0 is Unreadable },
                setAsideUnreadableRecords: {
                    self.isUnreadable = false
                    return [URL(fileURLWithPath: "/tmp/RecoveryRecord.unreadable.json")]
                },
                bypassRecovery: bypass ? { [URL(fileURLWithPath: "/tmp/RecoverySkipped.json")] } : nil
            ))
        }
    }

    @Test("Recovery lists recorded and other apps, takes a selection, and checks again")
    func recoveryLists() async throws {
        let appState = AppState()
        let records = RecoveryRecords()
        records.conflictsLeft = 1
        let model = records.model(bypass: true)
        let page = page(NativeVisibilityRecoveryView(model: model), appState: appState)

        let busy = await shownTexts(page, containing: "Checking menu bar visibility")
        #expect(busy.contains { $0.contains("Checking menu bar visibility") }, "another manager running keeps it busy")

        let texts = await shownTexts(page, containing: "Other disabled apps")
        #expect(texts.contains { $0.contains("Recorded changes to restore") })
        #expect(texts.contains { $0.contains("com.example.recorded") })
        #expect(texts.contains { $0.contains("App com.example.manual") })
        #expect(!page.elements(role: .button, label: "Skip Recovery…").isEmpty, "the runtime can skip recovery")

        let checkBox = try #require(page.elements().first { OffscreenAccessibility.role(of: $0) == .checkBox })
        OffscreenAccessibility.press(checkBox)
        await page.settle { model.selectedBundleIDs == ["com.example.manual"] }
        #expect(model.selectedBundleIDs == ["com.example.manual"])
        OffscreenAccessibility.press(checkBox)
        await page.settle { model.selectedBundleIDs.isEmpty }
        #expect(model.selectedBundleIDs.isEmpty)

        let before = records.inspections
        try page.press("Check Again")
        await page.settle { records.inspections > before }
        #expect(records.inspections > before)

        model.selectedBundleIDs = ["com.example.manual"]
        await model.restore()
        let done = await shownTexts(page, containing: "Visibility settings were saved")
        #expect(done.contains { $0.contains("Visibility settings were saved") })
        #expect(records.restored == ["com.example.manual"])
    }

    @Test("Recovery explains an unreadable record, and setting it aside shows where it went")
    func recoveryUnreadableRecord() async throws {
        let appState = AppState()
        let records = RecoveryRecords()
        records.isUnreadable = true
        records.disabled = []
        records.recorded = []
        let model = records.model()
        let page = page(NativeVisibilityRecoveryView(model: model), appState: appState)

        let texts = await shownTexts(page, containing: "can't read its record")
        #expect(texts.contains { $0.contains("can't read its record") })
        #expect(!page.elements(role: .button, label: "Set Aside Record…").isEmpty)
        #expect(page.elements(role: .button, label: "Skip Recovery…").isEmpty, "this runtime can't skip recovery")

        model.setAsideUnreadableRecords()
        let after = await shownTexts(page, containing: "previous recovery records are kept")
        #expect(after.contains { $0.contains("RecoveryRecord.unreadable.json") })
        #expect(after.contains { $0.contains("No other apps are available for recovery") })
    }

    @Test("Recovery shows a failure and how to recover from it")
    func recoveryFailure() async {
        let appState = AppState()
        let records = RecoveryRecords()
        records.conflictsLeft = .max
        records.waitTime = .milliseconds(1)
        let model = records.model()
        let page = page(NativeVisibilityRecoveryView(model: model), appState: appState)
        let texts = await shownTexts(page, containing: "Recovery records are kept")
        #expect(texts.contains { $0.contains("Recovery records are kept until the visibility settings are verified") })
    }

    // MARK: Advanced

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("The alert reveal list asks for a hidden item first when there is none")
    func alertRevealListEmpty() async {
        let appState = AppState()
        let page = page(ThawForm { AlertRevealItemList() }, appState: appState)
        let texts = await shownTexts(page, containing: "Hide an item first")
        #expect(texts.contains { $0.contains("Hide an item first") })
    }

    @Test("The alert reveal list offers every hidden item and an absent opt-in, and its switches save")
    func alertRevealListRows() async throws {
        let appState = AppState()
        let hidden = Self.item("Hidden", x: 10)
        let alwaysHidden = Self.item("Always", x: 40)
        appState.itemManager.itemCache[.hidden] = [hidden]
        appState.itemManager.itemCache[.alwaysHidden] = [alwaysHidden]
        MenuBarItemAlertReveals.setEnabled(true, for: "com.example.gone:Gone")
        let page = page(ThawForm { AlertRevealItemList() }, appState: appState)

        let texts = await shownTexts(page, containing: "not currently in the menu bar")
        #expect(texts.contains { $0.contains("com.example.gone:Gone (not currently in the menu bar)") })
        await page.settle { page.elements().count { OffscreenAccessibility.role(of: $0) == .checkBox } == 3 }
        let checkBoxes = page.elements().filter { OffscreenAccessibility.role(of: $0) == .checkBox }
        #expect(checkBoxes.count == 3, "two hidden items and the absent opt-in")

        // Present items come first, so the first switch belongs to one of the two hidden items.
        let present: Set = [hidden.tag.tagIdentifier, alwaysHidden.tag.tagIdentifier]
        #expect(MenuBarItemAlertReveals.identifiers() == ["com.example.gone:Gone"])
        OffscreenAccessibility.press(try #require(checkBoxes.first))
        await page.settle { MenuBarItemAlertReveals.identifiers().count == 2 }
        let enabled = MenuBarItemAlertReveals.identifiers().subtracting(["com.example.gone:Gone"])
        #expect(enabled.count == 1 && enabled.isSubset(of: present), "the switch saves its item")
        OffscreenAccessibility.press(try #require(checkBoxes.first))
        await page.settle { MenuBarItemAlertReveals.identifiers().count == 1 }
        #expect(MenuBarItemAlertReveals.identifiers() == ["com.example.gone:Gone"], "turning it off removes it again")
    }
}
