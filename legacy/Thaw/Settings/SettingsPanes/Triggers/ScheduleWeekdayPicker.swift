//
//  ScheduleWeekdayPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ScheduleWeekdayPicker

struct ScheduleWeekdayPicker: View {
    @Binding var selection: Set<ScheduleWeekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleWeekday.allCases) { weekday in
                Button {
                    toggle(weekday)
                } label: {
                    Text(weekday.shortTitle)
                        .font(.caption)
                        .fontWeight(selection.contains(weekday) ? .semibold : .regular)
                        .frame(minWidth: 32)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection.contains(weekday) ? Color.white : Color.primary)
                .background(selection.contains(weekday) ? Color.orange : Color.secondary.opacity(0.12), in: Capsule())
                .accessibilityLabel(Text(weekday.shortTitle))
                // Selection is otherwise conveyed only by fill and weight,
                // so VoiceOver would announce every weekday identically.
                .accessibilityAddTraits(selection.contains(weekday) ? .isSelected : [])
            }
        }
    }

    private func toggle(_ weekday: ScheduleWeekday) {
        if selection.contains(weekday) {
            guard selection.count > 1 else { return }
            selection.remove(weekday)
        } else {
            selection.insert(weekday)
        }
    }
}
