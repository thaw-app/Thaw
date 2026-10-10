//
//  CaptureInspectorSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

/// Shows the untreated frames Thaw captures, so granting Screen Recording comes
/// with the ability to confirm the scope of what is observed.
///
/// Capture is manual rather than continuous: an inspector that reads the screen
/// on a timer would make the privacy story worse, not better. Nothing here is
/// written to disk.
///
/// The copy has to state the scope exactly: Thaw reads a band across the top of
/// the display, which really does contain the frontmost app's menus and the
/// wallpaper behind the bar. Naming that is the honest half of the claim.
struct CaptureInspectorSection: View {
    /// One item's frame paired with where it lands inside a capture.
    private struct InspectedItem: Identifiable {
        let id: String
        let name: String
        let bounds: CGRect
    }

    @Environment(AppState.self) var appState

    @State private var inspection: ScreenCapture.CaptureInspection?
    @State private var items = [InspectedItem]()
    @State private var concealedItemCount = 0
    @State private var isCapturing = false
    @State private var showsCropRegions = true
    @State private var selectedDisplayID: CGDirectDisplayID?

    private var screens: [NSScreen] {
        NSScreen.screens
    }

    private var activeDisplayID: CGDirectDisplayID? {
        selectedDisplayID ?? screens.first?.displayID
    }

    private var activeScreen: NSScreen? {
        screens.first { $0.displayID == activeDisplayID }
    }

    var body: some View {
        ThawSection("What Thaw sees") {
            scopeDescription
            if screens.count > 1 {
                displayPicker
            }
            controls
            if let inspection {
                results(for: inspection)
            }
        }
    }

    // MARK: Controls

