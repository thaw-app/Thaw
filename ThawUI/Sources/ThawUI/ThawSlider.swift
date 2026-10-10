//
//  ThawSlider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CompactSlider
import SwiftUI

public struct ThawSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    @Binding private var value: Value

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let reversed: Bool
    private let showsValue: Bool
    private let unit: String?
    private let valueLabel: ValueLabel

    public init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
        reversed: Bool = false,
        showsValue: Bool = false,
        unit: String? = nil,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.reversed = reversed
        self.showsValue = showsValue
        self.unit = unit
        self.valueLabel = valueLabel()
    }

    public init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
        reversed: Bool = false,
        showsValue: Bool = false,
        unit: String? = nil
    ) where ValueLabel == Text {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.reversed = reversed
        self.showsValue = showsValue
        self.unit = unit
        self.valueLabel = Text(valueLabelKey)
    }

    @State private var isLabelActive = false
    @FocusState private var isFocused: Bool

    private var height: CGFloat {
        24
    }

    private var borderShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    public var body: some View {
        CompactSlider(value: $value, in: bounds, step: step ?? 0)
            .frame(height: height)
            .onContinuousHover { phase in
                if case .active = phase {
                    isLabelActive = true
                } else {
                    isLabelActive = false
                }
            }
            .overlay {
                HStack(spacing: 4) {
                    valueLabel
                        .scaleEffect(x: reversed ? -1 : 1, y: 1)
                    if showsValue {
                        Spacer()
                        if reversed {
                            if let unit {
                                Text(unit)
                                    .scaleEffect(x: -1, y: 1)
                            }
                            Text(value.formatted())
                                .monospacedDigit()
                                .scaleEffect(x: -1, y: 1)
                        } else {
                            Text(value.formatted())
                                .monospacedDigit()
                            if let unit {
                                Text(unit)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: height)
                // Match ThawInk.supporting at idle; the slider's only label must clear 4.5:1 contrast.
                .opacity(isLabelActive ? 0.85 : 0.7)
                .thawAnimation(ThawMotion.quick, value: isLabelActive)
                .allowsHitTesting(false)
            }
            .thawGlass(.control, in: borderShape)
            .compactSliderHandleStyle(.hidden())
            .compactSliderScale(alignment: .top, lineLength: 6)
            .compactSliderOptionsByAdding(.tapToSlide, .snapToSteps)
            .compactSliderProgress { configuration in
                Rectangle().fill(
                    configuration.focusState.isFocused
                        ? Color.accentColor : Color.accentColor.opacity(0.8)
                )
            }
            .scaleEffect(x: reversed ? -1 : 1, y: 1)
            .clipShape(borderShape)
            .contentShape([.interaction, .focusEffect], borderShape)
            // CompactSlider skips keyboard focus; add Tab focus, arrow-key movement, and the system focus ring.
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled(false)
            .onMoveCommand(perform: nudge)
            // CompactSlider has no accessibility support; a system slider supplies VoiceOver's label, value, and adjustment gestures.
            .accessibilityRepresentation {
                if let step {
                    Slider(value: accessibilityValue, in: accessibilityBounds, step: Double(step)) {
                        valueLabel
                    }
                } else {
                    Slider(value: accessibilityValue, in: accessibilityBounds) {
                        valueLabel
                    }
                }
            }
    }

    /// One keyboard step: the slider's own step, or a hundredth of its range.
    /// A reversed slider runs right to left on screen, so left and right swap.
    private func nudge(_ direction: MoveCommandDirection) {
        let increment = step ?? (bounds.upperBound - bounds.lowerBound) / 100
        let sign: Value = switch direction {
        case .right, .up: reversed ? -1 : 1
        case .left, .down: reversed ? 1 : -1
        @unknown default: 0
        }
        value = min(bounds.upperBound, max(bounds.lowerBound, value + sign * increment))
    }

    private var accessibilityValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Value($0) }
        )
    }

    private var accessibilityBounds: ClosedRange<Double> {
        Double(bounds.lowerBound) ... Double(bounds.upperBound)
    }
}
