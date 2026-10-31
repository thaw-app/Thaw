//
//  OnFrameChange.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension View {
    /// Performs the given action when the view's frame changes.
    public func onFrameChange(perform action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .local)
        } action: { _, newFrame in
            action(newFrame)
        }
    }

    /// Updates the given binding when the view's frame changes.
    public func onFrameChange(update binding: Binding<CGRect>) -> some View {
        onFrameChange { frame in
            binding.wrappedValue = frame
        }
    }
}
