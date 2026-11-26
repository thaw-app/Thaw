//
//  MenuBarSearchCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Menu bar search color capture")
struct MenuBarSearchCaptureTests {
    @MainActor
    private final class Pipeline {
        let screen = CurrentValueSubject<Int?, Never>(1)
        let isVisible = CurrentValueSubject<Bool, Never>(false)
        private(set) var captured: [Int] = []
        private var cancellable: AnyCancellable?

        init() {
            cancellable = MenuBarSearchModel.captureScreens(
                screen: screen,
                isVisible: isVisible,
                scheduler: DispatchQueue.main,
                delay: .milliseconds(30)
            )
            .sink { [unowned self] in captured.append($0) }
        }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    @Test("A panel that stays open is captured once, on its screen")
    func openPanelCaptures() async throws {
        let pipeline = Pipeline()
        pipeline.isVisible.send(true)
        try await pipeline.settle()
        #expect(pipeline.captured == [1])
    }

    @Test("Closing the panel before the delay ends cancels its capture")
    func quickCloseCancels() async throws {
        let pipeline = Pipeline()
        pipeline.isVisible.send(true)
        pipeline.isVisible.send(false)
        try await pipeline.settle()
        #expect(pipeline.captured.isEmpty)
    }

    @Test("Moving the open panel to another screen captures that screen")
    func screenChangeCapturesNewScreen() async throws {
        let pipeline = Pipeline()
        pipeline.isVisible.send(true)
        try await pipeline.settle()
        pipeline.screen.send(2)
        try await pipeline.settle()
        #expect(pipeline.captured == [1, 2])
    }
}
