//
//  HotkeyRecorder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import AppKit
import SwiftUI

// MARK: - HotkeyRecorderStrings

public nonisolated struct HotkeyRecorderStrings: Sendable {
    public var typeShortcut: LocalizedStringResource
    public var recordShortcut: LocalizedStringResource
    /// Spoken for the button that backs out of a recording.
    public var cancel: LocalizedStringResource
    /// Spoken for the button that removes the combination.
    public var clear: LocalizedStringResource
    /// Spoken for the button that starts a recording.
    public var record: LocalizedStringResource
    /// The space bar's name in a combination.
    public var spaceKey: LocalizedStringResource
    public var reservedTitle: LocalizedStringResource
    public var reservedMessage: LocalizedStringResource
    public var chooseAnother: LocalizedStringResource

    public init(
        typeShortcut: LocalizedStringResource,
        recordShortcut: LocalizedStringResource,
        cancel: LocalizedStringResource,
        clear: LocalizedStringResource,
        record: LocalizedStringResource,
        spaceKey: LocalizedStringResource,
        reservedTitle: LocalizedStringResource,
        reservedMessage: LocalizedStringResource,
        chooseAnother: LocalizedStringResource
    ) {
        self.typeShortcut = typeShortcut
        self.recordShortcut = recordShortcut
        self.cancel = cancel
        self.clear = clear
        self.record = record
        self.spaceKey = spaceKey
        self.reservedTitle = reservedTitle
        self.reservedMessage = reservedMessage
        self.chooseAnother = chooseAnother
    }
}

// MARK: - HotkeyRecorder

/// A two-part control that shows an assigned key combination and lets the user type a new one.
/// The app owns the hotkey and stands its hotkeys down from onRecordingChange, so the old combination can't fire.
public struct HotkeyRecorder<Label: View>: View {
    /// What the control is showing at the moment.
    private enum Phase {
        /// Waiting for the user to type a combination.
        case listening
        case assigned(KeyCombination)
        case empty
    }

    @Binding private var keyCombination: KeyCombination?
    let strings: HotkeyRecorderStrings
    private let width: CGFloat?
    private let onRecordingChange: (Bool) -> Void
    private let label: Label

    @State private var capture = KeyCapture()

    /// A nil key combination shows the control as empty. A nil width lets it grow from a minimum of 132; set one for a
    /// narrow row or recorders that must line up. onRecordingChange gets true when a recording starts, false when it ends.
    public init(
        keyCombination: Binding<KeyCombination?>,
        strings: HotkeyRecorderStrings,
        width: CGFloat? = nil,
        onRecordingChange: @escaping (Bool) -> Void = { _ in
            // Nothing to suspend.
        },
        @ViewBuilder label: () -> Label
    ) {
        self._keyCombination = keyCombination
        self.strings = strings
        self.width = width
        self.onRecordingChange = onRecordingChange
        self.label = label()
    }

    private var phase: Phase {
        if capture.isListening {
            return .listening
        }
        if let keyCombination {
            return .assigned(keyCombination)
        }
        return .empty
    }

    public var body: some View {
        LabeledContent {
            segments
        } label: {
            label
        }
        .alert(
            Text(strings.reservedTitle),
            isPresented: $capture.isShowingReservedWarning
        ) {
            Button(strings.chooseAnother) {
                capture.isShowingReservedWarning = false
            }
        } message: {
            Text(strings.reservedMessage)
        }
        .onDisappear { capture.stop() }
    }

    @ViewBuilder
    private var segments: some View {
        let height = SegmentButtonStyle.outerRadius * 2
        let content = HStack(spacing: 1) {
            displaySegment
            actionSegment
        }
        if let width {
            content.frame(width: width, height: height)
        } else {
            content.frame(minWidth: 132, idealWidth: 132, minHeight: height, idealHeight: height)
        }
    }

    private func startCapture() {
        capture.start(onRecordingChange: onRecordingChange) { keyCombination = $0 }
    }

    func title(for keyCombination: KeyCombination) -> String {
        keyCombination.displayValue(spaceName: String(localized: strings.spaceKey))
    }

    /// The wider half, which reports the current state and starts a recording.
    private var displaySegment: some View {
        Button {
            switch phase {
            case .listening: capture.stop()
            case .assigned, .empty: startCapture()
            }
        } label: {
            switch phase {
            case .listening:
                Text(strings.typeShortcut)
            case let .assigned(keyCombination):
                Text(verbatim: title(for: keyCombination))
            case .empty:
                Text(strings.recordShortcut)
            }
        }
        .buttonStyle(SegmentButtonStyle(side: .leading, isHighlighted: capture.isListening))
    }

