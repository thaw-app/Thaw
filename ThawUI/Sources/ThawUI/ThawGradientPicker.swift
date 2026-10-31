//
//  ThawGradientPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - ThawGradientPickerStrings

/// VoiceOver's words for the stops and the actions on them.
public nonisolated struct ThawGradientPickerStrings: Sendable {
    public var addStop: LocalizedStringResource
    public var spaceStopsEvenly: LocalizedStringResource
    /// Numbered from 1.
    public var stopName: @Sendable (_ number: Int) -> LocalizedStringResource

    public init(
        addStop: LocalizedStringResource,
        spaceStopsEvenly: LocalizedStringResource,
        stopName: @escaping @Sendable (_ number: Int) -> LocalizedStringResource
    ) {
        self.addStop = addStop
        self.spaceStopsEvenly = spaceStopsEvenly
        self.stopName = stopName
    }
}

// MARK: - ThawGradientPicker

/// Edits a ThawGradient's stops: click the track to add, drag to move, double-click to spread evenly, select to open the color panel.
/// On a focused handle, space selects, arrows move (option for fine steps), delete removes, escape releases the panel.
public struct ThawGradientPicker: View {
    @Binding private var gradient: ThawGradient

    private let label: Text
    let strings: ThawGradientPickerStrings
    private let supportsOpacity: Bool

    /// The index of the stop the color panel is currently editing.
    @State private var selectedStop: Int?

    /// supportsOpacity says whether the color panel offers an opacity control while a stop is selected.
    public init(
        _ labelKey: LocalizedStringResource,
        gradient: Binding<ThawGradient>,
        strings: ThawGradientPickerStrings,
        supportsOpacity: Bool = true
    ) {
        self._gradient = gradient
        self.strings = strings
        self.supportsOpacity = supportsOpacity
        self.label = Text(labelKey)
    }

    public var body: some View {
        LabeledContent {
            ThawGradientTrack(
                supportsOpacity: supportsOpacity,
                strings: strings,
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

/// Previews the gradient, hosts a handle per stop, and owns the color panel while a stop is selected.
private struct ThawGradientTrack: View {
    private static let handleWidth: CGFloat = 10

    private static let trackSize = CGSize(width: 200, height: 24)

    private static let trackCornerRadius: CGFloat = 6

    /// How close to the midpoint a stop must land to snap to center. Handles apply it while dragging too.
    static let centerSnapTolerance: CGFloat = 0.025

    let supportsOpacity: Bool

    let strings: ThawGradientPickerStrings

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

    private var hasSelection: Bool {
        selection != nil
    }

    private var trackShape: some InsettableShape {
        RoundedRectangle(cornerRadius: Self.trackCornerRadius, style: .continuous)
    }

    /// A hairline at the track's midpoint, where a stop snaps.
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
            .padding(.vertical, ThawSpacing.hairline)
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
            // On the track: key presses climb from the focused handle, and both settle track-level state.
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
            // Keyboard routes to the two mouse-only edits: adding a stop and spreading them.
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
            .accessibilityAction(named: Text(strings.addStop)) {
                insertStopFromKeyboard()
            }
            .accessibilityAction(named: Text(strings.spaceStopsEvenly)) {
                spaceStopsEvenly()
            }
            .onChange(of: gradient) { previous, current in
                // An empty gradient has no handles left to click, so there would be no way back.
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

    /// Turns a click on bare track into a new stop.
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
                strings: strings,
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

    /// Appends a stop colored to match the gradient at location, and selects it.
    private func insertStop(at location: CGFloat) {
        let clamped = location.clamped(to: 0 ... 1)
        let location = abs(clamped - 0.5) <= Self.centerSnapTolerance ? 0.5 : clamped
        let stop = gradient.color(at: location).map {
            ThawGradient.ColorStop.stop($0, location: location)
        }
        gradient.stops.append(stop ?? .black(location: location))
        selection = gradient.stops.indices.last
    }

    /// Lands halfway to the next stop on the right, so repeats subdivide; with nothing selected, the midpoint.
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

    private func removeSelectedStop() {
        let index = liveSelection
        selection = nil
        guard let index else {
            return
        }
        gradient.stops.remove(at: index)
    }

    /// Spreads the stops evenly across the track, keeping their left-to-right order.
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

    /// Nil when nothing is selected or the selection has fallen out of range.
    private var liveSelection: Int? {
        guard let selection, gradient.stops.indices.contains(selection) else {
            return nil
        }
        return selection
    }

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
    /// One arrow press, as a fraction of the track: twenty presses cross it.
    private static let nudge: CGFloat = 0.05

    /// The same with option held, for values a drag would have to be very steady to hit.
    private static let fineNudge: CGFloat = 0.01

    let strings: ThawGradientPickerStrings

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
            .accessibilityLabel(Text(strings.stopName(index + 1)))
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

    private func center(of stop: ThawGradient.ColorStop) -> CGPoint {
        CGPoint(
            x: geometry.size.width * stop.location,
            y: geometry.size.height / 2
        )
    }

    private func toggleSelection() {
        selection = isSelected ? nil : index
    }

    /// Moves the stop by delta for the keyboard. No center snap: keys land on exact values.
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
    /// Clears selection when the hosting window hides, so a hidden picker doesn't keep the color panel.
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
