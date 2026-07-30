//
//  IceSlider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import CompactSlider
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

    @State private var isLabelActive = false

    private var height: CGFloat {
        24
    }

    private var borderShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        CompactSlider(value: $value, in: bounds, step: step ?? 0)
            .frame(height: height)
            .onContinuousHover { phase in
                if case .active = phase { isLabelActive = true } else { isLabelActive = false }
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
                .opacity(isLabelActive ? 0.65 : 0.45)
                .animation(.easeInOut(duration: 0.15), value: isLabelActive)
                .allowsHitTesting(false)
            }
            .glassEffect(.regular, in: borderShape)
            .overlay(
                borderShape.strokeBorder(.separator, lineWidth: 0.5)
            )
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
    }
}
