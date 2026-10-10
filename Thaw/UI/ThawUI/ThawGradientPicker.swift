//
//  ThawGradientPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI
import ThawUI

// MARK: - ThawGradientPicker

/// A labeled control for editing the color stops of an ThawGradient.
///
/// Click the track to add a stop, drag to move, double-click to spread
/// evenly; selecting a handle opens the shared color panel. Handles take
/// keyboard focus: space selects, arrows move (option for fine steps),
/// delete removes, escape releases the panel.
struct ThawGradientPicker: View {
    @Binding private var gradient: ThawGradient

    private let label: Text
    private let supportsOpacity: Bool

    /// The index of the stop the color panel is currently editing.
    @State private var selectedStop: Int?

    /// Creates a gradient picker labeled by a string.
    ///
    /// - Parameters:
    ///   - labelKey: A description of what the gradient is for.
    ///   - gradient: The gradient the picker edits.
    ///   - supportsOpacity: Whether the color panel offers an opacity
    ///     control while a stop is selected.
    init(_ labelKey: LocalizedStringKey, gradient: Binding<ThawGradient>, supportsOpacity: Bool = true) {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = Text(labelKey)
    }

    var body: some View {
        LabeledContent {
            ThawGradientTrack(
                supportsOpacity: supportsOpacity,
                gradient: $gradient,
                selection: $selectedStop
            )
            .deselectingWhenWindowHides($selectedStop)
        } label: {
            label
        }
    }
}

// MARK: - ThawGradientTrack

/// The interactive body of the picker.
///
/// The track previews the gradient, hosts a handle for every stop, and
/// owns the shared color panel for as long as a stop stays selected.
private struct ThawGradientTrack: View {
    /// The width of a stop handle, in points.
    private static let handleWidth: CGFloat = 10

    /// The size of the gradient preview.
    private static let trackSize = CGSize(width: 200, height: 24)

    /// The corner radius of the gradient preview.
    private static let trackCornerRadius: CGFloat = 6

    /// How close to the midpoint a stop has to land before it snaps to
    /// dead center. Shared with the handles, which apply the same snap
    /// while dragging.
    static let centerSnapTolerance: CGFloat = 0.025

    /// Whether the color panel offers an opacity control.
    let supportsOpacity: Bool

    /// The gradient being edited.
    @Binding var gradient: ThawGradient

    /// The index of the stop the color panel is editing.
    @Binding var selection: Int?

    /// The stop most recently moved or selected, drawn above the rest.
    @State private var frontmostStop: Int?

    /// Which handle holds keyboard focus; follows the selection so keys reach
    /// the stop the color panel is editing.
    @FocusState private var focusedStop: Int?

    @State private var colorPanelObservers = Set<AnyCancellable>()

    @Environment(\.isEnabled) private var isEnabled

    /// Whether a stop is selected, meaning the color panel is in play.
    private var hasSelection: Bool {
        selection != nil
    }

    private var trackShape: some InsettableShape {
        RoundedRectangle(cornerRadius: Self.trackCornerRadius, style: .continuous)
    }

    /// A hairline at the midpoint of the track, showing where a stop
    /// snaps to.
    private var centerTick: some View {
        Rectangle()
            .frame(width: 1, height: 6)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        gradient.horizontalSwiftUIView(using: .displayP3)
            .clipShape(trackShape)
            .overlay { trackShape.strokeBorder(.secondary) }
            .overlay { centerTick }
            .padding(.vertical, 2)
            .overlay {
                GeometryReader { geometry in
                    insertionSurface(in: geometry)
                    stopHandles(in: geometry)
                }
                .padding(.horizontal, Self.handleWidth / 2)
            }
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .thawShadow(.control)
            .onTapGesture(count: 2, perform: spaceStopsEvenly)
            // On the track rather than the handle: key presses climb from
            // the focused handle, and these two both settle track-level
            // state (the selection, and the color panel it owns).
            .onKeyPress(.delete) {
                guard hasSelection else {
                    return .ignored
                }
                removeSelectedStop()
                return .handled
            }
            .onKeyPress(.escape) {
                guard hasSelection else {
                    return .ignored
                }
                selection = nil
                hideColorPanel()
                return .handled
            }
            // Keyboard routes to the two edits that otherwise need a mouse
            // (a click on bare track adds a stop, a double-click spreads
            // them), reached from the focused handle.
            .onKeyPress(keys: ["+", "=", "e"]) { press in
                switch press.key {
                case "+", "=":
                    insertStopFromKeyboard()
                    return .handled
                case "e":
                    spaceStopsEvenly()
                    return .handled
                default:
                    return .ignored
                }
            }
            .accessibilityAction(named: Text("Add a color stop")) {
                insertStopFromKeyboard()
            }
            .accessibilityAction(named: Text("Space color stops evenly")) {
                spaceStopsEvenly()
            }
            .onChange(of: gradient) { previous, current in
                // A gradient with nothing in it has no handles left to
                // click, so there would be no way back out of it.
                if current.stops.isEmpty {
                    gradient = previous
                }
            }
            .onChange(of: selection) { previous, current in
                guard previous != current else {
                    return
                }
                focusedStop = current
                colorPanelObservers.removeAll()
                guard current != nil else {
                    return
                }
                // Reopening puts the panel in front even if it was
                // already showing behind another window.
                hideColorPanel()
                showColorPanel()
                observeColorPanel()
            }
            .compositingGroup()
            .allowsHitTesting(isEnabled)
            // Not dimmed when disabled: halving opacity put the track below
            // the contrast floor.
            .grayscale(isEnabled ? 0 : 1)
    }

