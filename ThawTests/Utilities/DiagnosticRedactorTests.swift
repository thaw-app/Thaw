//
//  DiagnosticRedactorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The redactor must strip what identifies a person while leaving the
/// identifiers and geometry a maintainer reads a move report for.
@Suite("Diagnostic redactor")
struct DiagnosticRedactorTests {
    @Test("Exact terms are replaced case-insensitively, longest first")
    func exactTerms() {
        let redactor = DiagnosticRedactor(terms: [
            .init("Alvie", placeholder: "<user>"),
            .init("Alvie Stoddard", placeholder: "<user>"),
            .init("HomeNet-5G", placeholder: "<wifi-network>"),
        ])

        let text = "Trigger for alvie stoddard on HomeNet-5G; owner=com.alvie.Helper"

        #expect(redactor.redact(text) == "Trigger for <user> on <wifi-network>; owner=com.<user>.Helper")
    }

    @Test("Short terms redact standalone account names without mangling identifiers")
    func shortTerms() {
        let redactor = DiagnosticRedactor(terms: [.init("li", placeholder: "<user>")])

        #expect(redactor.redact("login=Li; alias li") == "login=<user>; alias <user>")
        #expect(redactor.redact("plist client com.little.Helper") == "plist client com.little.Helper")
    }

    @Test("Patterns catch paths, addresses and coordinates the caller did not know about")
    func patterns() {
        let redactor = DiagnosticRedactor(terms: [])

        #expect(redactor.redact("path=/Users/someone/Library/Logs/Thaw") == "path=/Users/<user>/Library/Logs/Thaw")
        #expect(redactor.redact("mail someone@example.com now") == "mail <email> now")
        #expect(redactor.redact("router 192.168.1.20 up") == "router <ip-address> up")
        #expect(redactor.redact("router fe80::a4b2:31ff:fe7a:9c10 up") == "router <ip-address> up")
        #expect(redactor.redact("router 12:34:56:78:9a:bc:de:f0 up") == "router <ip-address> up")
        #expect(redactor.redact("bt AA:BB:CC:DD:EE:FF paired") == "bt <mac-address> paired")
        #expect(redactor.redact("near 37.774929, -122.419418 (home)") == "near <coordinates> (home)")
    }

    @Test("Labeled network, device, and trigger-like values are removed")
    func labeledSensitiveValues() {
        let redactor = DiagnosticRedactor(terms: [])
        let text = "wifiSSID=\"Home Network\"; deviceName=Alvie AirPods; triggerName=At Work; conditionValue=private"
        let redacted = redactor.redact(text)

        #expect(!redacted.contains("Home Network"))
        #expect(!redacted.contains("Alvie AirPods"))
        #expect(!redacted.contains("At Work"))
        #expect(!redacted.contains("private"))
    }

    @Test("JSON-style quoted field names are removed")
    func jsonQuotedFieldNames() {
        let redactor = DiagnosticRedactor(terms: [])

        // The quoted key and its value are consumed together; the secret
        // never survives, which is what matters.
        #expect(redactor.redact("{\"wifiSSID\":\"Home Network\"}") == "{\"<sensitive-value>}")
        #expect(!redactor.redact("{\"triggerName\":\"Focus 1\"}").contains("Focus 1"))
        // Unquoted forms keep working.
        #expect(redactor.redact("ssid: net") == "<sensitive-value>")
    }

    @Test("Menu bar geometry and identifiers survive redaction")
    func geometry() {
        let redactor = DiagnosticRedactor(
            terms: DiagnosticRedactor.accountTerms(userName: "someone", fullName: "Some Person", homeDirectory: "/Users/someone")
        )

        let line = "Move event geometry: item=<com.example.App:Item-0 (windowID: 1223)> itemBounds=(1425.0, 0.0, 38.0, 33.0) "
            + "pressPoint=(-3733.0, 16.5) minX=-8791.0 elapsed=0.029878973960876465s"

        #expect(redactor.redact(line) == line)
    }

    @Test("Account terms cover the home directory, the login name and the full name")
    func accountTerms() {
        let terms = DiagnosticRedactor.accountTerms(userName: "someone", fullName: "Some Person", homeDirectory: "/Users/someone")

        #expect(terms.contains(.init("/Users/someone", placeholder: "~")))
        #expect(terms.contains(.init("someone", placeholder: "<user>")))
        #expect(terms.contains(.init("Some Person", placeholder: "<user>")))
        #expect(terms.contains(.init("Some", placeholder: "<user>")))
        #expect(terms.contains(.init("Person", placeholder: "<user>")))

        let redactor = DiagnosticRedactor(terms: terms)

        #expect(redactor.redact("/Users/someone/Desktop, by Some Person") == "~/Desktop, by <user>")
    }

    @Test("Short full-name parts use identifier boundaries")
    func shortAccountNameParts() {
        let terms = DiagnosticRedactor.accountTerms(userName: "li", fullName: "Li Bo", homeDirectory: "/Users/li")
        let redactor = DiagnosticRedactor(terms: terms)

        #expect(terms.contains(.init("Li Bo", placeholder: "<user>")))
        #expect(redactor.redact("Owner Li Bo; logins li and bo") == "Owner <user>; logins <user> and <user>")
        #expect(redactor.redact("plist client boiling com.little.Helper") == "plist client boiling com.little.Helper")
    }
}
