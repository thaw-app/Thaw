//
//  SecondsLabel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct SecondsLabel: View {
    let value: Double

    var body: Text {
        let number = value.formatted(.number.precision(.fractionLength(0 ... 1)))
        return Text("\(number) seconds")
    }
}
