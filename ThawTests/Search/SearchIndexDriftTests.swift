//
//  SearchIndexDriftTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Every user-facing stored setting is linked from a SearchEntry or opted out
/// in SearchIndex. Fix a failure there, never by editing these tests.
@MainActor
@Suite("SearchIndex drift guard", .scratchDefaults)
struct SearchIndexDriftTests {
    /// The names of the @Observable-managed stored properties of a settings
    /// model instance.
    ///
    /// @Observable backs each tracked property foo with _foo while ignored
    /// members keep plain names, so reflecting _ names yields exactly the
    /// user-facing surface.
    private func observedPropertyNames(of model: some AnyObject) -> Set<String> {
        var names = Set<String>()
        for child in Mirror(reflecting: model).children {
            guard let label = child.label, label.hasPrefix("_"), !label.hasPrefix("_$") else {
                continue
            }
            names.insert(String(label.dropFirst()))
        }
        return names
    }

    /// One page's model: its name in messages, how a property name becomes
    /// its SettingsProperty, and the stored properties it has.
    private struct Page {
        let name: String
        let property: (String) -> SettingsProperty
        let stored: Set<String>
    }

    /// Every page model the index links into.
    private var pages: [Page] {
        [
            Page(name: "GeneralSettings", property: SettingsProperty.general, stored: observedPropertyNames(of: GeneralSettings())),
            Page(name: "LayoutSettings", property: SettingsProperty.layout, stored: observedPropertyNames(of: LayoutSettings())),
            Page(name: "VisibilitySettings", property: SettingsProperty.visibility, stored: observedPropertyNames(of: VisibilitySettings())),
            Page(name: "ThawBarSettings", property: SettingsProperty.thawBar, stored: observedPropertyNames(of: ThawBarSettings())),
            Page(name: "AppearanceSettings", property: SettingsProperty.appearance, stored: observedPropertyNames(of: AppearanceSettings())),
            Page(name: "SpacesSettings", property: SettingsProperty.spaces, stored: observedPropertyNames(of: SpacesSettings())),
            Page(name: "PrivacySettings", property: SettingsProperty.privacy, stored: observedPropertyNames(of: PrivacySettings())),
            Page(name: "ToolsSettings", property: SettingsProperty.tools, stored: observedPropertyNames(of: ToolsSettings())),
            Page(name: "WidgetsSettings", property: SettingsProperty.widgets, stored: observedPropertyNames(of: WidgetsSettings())),
        ]
    }

    /// Every SettingsProperty a stored property of some page model maps to.
    private var allStoredProperties: Set<SettingsProperty> {
        Set(pages.flatMap { page in page.stored.map(page.property) })
    }

    /// Every property link declared by the current index.
    private var indexedProperties: Set<SettingsProperty> {
        Set(SearchIndex.entries.compactMap(\.property))
    }

    // MARK: - Model → index coverage

    @Test("every page model's stored property is searchable or opted out")
    func pageModelCoverage() {
        let covered = indexedProperties.union(SearchIndex.nonSearchableProperties)
        for page in pages {
            let missing = page.stored.filter { !covered.contains(page.property($0)) }.sorted()
            #expect(
                missing.isEmpty,
                """
                \(page.name) properties with no SearchEntry and no opt-out: \(missing). \
                Add a SearchEntry linking the property, or a commented opt-out in \
                SearchIndex.nonSearchableProperties if deliberately unsearchable.
                """
            )
        }
    }

    // MARK: - Index → model integrity

    @Test("every property link in the index names a real stored property")
    func indexLinksResolveToStoredProperties() {
        let dangling = indexedProperties.subtracting(allStoredProperties)
        #expect(
            dangling.isEmpty,
            """
            SearchEntry.property links that match no stored property (renamed \
            or removed on the model?): \(dangling)
            """
        )
    }

    @Test("opt-outs name real stored properties and never shadow a live entry")
    func optOutsAreConsistent() {
        let stored = allStoredProperties
        for property in SearchIndex.nonSearchableProperties {
            #expect(stored.contains(property), "Stale opt-out for removed property \(property)")
            #expect(
                !indexedProperties.contains(property),
                "\(property) is opted out but also has a SearchEntry, the opt-out is stale"
            )
        }
    }

    // MARK: - Reflection sanity

    @Test("the Mirror enumeration actually sees the models' tracked properties")
    func mirrorEnumerationIsNotEmpty() {
        // Canary: if a toolchain renames the backing stores, the coverage
        // tests would pass vacuously.
        let general = observedPropertyNames(of: GeneralSettings())
        let layout = observedPropertyNames(of: LayoutSettings())
        let visibility = observedPropertyNames(of: VisibilitySettings())

        #expect(general.contains("showThawIcon"))
        #expect(visibility.contains("showOnClick"))
        #expect(layout.contains("enableAlwaysHiddenSection"))
        #expect(visibility.contains("tooltipDelay"))
        #expect(!general.contains("settingsURIChanges"), "@ObservationIgnored members must not count as user-facing")
        #expect(!layout.contains("appState"), "@ObservationIgnored members must not count as user-facing")
    }
}
