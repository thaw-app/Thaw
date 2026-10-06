//
//  ScreenCorners.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Observation

/// Small black corner panels avoid a fullscreen overlay participating in every menu-bar window walk.
/// Panels ignore the mouse, join all Spaces and fullscreen apps, and are excluded from screenshots and Thaw captures.
@MainActor
final class ScreenCorners {
    private weak var appState: AppState?
    private var panels: [NSPanel] = []
    private var observationTask: Task<Void, Never>?
    private var screenObserver: AnyCancellable?

    func performSetup(with appState: AppState) {
        self.appState = appState
        observationTask = Task { @MainActor [weak self, general = appState.settings.general] in
            for await _ in Observations({ (general.roundScreenCorners, general.screenCornerRadius) }) {
                self?.reconcile()
            }
        }
        screenObserver = DisplayTopology.shared.screenParametersChanged
            .sink { [weak self] in self?.reconcile() }
    }

    private func reconcile() {
        removePanels()
        guard let general = appState?.settings.general, general.roundScreenCorners else { return }
        let radius = CGFloat(general.screenCornerRadius)
        for screen in NSScreen.screens {
            for corner in Corner.allCases {
                panels.append(makePanel(corner, radius: radius, on: screen))
            }
        }
    }

    private func removePanels() {
        for panel in panels {
            panel.unregisterAsMenuBarOverlay()
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func makePanel(_ corner: Corner, radius: CGFloat, on screen: NSScreen) -> NSPanel {
        let frame = screen.frame
        let origin = switch corner {
        case .topLeft: CGPoint(x: frame.minX, y: frame.maxY - radius)
        case .topRight: CGPoint(x: frame.maxX - radius, y: frame.maxY - radius)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: CGPoint(x: frame.maxX - radius, y: frame.minY)
        }
        let panel = NSPanel.menuBarOverlay(opaque: false, absorbsClicks: false)
        // Above the menu bar, its menus and full-screen apps, or the corners
        // show square behind them.
        panel.level = .screenSaver
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: radius, height: radius)), display: false)
        panel.contentView = CornerView(corner: corner)
        panel.orderFrontRegardless()
        panel.registerAsMenuBarOverlay()
        return panel
    }

    fileprivate enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Black everywhere in its square except a quarter circle cut out of the
    /// side facing the screen's middle.
    private final class CornerView: NSView {
        let corner: Corner

        init(corner: Corner) {
            self.corner = corner
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_: NSRect) {
            let square = bounds
            let radius = square.width
            let center = switch corner {
            case .topLeft: CGPoint(x: square.maxX, y: square.minY)
            case .topRight: CGPoint(x: square.minX, y: square.minY)
            case .bottomLeft: CGPoint(x: square.maxX, y: square.maxY)
            case .bottomRight: CGPoint(x: square.minX, y: square.maxY)
            }
            let path = NSBezierPath(rect: square)
            path.appendOval(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
        }
    }
}
