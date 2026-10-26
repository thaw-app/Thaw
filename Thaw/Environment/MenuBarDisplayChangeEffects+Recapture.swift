//
//  MenuBarDisplayChangeEffects+Recapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension MenuBarDisplayChangeEffects {
    // The image cache still recaptures from its own screen publisher until this takes over.
    func recaptureImages() async {}
}
