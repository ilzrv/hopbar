import Foundation
@testable import Hopbar
import XCTest

final class ConfigStoreTests: XCTestCase {
    func testDecodesValidConfigAndPreservesOrder() throws {
        let config = """
        {
          "terminal": "iterm",
          "open": "tab",
          "items": [
            { "title": "First", "command": "ssh first" },
            { "title": "Docs", "url": "https://example.com" },
            {
              "title": "Group",
              "items": [
                { "title": "Nested", "command": "echo nested", "open": "window" }
              ]
            }
          ]
        }
        """

        let model = try load(config)

        XCTAssertEqual(model.entries.map(\.title), ["First", "Docs", "Group"])
        XCTAssertEqual(model.entries[0].kind, .command("ssh first", terminal: .iterm, open: .tab))
        XCTAssertEqual(model.entries[1].kind, .url(URL(string: "https://example.com")!))

        guard case .group(let nested) = model.entries[2].kind else {
            return XCTFail("Expected group entry.")
        }
        XCTAssertEqual(nested[0].kind, .command("echo nested", terminal: .iterm, open: .window))
    }

    func testDefaultsToITermAndTab() throws {
        let config = """
        {
          "items": [
            { "title": "Default Command", "command": "pwd" }
          ]
        }
        """

        let model = try load(config)

        XCTAssertEqual(model.entries[0].kind, .command("pwd", terminal: .iterm, open: .tab))
    }

    func testAllowsPerItemTerminalOverride() throws {
        let config = """
        {
          "terminal": "iterm",
          "open": "tab",
          "items": [
            { "title": "Terminal Command", "command": "top", "terminal": "terminal", "open": "current" }
          ]
        }
        """

        let model = try load(config)

        XCTAssertEqual(model.entries[0].kind, .command("top", terminal: .terminal, open: .current))
    }

    func testAllowsGhosttyTerminal() throws {
        let config = """
        {
          "terminal": "ghostty",
          "open": "window",
          "items": [
            { "title": "Ghostty Command", "command": "pwd" }
          ]
        }
        """

        let model = try load(config)

        XCTAssertEqual(model.entries[0].kind, .command("pwd", terminal: .ghostty, open: .window))
    }

    func testGroupTerminalAndOpenApplyToChildren() throws {
        let config = """
        {
          "terminal": "iterm",
          "open": "tab",
          "items": [
            {
              "title": "Terminal Group",
              "terminal": "terminal",
              "open": "window",
              "items": [
                { "title": "Child", "command": "uptime" }
              ]
            }
          ]
        }
        """

        let model = try load(config)

        guard case .group(let children) = model.entries[0].kind else {
            return XCTFail("Expected group entry.")
        }
        XCTAssertEqual(children[0].kind, .command("uptime", terminal: .terminal, open: .window))
    }

    func testRejectsInvalidJSON() throws {
        let store = try makeStore(contents: "{")

        guard case .failure(.invalidJSON) = store.load() else {
            return XCTFail("Expected invalid JSON failure.")
        }
    }

    func testRejectsInvalidEnumValue() throws {
        let config = """
        {
          "terminal": "warp",
          "items": [
            { "title": "Command", "command": "pwd" }
          ]
        }
        """

        let store = try makeStore(contents: config)

        guard case .failure(.invalidJSON(let message)) = store.load() else {
            return XCTFail("Expected invalid JSON failure.")
        }
        XCTAssertTrue(message.contains("Invalid terminal"))
    }

    func testRejectsItemWithCommandAndItems() throws {
        let config = """
        {
          "items": [
            { "title": "Bad", "command": "pwd", "items": [] }
          ]
        }
        """

        let store = try makeStore(contents: config)

        guard case .failure(.validation(let message)) = store.load() else {
            return XCTFail("Expected validation failure.")
        }
        XCTAssertTrue(message.contains("exactly one"))
    }

    func testRejectsDuplicateTitlesInSameGroup() throws {
        let config = """
        {
          "items": [
            { "title": "Dup", "command": "pwd" },
            { "title": "dup", "command": "ls" }
          ]
        }
        """

        let store = try makeStore(contents: config)

        guard case .failure(.validation(let message)) = store.load() else {
            return XCTFail("Expected validation failure.")
        }
        XCTAssertTrue(message.contains("Duplicate"))
    }

    func testCreatesDefaultConfigWhenMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent(".hopbar.json")
        let store = ConfigStore(configURL: url, defaultConfigContents: #"{"items":[]}"#)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        guard case .success = store.ensureConfigExists() else {
            return XCTFail("Expected default config creation to succeed.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func load(_ contents: String) throws -> MenuModel {
        let store = try makeStore(contents: contents)
        switch store.load() {
        case .success(let model):
            return model
        case .failure(let error):
            XCTFail("Expected config to load successfully, got: \(error)")
            throw error
        }
    }

    private func makeStore(contents: String) throws -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(".hopbar.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return ConfigStore(configURL: url)
    }
}
