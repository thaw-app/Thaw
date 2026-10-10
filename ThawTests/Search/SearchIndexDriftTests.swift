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
@Suite("SearchIndex drift guard")
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

    /// Every property link declared by the current index.
    private var indexedProperties: Set<SettingsProperty> {
        Set(SearchIndex.entries.compactMap(\.property))
    }

    // MARK: - Model → index coverage

    @Test("every GeneralSettings stored property is searchable or opted out")
    func generalSettingsCoverage() {
        let covered = indexedProperties.union(SearchIndex.nonSearchableProperties)
        let missing = observedPropertyNames(of: GeneralSettings())
            .filter { !covered.contains(.general($0)) }
            .sorted()

        #expect(
            missing.isEmpty,
            """
            GeneralSettings properties with no SearchEntry and no opt-out: \(missing). \
            Add a SearchEntry with `property: .general(...)`, or a commented \
            opt-out in SearchIndex.nonSearchableProperties if deliberately unsearchable.
            """
        )
    }

    @Test("every AdvancedSettings stored property is searchable or opted out")
    func advancedSettingsCoverage() {
        let covered = indexedProperties.union(SearchIndex.nonSearchableProperties)
        let missing = observedPropertyNames(of: AdvancedSettings())
            .filter { !covered.contains(.advanced($0)) }
            .sorted()

        #expect(
            missing.isEmpty,
            """
            AdvancedSettings properties with no SearchEntry and no opt-out: \(missing). \
            Add a SearchEntry with `property: .advanced(...)`, or a commented \
            opt-out in SearchIndex.nonSearchableProperties if deliberately unsearchable.
            """
        )
    }

    // MARK: - Index → model integrity

    @Test("every property link in the index names a real stored property")
    func indexLinksResolveToStoredProperties() {
        let general = observedPropertyNames(of: GeneralSettings())
        let advanced = observedPropertyNames(of: AdvancedSettings())

        let dangling = indexedProperties.filter { property in
            switch property {
            case let .general(name): !general.contains(name)
            case let .advanced(name): !advanced.contains(name)
            }
        }

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
        let general = observedPropertyNames(of: GeneralSettings())
        let advanced = observedPropertyNames(of: AdvancedSettings())

        for property in SearchIndex.nonSearchableProperties {
            switch property {
            case let .general(name):
                #expect(general.contains(name), "Stale opt-out for removed property .general(\(name))")
            case let .advanced(name):
                #expect(advanced.contains(name), "Stale opt-out for removed property .advanced(\(name))")
            }
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
        let advanced = observedPropertyNames(of: AdvancedSettings())

        #expect(general.contains("showThawIcon"))
        #expect(general.contains("showOnClick"))
        #expect(advanced.contains("enableAlwaysHiddenSection"))
        #expect(advanced.contains("tooltipDelay"))
        #expect(!general.contains("cancellables"), "@ObservationIgnored members must not count as user-facing")
        #expect(!advanced.contains("appState"), "@ObservationIgnored members must not count as user-facing")
    }
}
