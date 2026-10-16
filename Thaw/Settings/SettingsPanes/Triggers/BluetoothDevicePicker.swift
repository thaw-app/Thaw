//
//  BluetoothDevicePicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - BluetoothDevicePicker

/// The Bluetooth device picker, shared by the trigger row and the compound
/// condition editor.
///
/// Offers the names the matcher compares. A classic Bluetooth name can differ
/// from System Settings (AirPods may report a model name), so a typed guess can
/// silently never match. "Other…" keeps an unpaired device reachable.
struct BluetoothDevicePicker: View {
    @Binding var name: String
    let options: [TriggerBluetoothOption]
    let refreshOptions: () -> Void
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    /// Tags the "Other…" row. Prefixed with a control character so it can
    /// never collide with a real device name.
    private static let customTag = "\u{1}custom"

    /// Set when the user picks "Other…" while the current value is a listed
    /// device, which `isUnlisted` alone cannot detect.
    @State private var prefersCustomEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IcePicker("Device", selection: selection) {
                if name.isEmpty {
                    Text("Choose a device…").tag("")
                }
                ForEach(options, id: \.name) { option in
                    Text(option.displayString).tag(option.name)
                }
                Text("Other…").tag(Self.customTag)
            }
            if showsTextField {
                CommitTextField(
                    title: "Device name",
                    prompt: "Device name",
                    value: $name,
                    focusedField: focusedField,
                    focusID: focusID
                )
            }
        }
        // Rows are keyed by index, so deleting one carries this state onto the next.
        // Clear it whenever the bound value names a listed device.
        .onChange(of: name, initial: true) { _, newValue in
            if options.contains(where: { $0.name == newValue }) {
                prefersCustomEntry = false
            }
        }
        // Re-enumerate whenever this picker appears: the pane's own refresh
        // ran at pane-appearance, which predates a kind switched to
        // Bluetooth, a device paired since, or an access grant.
        .onAppear(perform: refreshOptions)
    }

    /// A configured name missing from the list (unpaired, or typed before this
    /// picker existed). Never hidden, or opening the editor would discard it.
    private var isUnlisted: Bool {
        !name.isEmpty && !options.contains { $0.name == name }
    }

    private var showsTextField: Bool {
        prefersCustomEntry || isUnlisted
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if showsTextField {
                    return Self.customTag
                }
                return name
            },
            set: { newValue in
                if newValue == Self.customTag {
                    prefersCustomEntry = true
                } else {
                    prefersCustomEntry = false
                    name = newValue
                }
            }
        )
    }
}
