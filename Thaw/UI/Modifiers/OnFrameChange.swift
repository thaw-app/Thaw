//
//  OnFrameChange.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension View {
    /// Performs the given action when the view's frame changes.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The space used to measure the frame.
    ///   - action: Receives the new frame.
    func onFrameChange(
        in coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping (CGRect) -> Void
    ) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: coordinateSpace)
        } action: { _, newFrame in
            action(newFrame)
        }
    }

    /// Updates the given binding when the view's frame changes.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The space used to measure the frame.
    ///   - binding: Receives the new frame.
    func onFrameChange(
        in coordinateSpace: some CoordinateSpaceProtocol = .local,
        update binding: Binding<CGRect>
    ) -> some View {
        onFrameChange(in: coordinateSpace) { frame in
            binding.wrappedValue = frame
        }
    }
}
