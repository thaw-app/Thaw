//
//  HotkeyRecorder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - HotkeyRecorder

/// A two-part control that shows the key combination assigned to a hotkey and
/// lets the user type a new one.
///
/// The wider half carries the current combination and starts a recording; the
/// square half next to it cancels a recording in progress, or clears the
/// combination when there is nothing to cancel.
struct HotkeyRecorder<Label: View>: View {
    /// What the control is showing at the moment.
    private enum Phase {
        /// Waiting for the user to type a combination.
        case listening

        /// A combination is assigned. The payload is nil only if the hotkey
        /// somehow ended up enabled without one.
        case assigned(KeyCombination?)

        /// No combination is assigned.
        case empty
    }

    private let hotkey: Hotkey

    @State private var capture: KeyCapture

    private let label: Label

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        self.hotkey = hotkey
        self._capture = State(wrappedValue: KeyCapture(hotkey: hotkey))
        self.label = label()
    }

    private var phase: Phase {
        if capture.isListening {
            return .listening
        }
        if hotkey.isEnabled {
            return .assigned(hotkey.keyCombination)
        }
        return .empty
    }

    var body: some View {
        LabeledContent {
            segments
        } label: {
            label
        }
        .alert(
            "macOS already uses this shortcut",
            isPresented: $capture.isShowingReservedWarning
        ) {
            Button("Choose Another") {
                capture.isShowingReservedWarning = false
            }
        } message: {
            Text("Record a different one, or turn this one off in System Settings \(Constants.menuArrow) Keyboard \(Constants.menuArrow) Keyboard Shortcuts.")
        }
    }

    private var segments: some View {
        HStack(spacing: 1) {
            displaySegment
            actionSegment
        }
        .frame(minWidth: 132, idealWidth: 132, minHeight: 24, idealHeight: 24)
    }

    /// The wider half, which reports the current state and starts a recording.
    private var displaySegment: some View {
        Button {
            switch phase {
            case .listening: capture.stop()
            case .assigned, .empty: capture.start()
            }
        } label: {
            switch phase {
            case .listening:
                Text("Type Shortcut")
            case let .assigned(keyCombination):
                if let keyCombination {
                    Text(keyCombination.displayValue)
                } else {
                    Text("Error")
                }
            case .empty:
                Text("Record Shortcut")
            }
        }
        .buttonStyle(
            SegmentButtonStyle(
                side: .leading,
                isHighlighted: capture.isListening
            )
        )
    }

    /// The square half, whose meaning depends on the phase: back out of a
    /// recording, throw away an assigned combination, or start a recording.
    private var actionSegment: some View {
        Button {
            switch phase {
            case .listening: capture.stop()
            case .assigned: hotkey.keyCombination = nil
            case .empty: capture.start()
            }
        } label: {
            actionSegmentLabel
        }
        .buttonStyle(
            SegmentButtonStyle(
                side: .trailing,
                isHighlighted: false
            )
        )
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var actionSegmentLabel: some View {
        // The insets differ because the symbols are drawn at different
        // optical weights and would not otherwise look evenly sized.
        let (symbol, description, inset): (String, String, CGFloat) = switch phase {
        case .listening: ("escape", "Cancel", 6)
        case .assigned: ("xmark", "Clear", 7.5)
        case .empty: ("record.circle", "Record", 5.5)
        }
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .padding(inset)
            .accessibilityLabel(description)
    }
}

// MARK: - KeyCapture

/// Intercepts the next key press on behalf of a recorder and turns it into a
/// key combination for a hotkey.
@MainActor
@Observable
private final class KeyCapture {
    /// Whether key presses are currently being intercepted.
    private(set) var isListening = false

    /// Whether to warn that the combination just typed belongs to the system.
    var isShowingReservedWarning = false

    @ObservationIgnored
    private let hotkey: Hotkey

    @ObservationIgnored
    private lazy var monitor = EventMonitor.local(for: .keyDown) { [weak self] event in
        guard let self else {
            return event
        }
        consider(event)
        // Swallow the event either way: while recording, key presses are input
        // to this control rather than to whatever has focus.
        return nil
    }

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Begins intercepting key presses.
    ///
    /// The hotkey stands down for the duration, so the combination being
    /// replaced cannot fire while the replacement is being typed.
    func start() {
        guard !isListening else {
            return
        }
        hotkey.disable()
        monitor.start()
        isListening = true
    }

    /// Stops intercepting key presses and puts the hotkey back to work.
    func stop() {
        guard isListening else {
            return
        }
        monitor.stop()
        hotkey.enable()
        isListening = false
    }

    /// Works out what an intercepted key press means.
    ///
    /// A bare Escape backs out of the recording. Everything else needs a
    /// modifier that is not Shift, since a global hotkey on an unmodified key
    /// would swallow ordinary typing everywhere.
    private func consider(_ event: NSEvent) {
        let keyCombination = KeyCombination(event: event)

        guard !keyCombination.modifiers.isEmpty else {
            if keyCombination.key == .escape {
                stop()
            } else {
                NSSound.beep()
            }
            return
        }
        guard keyCombination.modifiers != .shift else {
            NSSound.beep()
            return
        }
        guard !keyCombination.isSystemReserved else {
            isShowingReservedWarning = true
            return
        }

        hotkey.keyCombination = keyCombination
        stop()
    }
}

// MARK: - SegmentButtonStyle

/// The style shared by the recorder's two halves, which round off the outer
/// end of the control and leave the inner end square.
private struct SegmentButtonStyle: ButtonStyle {
    /// The end of the control a segment sits at.
    enum Side {
        case leading
        case trailing
    }

    var side: Side
    var isHighlighted: Bool

    private var outline: some InsettableShape {
        let r: CGFloat = 6
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
