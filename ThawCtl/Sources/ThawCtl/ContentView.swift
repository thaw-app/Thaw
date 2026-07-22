//
//  ContentView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct ContentView: View {
    @State private var engine: ThawCtlEngine

    @State private var setKey = ""
    @State private var setValue = ""
    @State private var toggleKey = ""
    @State private var getKey = ""
    @State private var displayUUID = ""

    init(engine: ThawCtlEngine) {
        self.engine = engine
    }

    var body: some View {
        HSplitView {
            controlPanel
            responsePanel
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                actionSection
                setSection
                toggleSection
                getSection
                authorizeSection
            }
            .padding()
        }
        .frame(minWidth: 320)
    }

    private var actionSection: some View {
        GroupBox("Quick Actions") {
            VStack(spacing: 6) {
                HStack {
                    actionButton("Toggle Hidden", action: "toggle-hidden")
                    actionButton("Always Hidden", action: "toggle-always-hidden")
                }
                HStack {
                    actionButton("Search", action: "search")
                    actionButton("Toggle Bar", action: "toggle-thawbar")
                }
                HStack {
                    actionButton("App Menus", action: "toggle-application-menus")
                    actionButton("Settings", action: "open-settings")
                }
            }
            .padding(4)
        }
    }

    private func actionButton(_ label: String, action: String) -> some View {
        Button(label) { engine.sendAction(action) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
    }

    private var setSection: some View {
        GroupBox("Set Setting (thaw://set)") {
            VStack(spacing: 6) {
                HStack {
                    Text("Key:")
                    TextField("e.g. autoRehide", text: $setKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("Val:")
                    TextField("true/false", text: $setValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 70)
                }
                Button("Send Set") { engine.sendSet(key: setKey, value: setValue, display: displayUUID) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(setKey.isEmpty || setValue.isEmpty)
            }
            .padding(4)
        }
    }

    private var toggleSection: some View {
        GroupBox("Toggle Setting (thaw://toggle)") {
            VStack(spacing: 6) {
                Picker("Key:", selection: $toggleKey) {
                    Text("Pick a key...").tag("")
                    ForEach(booleanKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .pickerStyle(.menu)
                Button("Send Toggle") { engine.sendToggle(key: toggleKey, display: displayUUID) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(toggleKey.isEmpty)
            }
            .padding(4)
        }
    }

    private var getSection: some View {
        GroupBox("Get Setting (thaw://get → thawctl://callback)") {
            VStack(spacing: 6) {
                Picker("Key:", selection: $getKey) {
                    Text("Pick a key...").tag("")
                    ForEach(getKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .pickerStyle(.menu)
                Button("Send Get") { engine.sendGet(key: getKey, display: displayUUID) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(getKey.isEmpty)
            }
            .padding(4)
        }
    }

    private var authorizeSection: some View {
        GroupBox("Authorization") {
            VStack(spacing: 6) {
                Button("Request Authorization") { engine.sendAuthorize() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text("Triggers whitelist dialog in Thaw")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var booleanKeys: [String] {
        [
            "autoRehide", "showOnClick", "showOnDoubleClick", "showOnHover", "showOnScroll",
            "useIceBarOnlyOnNotchedDisplay", "hideApplicationMenus", "enableAlwaysHiddenSection",
            "useOptionClickToShowAlwaysHiddenSection", "useDoubleClickToShowAlwaysHiddenSection",
            "enableSecondaryContextMenu", "showAllSectionsOnUserDrag", "showMenuBarTooltips",
            "enableDiagnosticLogging", "customIceIconIsTemplate", "showIceIcon",
            "iceBarLocationOnHotkey", "useLCSSortingOnNotchedDisplays",
        ]
    }

    private var getKeys: [String] {
        ["all"] + booleanKeys + [
            "rehideInterval", "showOnHoverDelay", "tooltipDelay",
            "iconRefreshInterval", "rehideStrategy", "useIceBar", "iceBarLocation",
            "alwaysShowHiddenItems", "iceBarLayout", "gridColumns", "version", "displays",
        ]
    }

    // MARK: - Response Panel

    private var responsePanel: some View {
        VStack(spacing: 0) {
            // Display UUID field
            HStack {
                Text("Display UUID:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("(optional)", text: $displayUUID)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .controlSize(.small)
            }
            .padding(6)

            Divider()

            // Timeline
            List {
                ForEach(engine.log) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.direction.rawValue)
                                .font(.caption2)
                                .foregroundStyle(entry.direction == .sent ? .blue : .green)
                                .fontWeight(.semibold)
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 280)
    }
}
