//
//  ImageConditionEditor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

// MARK: - ImageConditionEditor

/// The "Watched item" picker shared by the two icon-watching editors. One copy
/// keeps a stored-but-absent item reading the same whichever condition chose it.
private struct WatchedItemPicker: View {
    let selection: Binding<String>
    let watchedID: String
    let itemOptions: [TriggerItemOption]

    var body: some View {
        IcePicker("Watched item", selection: selection) {
            if watchedID.isEmpty {
                Text("Choose an item…").tag("")
            } else if !itemOptions.contains(where: { $0.id == watchedID }) {
                Text("\(watchedID) (not present)").tag(watchedID)
            }
            ForEach(itemOptions, id: \.id) { option in
                Text(option.name).tag(option.id)
            }
        }
    }
}

/// Picks the item whose icon is watched for attention-seeking behaviour.
/// Unlike ``ImageConditionEditor`` there is no reference to capture: the
/// verdict comes from how the icon moves over time, not from a comparison
/// against a stored snapshot.
struct AttentionConditionEditor: View {
    @Binding var condition: TriggerCondition
    let itemOptions: [TriggerItemOption]

    private var watchedID: String {
        condition.watchedItemIdentifier ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchedItemPicker(
                selection: itemBinding,
                watchedID: watchedID,
                itemOptions: itemOptions
            )

            Text("Reveals the item while its icon is blinking. A clock or a battery percentage will not trigger this: they always move to a state they have never shown before, while a blink keeps returning to one. Requires screen recording permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var itemBinding: Binding<String> {
        Binding(get: { watchedID }, set: { condition = condition.withAttentionItem($0) })
    }
}

/// Editor for an image-comparison condition: pick a menu bar item to watch
/// and capture a reference image of its icon.
struct ImageConditionEditor: View {
    @Binding var condition: TriggerCondition
    let itemOptions: [TriggerItemOption]
    let captureReference: (String) async -> ImageComparisonReference?

    @State private var isCapturing = false

    private var watchedID: String {
        condition.imageValue?.itemIdentifier ?? ""
    }

    private var hasReference: Bool {
        condition.imageValue?.referenceHash != nil
    }

    private var exactReferenceNeedsRecapture: Bool {
        comparisonMode == .exact
            && hasReference
            && condition.imageValue?.referenceExactHash == nil
    }

    private var referenceImage: NSImage? {
        guard let data = condition.imageValue?.referenceImageData else { return nil }
        return NSImage(data: data)
    }

    private var comparisonMode: ImageComparisonMode {
        condition.imageValue?.comparisonMode ?? .fuzzy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchedItemPicker(
                selection: itemBinding,
                watchedID: watchedID,
                itemOptions: itemOptions
            )
            .disabled(isCapturing)

            IcePicker("Comparison", selection: comparisonModeBinding) {
                ForEach(ImageComparisonMode.allCases) { mode in
                    Text(mode.displayString).tag(mode)
                }
            }

            HStack(spacing: 12) {
                Button(isCapturing ? "Capturing…" : "Capture Reference") { capture() }
                    .disabled(isCapturing || watchedID.isEmpty)
                Spacer()
                referenceStatus
            }

            Text(comparisonHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var itemBinding: Binding<String> {
        Binding(get: { watchedID }, set: { condition = condition.withImageItem($0) })
    }

    private var comparisonModeBinding: Binding<ImageComparisonMode> {
        Binding(
            get: { comparisonMode },
            set: { condition = condition.withImageComparisonMode($0) }
        )
    }

    @ViewBuilder
    private var referenceStatus: some View {
        if let referenceImage {
            HStack(spacing: 8) {
                Text("Reference")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(nsImage: referenceImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 22)
                    .padding(4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Captured reference icon")
            }
        } else {
            Text(referenceStatusText)
                .font(.caption)
                .foregroundStyle(hasReference && !exactReferenceNeedsRecapture ? .green : .secondary)
        }
    }

    private var referenceStatusText: String {
        if exactReferenceNeedsRecapture {
            return String(localized: "Recapture required for Exact")
        }
        return hasReference
            ? String(localized: "Reference captured — recapture to add preview")
            : String(localized: "No reference yet")
    }

    private var comparisonHelp: String {
        switch comparisonMode {
        case .fuzzy:
            String(localized: "Fuzzy ignores small rendering differences and reveals when the icon meaningfully changes from the reference. Requires screen recording permission.")
        case .exact:
            String(localized: "Exact reveals on any pixel-content difference from the reference. Requires screen recording permission.")
        }
    }

    private func capture() {
        let id = watchedID
        guard !id.isEmpty else { return }
        isCapturing = true
        Task { @MainActor in
            let reference = await captureReference(id)
            isCapturing = false
            if let reference, watchedID == id {
                condition = condition.withImageReference(reference)
            }
        }
    }
}
