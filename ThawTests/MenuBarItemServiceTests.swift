//
//  MenuBarItemServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - MenuBarItemService Tests

@Suite("Menu bar item service")
struct MenuBarItemServiceTests {
    // MARK: - Service Name

    @Test("The service name is the reverse-DNS Mach service identifier")
    func serviceName() {
        #expect(MenuBarItemService.name == "com.stonerl.Thaw.MenuBarItemService")
    }

    // MARK: - Request Tests

    @Suite("Request")
    struct MenuBarItemServiceRequestTests {
        // MARK: - Start Request

        @Test("A start request encodes to JSON naming the case")
        func startRequestEncode() throws {
            let request = MenuBarItemService.Request.start
            let encoder = JSONEncoder()
            let data = try encoder.encode(request)
            let json = try #require(String(data: data, encoding: .utf8))

            #expect(json.contains("start"))
        }

        @Test("A start request decodes from its JSON form")
        func startRequestDecode() throws {
            let json = #"{"start":{}}"#
            let data = try #require(json.data(using: .utf8))
            let decoder = JSONDecoder()

            let request = try decoder.decode(MenuBarItemService.Request.self, from: data)

            guard case .start = request else {
                Issue.record("Expected .start request")
                return
            }
        }

        @Test("A start request survives a round trip")
        func startRequestRoundTrip() throws {
            let original = MenuBarItemService.Request.start
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarItemService.Request.self, from: data)

            guard case .start = decoded else {
                Issue.record("Expected .start request after round trip")
                return
            }
        }

        // MARK: - SourcePID Request

        @Test("A sourcePID request keeps its window info across a round trip")
        func sourcePIDRequestRoundTrip() throws {
            // Create a WindowInfo manually for testing
            let windowInfo = try createTestWindowInfo()
            let original = MenuBarItemService.Request.sourcePID(windowInfo)

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarItemService.Request.self, from: data)

            guard case let .sourcePID(decodedWindow) = decoded else {
                Issue.record("Expected .sourcePID request after round trip")
                return
            }
            #expect(decodedWindow.windowID == windowInfo.windowID)
            #expect(decodedWindow.ownerPID == windowInfo.ownerPID)
        }

        // MARK: - Helper

        private func createTestWindowInfo() throws -> WindowInfo {
            // CGRect encodes as nested arrays: [[x,y],[width,height]]
            let json = """
            {
                "windowID": 12345,
                "ownerPID": 1000,
                "bounds": [[0, 0], [100, 22]],
                "layer": 25,
                "title": "TestItem",
                "ownerName": "TestApp",
                "isOnScreen": true
            }
            """
            let data = try #require(json.data(using: .utf8))
            return try JSONDecoder().decode(WindowInfo.self, from: data)
        }
    }

    // MARK: - Response Tests

    @Suite("Response")
    struct MenuBarItemServiceResponseTests {
        // MARK: - Start Response

        @Test("A start response encodes to JSON naming the case")
        func startResponseEncode() throws {
            let response = MenuBarItemService.Response.start
            let encoder = JSONEncoder()
            let data = try encoder.encode(response)
            let json = try #require(String(data: data, encoding: .utf8))

            #expect(json.contains("start"))
        }

        @Test("A start response survives a round trip")
        func startResponseRoundTrip() throws {
            let original = MenuBarItemService.Response.start
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarItemService.Response.self, from: data)

            guard case .start = decoded else {
                Issue.record("Expected .start response after round trip")
                return
            }
        }

        // MARK: - SourcePID Response

        @Test("A sourcePID response keeps its pid across a round trip")
        func sourcePIDResponseWithPID() throws {
            let original = MenuBarItemService.Response.sourcePID(1234)
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarItemService.Response.self, from: data)

            guard case let .sourcePID(pid) = decoded else {
                Issue.record("Expected .sourcePID response")
                return
            }
            #expect(pid == 1234)
        }

        @Test("A sourcePID response keeps a nil pid across a round trip")
        func sourcePIDResponseWithNil() throws {
            let original = MenuBarItemService.Response.sourcePID(nil)
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarItemService.Response.self, from: data)

            guard case let .sourcePID(pid) = decoded else {
                Issue.record("Expected .sourcePID response with nil")
                return
            }
            #expect(pid == nil)
        }

        @Test("A sourcePID response encodes both the case name and the pid")
        func sourcePIDResponseEncodesCorrectly() throws {
            let response = MenuBarItemService.Response.sourcePID(5678)
            let encoder = JSONEncoder()
            let data = try encoder.encode(response)
            let json = try #require(String(data: data, encoding: .utf8))

            #expect(json.contains("sourcePID"))
            #expect(json.contains("5678"))
        }
    }
}
