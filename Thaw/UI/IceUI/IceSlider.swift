//
//  IceSlider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CompactSlider
import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    @Binding private var value: Value

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let reversed: Bool
    private let showsValue: Bool
    private let unit: String?
    private let valueLabel: ValueLabel

    init(
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

    init(
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

    private var borderShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    private var height: CGFloat {
        24
    }

    var body: some View {
        CompactSlider(
            value: $value,
            in: bounds,
            step: step ?? 0,
            handleVisibility: .hovering(width: 0),
            minHeight: 0,
            gestureOptions: .default.subtracting([.scrollWheel])
        ) {
            HStack(spacing: 4) {
                valueLabel
                if showsValue {
                    Spacer()
                    Text(value.formatted())
                        .monospacedDigit()
                    if let unit {
                        Text(unit)
                    }
                }
            }
            .padding(.horizontal, 8)
            .opacity(0.5)
            .frame(height: height)
            .rotationEffect(.degrees(reversed ? 180 : 0))
        }
        .compactSliderDisabledHapticFeedback(true)
        .compactSliderSecondaryColor(
            progressColor: .accentColor.opacity(0.5),
            focusedProgressColor: .accentColor.opacity(0.75)
        )
        .rotationEffect(.degrees(reversed ? 180 : 0))
        .clipShape(borderShape)
        .contentShape([.interaction, .focusEffect], borderShape)
    }
}