    /// A transparent layer beneath the handles that turns a click on bare
    /// track into a new stop.
    private func insertionSurface(in geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(trackShape)
            .onTapGesture { location in
                insertStop(at: location.x / geometry.size.width)
            }
    }

    private func stopHandles(in geometry: GeometryProxy) -> some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            ThawGradientStopHandle(
                gradient: $gradient,
                selection: $selection,
                frontmostStop: $frontmostStop,
                focus: $focusedStop,
                index: index,
                geometry: geometry,
                width: Self.handleWidth
            )
        }
    }

    /// Appends a stop at location, colored to match whatever the
    /// gradient already renders there, and selects it.
    private func insertStop(at location: CGFloat) {
        let clamped = location.clamped(to: 0 ... 1)
        let location = abs(clamped - 0.5) <= Self.centerSnapTolerance ? 0.5 : clamped
        let stop = gradient.color(at: location).map {
            ThawGradient.ColorStop.stop($0, location: location)
        }
        gradient.stops.append(stop ?? .black(location: location))
        selection = gradient.stops.indices.last
    }

    /// Adds a stop without a pointer position to aim with.
    ///
    /// Lands halfway to the next stop on the right, so repeats subdivide;
    /// with nothing selected it takes the midpoint.
    private func insertStopFromKeyboard() {
        guard let index = liveSelection else {
            insertStop(at: 0.5)
            return
        }
        let start = gradient.stops[index].location
        let next = gradient.stops
            .map(\.location)
            .filter { $0 > start }
            .min() ?? 1
        insertStop(at: (start + next) / 2)
    }

    /// Drops the selected stop, leaving nothing selected.
    private func removeSelectedStop() {
        let index = liveSelection
        selection = nil
        guard let index else {
            return
        }
        gradient.stops.remove(at: index)
    }

    /// Spreads the stops from one end of the track to the other at equal
    /// intervals, preserving their left-to-right order.
    private func spaceStopsEvenly() {
        switch gradient.stops.count {
        case 0:
            return
        case 1:
            gradient.stops[0].location = 0.5
        case let count:
            let ordered = gradient.stops.sorted { $0.location < $1.location }
            gradient.stops = ordered.enumerated().map { offset, stop in
                stop.withLocation(CGFloat(offset) / CGFloat(count - 1))
            }
        }
    }

    // MARK: Color Panel

    private func showColorPanel() {
        let panel = NSColorPanel.shared
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func hideColorPanel() {
        let panel = NSColorPanel.shared
        if panel.isVisible {
            panel.close()
        }
    }

    /// Seeds the color panel with the selected stop's color, then keeps
    /// the two in step until the selection changes.
    private func observeColorPanel() {
        let panel = NSColorPanel.shared

        if let color = selectedColor, panel.color != color {
            panel.color = color
        }

        var observers = Set<AnyCancellable>()

        panel.publisher(for: \.color)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { color in
                adoptPanelColor(color)
            }
            .store(in: &observers)

        panel.publisher(for: \.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { isVisible in
                panelVisibilityChanged(to: isVisible)
            }
            .store(in: &observers)

        colorPanelObservers = observers
    }

    /// The index of the selected stop, or nil when nothing is selected
    /// or the selection has fallen out of range.
    private var liveSelection: Int? {
        guard let selection, gradient.stops.indices.contains(selection) else {
            return nil
        }
        return selection
    }

    /// The selected stop's color, expressed for the color panel.
    private var selectedColor: NSColor? {
        liveSelection.flatMap { NSColor(cgColor: gradient.stops[$0].color) }
    }

    private func adoptPanelColor(_ color: NSColor) {
        guard
            let index = liveSelection,
            NSColorPanel.shared.isVisible,
            gradient.stops[index].color != color.cgColor
        else {
            return
        }
        gradient.stops[index].color = color.cgColor
    }

    private func panelVisibilityChanged(to isVisible: Bool) {
        guard hasSelection else {
            return
        }
        // Closing the panel is the user's way of finishing with a stop.
        guard isVisible else {
            selection = nil
            return
        }
        let panel = NSColorPanel.shared
        if panel.showsAlpha != supportsOpacity {
            panel.showsAlpha = supportsOpacity
        }
    }
}

// MARK: - ThawGradientStopHandle

/// A draggable capsule marking one stop's position along the track.
private struct ThawGradientStopHandle: View {
    /// How far one arrow key moves a stop along the track, as a fraction of
    /// its length: twenty presses cross it end to end.
    private static let nudge: CGFloat = 0.05

    /// The same, holding option, fine enough to land on a value a drag
    /// would have to be very steady to hit.
    private static let fineNudge: CGFloat = 0.01

    @Binding var gradient: ThawGradient
    @Binding var selection: Int?
    @Binding var frontmostStop: Int?

    let focus: FocusState<Int?>.Binding
    let index: Int
    let geometry: GeometryProxy
    let width: CGFloat

    private var stop: ThawGradient.ColorStop? {
        gradient.stops.indices.contains(index) ? gradient.stops[index] : nil
    }

    private var isSelected: Bool {
        index == selection
    }

    private var isFrontmost: Bool {
        index == frontmostStop
    }

    private var selectionHalo: AnyShapeStyle {
        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)
    }

    private var handleShape: some InsettableShape {
        Capsule(style: .continuous)
    }

    var body: some View {
        capsule
            .focusable()
            .focused(focus, equals: index)
            .gesture(
                DragGesture(minimumDistance: 2).onChanged { value in
                    move(with: value)
                }
            )
            .onTapGesture(perform: toggleSelection)
            .onKeyPress(.space) {
                toggleSelection()
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                let step = press.modifiers.contains(.option) ? Self.fineNudge : Self.nudge
                nudge(by: press.key == .leftArrow ? -step : step)
                return .handled
            }
            .onChange(of: isSelected) { _, selected in
                if selected {
                    frontmostStop = index
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Color stop \(index + 1)"))
            .accessibilityValue(Text(Double(stop?.location ?? 0).formatted(.percent.precision(.fractionLength(0)))))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggleSelection() }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(by: Self.nudge)
                case .decrement: nudge(by: -Self.nudge)
                @unknown default: break
                }
            }
    }

    @ViewBuilder
    private var capsule: some View {
        if let stop {
            handleShape
                .fill(Color(cgColor: stop.color))
                .thawGlass(.field(isFocused: isSelected), in: handleShape)
                .overlay(
                    handleShape.strokeBorder(isSelected ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(.separator), lineWidth: 1.0)
                )
                .background(selectionHalo, in: handleShape.inset(by: -2))
                .contentShape([.interaction, .focusEffect], handleShape)
                .frame(width: width)
                .position(center(of: stop))
                .zIndex(isFrontmost ? 2 : stop.location)
                .compositingGroup()
        }
    }

    /// Where the handle for stop sits within the track.
    private func center(of stop: ThawGradient.ColorStop) -> CGPoint {
        CGPoint(
            x: geometry.size.width * stop.location,
            y: geometry.size.height / 2
        )
    }

    private func toggleSelection() {
        selection = isSelected ? nil : index
    }

    /// Moves the stop by delta for the keyboard. No center snap: keys land on
    /// exact values, and snapping would make 0.5 unreachable.
    private func nudge(by delta: CGFloat) {
        guard let stop else {
            return
        }
        gradient.stops[index].location = (stop.location + delta).clamped(to: 0 ... 1)
        frontmostStop = index
    }

    /// Tracks the pointer, snapping to the center tick mark when the drag
    /// slows down near it. Holding command drags past the snap.
    private func move(with value: DragGesture.Value) {
        guard stop != nil else {
            return
        }

        var newLocation = (value.location.x / geometry.size.width).clamped(to: 0 ... 1)

        if
            abs(value.velocity.width) <= 75,
            abs(newLocation - 0.5) <= ThawGradientTrack.centerSnapTolerance,
            !NSEvent.modifierFlags.contains(.command)
        {
            newLocation = 0.5
        }

        gradient.stops[index].location = newLocation
        frontmostStop = index
    }
}

// MARK: - Window Visibility

private extension View {
    /// Clears selection whenever the window hosting this view stops
    /// being visible, so a hidden picker does not keep the color panel.
    func deselectingWhenWindowHides(_ selection: Binding<Int?>) -> some View {
        modifier(DeselectWhenWindowHides(selection: selection))
    }
}

private struct DeselectWhenWindowHides: ViewModifier {
    @Binding var selection: Int?
    @State private var observer: AnyCancellable?

    func body(content: Content) -> some View {
        content.onWindowChange { window in
            observer = window?.publisher(for: \.isVisible)
                .removeDuplicates()
                .filter { !$0 }
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    selection = nil
                }
        }
    }
}
