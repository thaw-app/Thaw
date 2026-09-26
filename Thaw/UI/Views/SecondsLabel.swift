//
//  SecondsLabel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct SecondsLabel: View {
    let value: Double

    var body: Text {
        Text("\(value, format: .number.precision(.fractionLength(0 ... 1))) seconds")
    }
}
