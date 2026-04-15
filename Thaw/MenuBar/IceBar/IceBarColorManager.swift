//
//  IceBarColorManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine

final class IceBarColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    func performSetup(with _: IceBarPanel) {}
}