    /// The square half, whose meaning depends on the phase: back out of a
    /// recording, throw away an assigned combination, or start a recording.
    private var actionSegment: some View {
        Button {
            switch phase {
            case .listening: capture.stop()
            case .assigned: keyCombination = nil
            case .empty: startCapture()
            }
        } label: {
            actionSegmentLabel
        }
        .buttonStyle(SegmentButtonStyle(side: .trailing, isHighlighted: false))
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var actionSegmentLabel: some View {
        // The insets differ because the symbols are drawn at different
        // optical weights and would not otherwise look evenly sized.
        let (symbol, description, inset): (String, LocalizedStringResource, CGFloat) = switch phase {
        case .listening: ("escape", strings.cancel, 6)
        case .assigned: ("xmark", strings.clear, 7.5)
        case .empty: ("record.circle", strings.record, 5.5)
        }
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .padding(inset)
            .accessibilityLabel(Text(description))
    }
}

// MARK: - KeyCapture

/// Intercepts the next key press on behalf of a recorder and turns it into a key combination.
@MainActor
@Observable
final class KeyCapture {
    /// Whether key presses are currently being intercepted.
    private(set) var isListening = false

    /// Whether to warn that the combination just typed belongs to the system.
    var isShowingReservedWarning = false

    @ObservationIgnored private let isReserved: (KeyCombination) -> Bool
    @ObservationIgnored private let beep: () -> Void
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onRecordingChange: (Bool) -> Void = { _ in
        // Set by start.
    }

    @ObservationIgnored private var onCapture: (KeyCombination) -> Void = { _ in
        // Set by start.
    }

    init(
        isReserved: @escaping (KeyCombination) -> Bool = { $0.isSystemReserved },
        beep: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.isReserved = isReserved
        self.beep = beep
    }

    /// Begins intercepting key presses.
    func start(onRecordingChange: @escaping (Bool) -> Void, onCapture: @escaping (KeyCombination) -> Void) {
        guard !isListening else {
            return
        }
        self.onRecordingChange = onRecordingChange
        self.onCapture = onCapture
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            return intercept(event)
        }
        isListening = true
        onRecordingChange(true)
    }

    /// Stops intercepting key presses and puts the hotkeys back to work.
    func stop() {
        guard isListening else {
            return
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isShowingReservedWarning = false
        isListening = false
        onRecordingChange(false)
    }

    /// Decides what happens to a key press while recording: it is input to this control
    /// rather than to whatever has focus, unless the warning is up and needs the keyboard.
    func intercept(_ event: NSEvent) -> NSEvent? {
        guard !isShowingReservedWarning else {
            return event
        }
        consider(KeyCombination(event: event))
        return nil
    }

    /// Escape backs out of the recording. Everything else needs a modifier other than Shift,
    /// since a global hotkey on an unmodified key would swallow ordinary typing everywhere.
    func consider(_ keyCombination: KeyCombination) {
        guard !keyCombination.modifiers.isEmpty, keyCombination.modifiers != .shift else {
            if keyCombination.key == .escape {
                stop()
            } else {
                beep()
            }
            return
        }
        guard !isReserved(keyCombination) else {
            isShowingReservedWarning = true
            return
        }

        onCapture(keyCombination)
        stop()
    }
}

// MARK: - SegmentButtonStyle

/// The style shared by the recorder's two halves, which round off the outer
/// end of the control and leave the inner end square.
private struct SegmentButtonStyle: ButtonStyle {
    /// Half the control's height, so the outer ends are round like the capsule buttons.
    static let outerRadius: CGFloat = 12
    /// The end of the control a segment sits at.
    enum Side {
        case leading
        case trailing
    }

    var side: Side
    var isHighlighted: Bool

    private var outline: some InsettableShape {
        let r = Self.outerRadius
        let radii = switch side {
        case .leading: RectangleCornerRadii(topLeading: r, bottomLeading: r)
        case .trailing: RectangleCornerRadii(bottomTrailing: r, topTrailing: r)
        }
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        // Pressing inverts the highlight, so a highlighted segment reads as
        // pressed when it is released and vice versa.
        let isFilled = configuration.isPressed != isHighlighted
        let borderShape = outline
        borderShape
            .fill(isFilled ? .tertiary : .quaternary)
            .overlay {
                configuration.label
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .thawGlass(.control, in: borderShape)
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