    /// States the region read, derived from the same function the capture
    /// configures itself with so the stated scope cannot drift from the taken
    /// one.
    @ViewBuilder
    private var scopeDescription: some View {
        if ScreenCapture.hasCachedScreenRecordingPermission {
            Text(scopeText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label {
                Text("Thaw is capturing nothing. Screen Recording permission has not been granted.")
            } icon: {
                Image(systemName: "eye.slash")
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What Thaw reads on this system, stated before anything is captured.
    private var scopeText: String {
        // The band's size is read from the same function the capture
        // configures itself with, so the stated scope cannot drift from the
        // taken one.
        let frame = activeScreen.map {
            ScreenCapture.inspectableStripFrame(
                displayFrame: $0.frame,
                menuBarHeight: ScreenCapture.liveMenuBarHeight(for: $0.displayID)
            )
        }
        guard let frame else {
            return String(localized: "Thaw reads a band at the top of the display. Nothing else on screen is captured.")
        }
        return String(
            localized: "Thaw reads a \(Int(frame.width)) × \(Int(frame.height)) pt band at the top of the display. Nothing else on screen is captured."
        )
    }

    private var displayPicker: some View {
        ThawPicker("Display", selection: displayBinding) {
            ForEach(screens, id: \.displayID) { screen in
                Text(screen.localizedName).tag(screen.displayID)
            }
        }
    }

    private var displayBinding: Binding<CGDirectDisplayID> {
        Binding(
            get: { activeDisplayID ?? 0 },
            set: { newValue in
                selectedDisplayID = newValue
                // A frame from the previous display would silently misattribute
                // what the user is looking at.
                inspection = nil
                items = []
            }
        )
    }

    private var controls: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if isCapturing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Capture Now") {
                    Task { await capture() }
                }
                .buttonStyle(.settingsGlass)
                .disabled(isCapturing || activeDisplayID == nil)
            }
        } label: {
            Toggle("Show crop regions", isOn: $showsCropRegions)
        }
        .annotation {
            Text(
                "Crop regions are the exact pixels Thaw reads for each menu bar item. "
                    + "Frames are shown once and never saved to disk."
            )
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(for inspection: ScreenCapture.CaptureInspection) -> some View {
        if inspection.isEmpty {
            SettingsWarningPill(
                title: "Nothing was captured",
                message: "Screen Recording may be off for \(Constants.displayName).",
                systemImage: "eye.slash",
                actionTitle: "Grant Access",
                action: { appState.permissions.screenRecording.performRequest() }
            )
        } else {
            // Only the primary frame is shown. inspection.hosting is a real
            // capture, but it is an off-screen compositing surface that looks
            // like nothing the user can recognise, and showing it next to their
            // own menu bar teaches confusion rather than scope.
            if let primary = inspection.primary {
                frame(
                    primary,
                    title: "Your menu bar",
                    // Naming the incidental contents is the honest half of the
                    // claim: this really is a slice of the user's screen.
                    subtitle: "The band Thaw reads, exactly as captured. That includes the "
                        + "frontmost app's menus and the wallpaper behind the bar."
                )
            }
            concealedItemsNote
            Text(inspection.capturedAt.formatted(date: .omitted, time: .standard))
                .font(ThawType.metric)
                .foregroundStyle(ThawInk.supporting)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Accounts for the items that have no crop region in the frame above.
    ///
    /// A stated absence verifies better than an unexplained one: without this,
    /// hidden items missing from the capture look like the inspector failing to
    /// show them rather than Thaw genuinely not reading them.
    private var concealedItemsNote: some View {
        VStack(alignment: .leading, spacing: 2) {
            if concealedItemCount > 0 {
                // Explicit forms: automatic agreement inflected the verb but not
                // the noun, and read "9 hidden item are not captured".
                Text(concealedItemCount == 1
                    ? "1 hidden item is not captured"
                    : "\(concealedItemCount) hidden items are not captured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(concealedItemsExplanation)
                .font(.caption)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var concealedItemsExplanation: String {
        // The conceal mechanism is a visibility restriction, so the system
        // does not render the item into any surface at all.
        return String(
            localized: "While an item is hidden, macOS does not draw it anywhere, so Thaw cannot see it either. Thaw captures a hidden item's icon only during the brief moment it reveals the item to fetch one."
        )
    }

    private func frame(
        _ capture: ScreenCapture.MenuBarHostingCapture,
        title: LocalizedStringKey,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ThawType.heading)
            CaptureFrameView(
                capture: capture,
                regions: showsCropRegions ? cropRegions(in: capture) : []
            )
            Text("\(capture.image.width) × \(capture.image.height) px at \(capture.scale, format: .number)×")
                .font(.caption)
                .foregroundStyle(ThawInk.supporting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .annotation { Text(subtitle) }
    }

    /// The crop rects Thaw would take from this frame.
    ///
    /// Resolved through the same cropMapping the capture pipeline crops with,
    /// so an overlay can never show a region the pipeline would not read.
    private func cropRegions(
        in capture: ScreenCapture.MenuBarHostingCapture
    ) -> [CaptureFrameView.Region] {
        items.compactMap { item in
            guard let mapping = capture.cropMapping(forItemBounds: item.bounds),
                  !mapping.clamped.isNull, !mapping.clamped.isEmpty
            else {
                return nil
            }
            return CaptureFrameView.Region(
                id: item.id,
                name: item.name,
                rect: mapping.clamped,
                isComplete: mapping.isComplete
            )
        }
    }

    // MARK: Capture

    private func capture() async {
        guard let displayID = activeDisplayID else { return }
        isCapturing = true
        defer { isCapturing = false }

        let liveItems = await MenuBarItem.getMenuBarItems(
            on: displayID,
            option: [.onScreen, .activeSpace]
        ).filter { !$0.bounds.isNull && !$0.bounds.isEmpty }

        // Settings is not one of the surfaces that keeps capture open, so
        // without a ticket the capture gate refuses and the inspector reports
        // that nothing was captured. The user asked for this one capture.
        let captured: ScreenCapture.CaptureInspection = await ScreenCapture.withOneshotCaptureTicket {
            await ScreenCapture.inspect(displayID: displayID)
        }

        inspection = captured
        items = liveItems.map { item in
            InspectedItem(
                id: item.uniqueIdentifier,
                name: item.displayName,
                bounds: item.bounds
            )
        }
        concealedItemCount = countConcealedItems()
    }

    /// How many items Thaw is currently keeping out of the bar.
    ///
    /// Counted from Thaw's own cache rather than from the capture, because a
    /// concealed item is precisely one the capture cannot account for. Sections
    /// the user has temporarily revealed are excluded, their items are on
    /// screen and do get crop regions.
    private func countConcealedItems() -> Int {
        let manager = appState.menuBarManager
        return [MenuBarSection.Name.hidden, .alwaysHidden].reduce(0) { total, name in
            guard let section = manager.section(withName: name), section.isHidden else {
                return total
            }
            return total + appState.itemManager.itemCache[name].count
        }
    }
}

// MARK: - CaptureFrameView

/// Draws one captured frame at its natural aspect ratio, with the crop regions
/// overlaid in the image's own pixel space.
private struct CaptureFrameView: View {
    struct Region: Identifiable {
        let id: String
        let name: String
        /// The region in image pixels.
        let rect: CGRect
        /// Whether the region survived clamping intact. An incomplete region is
        /// one the pipeline refuses, and is drawn differently so the inspector
        /// does not imply Thaw reads pixels it discards.
        let isComplete: Bool
    }

    let capture: ScreenCapture.MenuBarHostingCapture
    let regions: [Region]

    private var pixelSize: CGSize {
        CGSize(width: capture.image.width, height: capture.image.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = pixelSize.width > 0 ? proxy.size.width / pixelSize.width : 0
            ZStack(alignment: .topLeading) {
                Image(decorative: capture.image, scale: 1)
                    .resizable()
                    .frame(width: proxy.size.width, height: pixelSize.height * scale)
                ForEach(regions) { region in
                    // Dashed, not just orange: hue alone cannot carry the
                    // refused-region state under Differentiate Without Color.
                    Rectangle()
                        .strokeBorder(
                            region.isComplete ? Color.accentColor : Color.orange,
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: region.isComplete ? [] : [3, 2]
                            )
                        )
                        .frame(
                            width: region.rect.width * scale,
                            height: region.rect.height * scale
                        )
                        .offset(
                            x: region.rect.minX * scale,
                            y: region.rect.minY * scale
                        )
                        .help(region.name)
                        .accessibilityElement()
                        .accessibilityLabel(region.name)
                        .accessibilityValue(region.isComplete ? "Complete" : "Incomplete")
                }
            }
        }
        .aspectRatio(
            pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 1,
            contentMode: .fit
        )
        // A checkerboard would be noise; a plain backing makes a transparent
        // composite legible without implying its background is a colour.
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .frame(maxWidth: .infinity)
    }
}
