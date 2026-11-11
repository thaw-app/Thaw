//
//  SettingsURIHandler+GeneralKeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension SettingsURIHandler {
    /// The General page's keys, merged into keyTable.
    static let generalKeyTable: [String: SettingURIEntry] = [
        "showThawIcon": SettingURIEntry(defaultsKey: .showThawIcon, kind: .boolean, isWritable: true),
        "customThawIconIsTemplate": SettingURIEntry(defaultsKey: .customThawIconIsTemplate, kind: .boolean, isWritable: true),
        "simpleMode": SettingURIEntry(defaultsKey: .simpleMode, kind: .boolean, isWritable: true),
        "showSettingDescriptions": SettingURIEntry(defaultsKey: .showSettingDescriptions, kind: .boolean, isWritable: true),
        "showDockIconWithSettings": SettingURIEntry(defaultsKey: .showDockIconWithSettings, kind: .boolean, isWritable: true),
        "blackSettingsBackground": SettingURIEntry(defaultsKey: .blackSettingsBackground, kind: .boolean, isWritable: true),
        "lockThawBarPosition": SettingURIEntry(defaultsKey: .lockThawBarPosition, kind: .boolean, isWritable: true),
        "openHiddenItemsInMenuBar": SettingURIEntry(defaultsKey: .openHiddenItemsInMenuBar, kind: .boolean, isWritable: true),
        "useThawBarOnNotchOverflow": SettingURIEntry(defaultsKey: .useThawBarOnNotchOverflow, kind: .boolean, isWritable: true),
        "useThawBarOnlyOnNotchedDisplay": SettingURIEntry(defaultsKey: .useThawBarOnlyOnNotchedDisplay, kind: .boolean, isWritable: true),
        "thawBarLocationOnHotkey": SettingURIEntry(defaultsKey: .thawBarLocationOnHotkey, kind: .boolean, isWritable: true),
        "showOnClick": SettingURIEntry(defaultsKey: .showOnClick, kind: .boolean, isWritable: true),
        "showOnHover": SettingURIEntry(defaultsKey: .showOnHover, kind: .boolean, isWritable: true),
        "showOnScroll": SettingURIEntry(defaultsKey: .showOnScroll, kind: .boolean, isWritable: true),
        "autoRehide": SettingURIEntry(defaultsKey: .autoRehide, kind: .boolean, isWritable: true),
        "rehideInterval": SettingURIEntry(defaultsKey: .rehideInterval, kind: .double(min: 1, max: 300), isWritable: true),
        "tempShowInterval": SettingURIEntry(defaultsKey: .tempShowInterval, kind: .double(min: 0, max: 30), isWritable: true),
        "rehideStrategy": SettingURIEntry(defaultsKey: .rehideStrategy, kind: .enumeration, isWritable: true),
        "settingsAppearance": SettingURIEntry(defaultsKey: .settingsAppearance, kind: .enumeration, isWritable: true),
    ]
}
