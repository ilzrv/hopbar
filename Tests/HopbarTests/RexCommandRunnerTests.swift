import Foundation
@testable import Hopbar
import XCTest

@MainActor
final class RexCommandRunnerTests: XCTestCase {
    func testRexCLIPreservesCommandAsJSONOnStandardInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cli = directory.appendingPathComponent("Rex CLI")
        try #"""
        #!/bin/sh
        [ "$#" -eq 5 ] && [ "$1" = do ] && [ "$2" = -e ] && [ "$4" = --args ] && [ "$5" = - ] || exit 1
        /bin/cat > "$0.json"
        """#.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let command = "printf '%s' \"$HOME\"; echo \\path\n# Привет\r\t"
        for mode in OpenMode.allCases {
            try CommandRunner.runRexCLI(at: cli, command: command, open: mode)
            let data = try Data(contentsOf: cli.appendingPathExtension("json"))
            let arguments = try JSONDecoder().decode([String: String].self, from: data)
            XCTAssertEqual(arguments, ["command": command, "open": mode.rawValue])
        }
    }

    func testRexTabCreatesShellWithCommandInAttachedSession() throws {
        try runProgram(mode: .tab, assertions: #"""
        assert(#createdWindows == 1 and #createdSessions == 0)
        assert(createdWindows[1].session_id == "session:attached")
        assert(createdWindows[1].layout.block.options == nil)
        assert(#writes == 1 and writes[1].block_id == "block:new-tab")
        assert(writes[1].args.data == rex.args.command .. "\r")
        assert(attachedSessions["session:attached"])
        assert(actions[#actions].args.window_id == "window:new")
        """#)
    }

    func testRexCurrentUsesFocusedPaneOfActiveTab() throws {
        try runProgram(mode: .current, assertions: #"""
        assert(#createdWindows == 0 and #createdSessions == 0 and #writes == 1)
        assert(writes[1].session_id == "session:attached")
        assert(writes[1].block_id == "block:focused")
        assert(writes[1].args.data == rex.args.command .. "\r")
        assert(attachedSessions["session:attached"])
        """#)
    }

    func testRexWindowCreatesAndDisplaysNewSession() throws {
        try runProgram(mode: .window, assertions: #"""
        assert(actions[1].action == "client.window.new")
        assert(appWindowsCreated == 1)
        assert(#createdSessions == 0 and #createdWindows == 0 and #writes == 1)
        assert(writes[1].session_id == "session:app" and writes[1].block_id == "block:app")
        assert(writes[1].args.data == rex.args.command .. "\r")
        assert(attachedSessions["session:app"])
        """#)
    }

    func testRexCurrentCreatesTabWhenSessionHasNoFocusedPane() throws {
        try runProgram(mode: .current, setup: "view = { windows = {} }", assertions: "assert(#createdWindows == 1 and #writes == 1)")
    }

    func testRexCurrentUsesFreshTabIfFocusedBlockIsNotATerminal() throws {
        try runProgram(mode: .current, setup: "focusedBlock.creator_name = 'other'", assertions: #"""
        assert(#createdWindows == 1 and #writes == 1 and writes[1].block_id == "block:new-tab")
        """#)
    }

    func testRexDoesNotSubmitCommandIfNewTabCannotBeSelected() throws {
        try runProgram(mode: .tab, setup: "refuseNewTabSelection = true", assertions: #"""
        assert(not ok and string.find(err, "selection failed", 1, true))
        assert(#createdWindows == 1 and #writes == 0 and createdWindows[1].layout.block.options == nil)
        """#, expectsSuccess: false)
    }

    func testRexCreatesSessionWhenNoneExist() throws {
        try runProgram(mode: .tab, setup: "client.session_ids = {}; serverSessions = {}", assertions: "assert(appWindowsCreated == 1 and #writes == 1)")
    }

    func testRexCreatesDedicatedSessionWhenAttachedSessionsAreAmbiguous() throws {
        try runProgram(mode: .current, setup: #"""
        client.session_ids = { "session:one", "session:two" }
        serverSessions = { { session_id = "session:one" }, { session_id = "session:two" } }
        """#, assertions: #"""
        assert(#createdSessions == 1 and #writes == 1 and #createdWindows == 0)
        assert(writes[1].block_id == "block:new-session")
        assert(createdSessions[1].label == "Hopbar")
        assert(actions[1].action == "client.update.status")
        assert(actions[2].args.session_id == "session:new")
        """#)
    }

    func testRexReusesDedicatedSessionWhenAttachedSessionsAreAmbiguous() throws {
        try runProgram(mode: .tab, setup: #"""
        client.session_ids = { "session:one", "session:hopbar" }
        serverSessions = { { session_id = "session:one" }, { session_id = "session:hopbar", label = "Hopbar" } }
        """#, assertions: #"""
        assert(#createdSessions == 0 and #createdWindows == 1)
        assert(createdWindows[1].session_id == "session:hopbar")
        """#)
    }

    func testRexRefusalPropagatesBeforeExecutingCommand() throws {
        for mode in OpenMode.allCases {
            try runProgram(mode: mode, setup: "refuseActions = true", assertions: #"""
            assert(not ok and string.find(err, "Remote Control", 1, true))
            assert(#writes == 0 and #createdWindows == 0 and #createdSessions == 0)
            assert(#reopens == 0)
            """#, expectsSuccess: false)
        }
    }

    func testRexReopensAppBeforeRunningCommandWhenNoAppWindowExists() throws {
        for mode in OpenMode.allCases {
            try runProgram(mode: mode, setup: "noAppWindow = true; windowReadyAfter = 3", assertions: #"""
            assert(#reopens == 1 and sleeps == 3, "reopens=" .. #reopens .. ", sleeps=" .. sleeps)
            assert(reopens[1][1] == "/usr/bin/open" and reopens[1][2] == "-b")
            assert(reopens[1][3] == "com.superlogical.rex")
            assert(#writes == 1)
            """#)
        }
    }

    func testRexStopsWithoutExecutingCommandWhenWindowCannotReopen() throws {
        try runProgram(mode: .tab, setup: "noAppWindow = true; windowReadyAfter = 100", assertions: #"""
        assert(not ok and string.find(err, "has no window to act in", 1, true))
        assert(#reopens == 1 and sleeps <= 30)
        assert(#writes == 0 and #createdWindows == 0 and #createdSessions == 0)
        """#, expectsSuccess: false)
    }

    func testRexWindowReusesWindowCreatedDuringColdLaunch() throws {
        try runProgram(mode: .window, setup: "localAppConnected = false; noAppWindow = true; windowReadyAfter = 3; client.session_ids = {}; serverSessions = {}", assertions: #"""
        assert(#reopens == 1 and appWindowsCreated == 1)
        assert(#actions == 1 and actions[1].action == "client.update.status")
        assert(#createdSessions == 0 and #createdWindows == 0)
        assert(#writes == 1 and writes[1].session_id == "session:app")
        """#)
    }

    func testRexWindowDoesNotWriteIntoRestoredTerminal() throws {
        try runProgram(mode: .window, setup: "localAppConnected = false; noAppWindow = true; windowReadyAfter = 1; restoreExistingWindow = true", assertions: #"""
        assert(#reopens == 1 and appWindowsCreated == 0)
        assert(#writes == 1 and writes[1].block_id == "block:new-tab")
        assert(#createdWindows == 1 and #createdSessions == 0)
        assert(createdWindows[1].session_id == "session:attached")
        """#)
    }

    func testRexCurrentDoesNotWriteIntoRestoredTerminal() throws {
        try runProgram(mode: .current, setup: "localAppConnected = false; noAppWindow = true; windowReadyAfter = 1; restoreExistingWindow = true", assertions: #"""
        assert(#writes == 1 and writes[1].block_id == "block:new-tab")
        assert(#createdWindows == 1 and createdWindows[1].session_id == "session:attached")
        """#)
    }

    func testRexWindowIgnoresUnattachedSessionsAndWaitsForAppOwnership() throws {
        try runProgram(mode: .window, setup: "unrelatedSession = true; appOwnerReadyAfter = 2", assertions: #"""
        assert(sleeps == 2 and #writes == 1 and writes[1].session_id == "session:app")
        """#)
    }

    func testRexWindowStopsWhenTwoNewAppSessionsAreVisible() throws {
        try runProgram(mode: .window, setup: "secondAppSession = true", assertions: #"""
        assert(not ok and string.find(err, "more than one session", 1, true))
        assert(#writes == 0)
        """#, expectsSuccess: false)
    }

    private func runProgram(
        mode: OpenMode,
        setup: String = "",
        assertions: String,
        expectsSuccess: Bool = true
    ) throws {
        let executable = ["/opt/homebrew/bin/lua", "/usr/local/bin/lua", "/usr/bin/lua"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        let luaURL = try XCTUnwrap(executable, "Install Lua to run the Rex tests (brew install lua).")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("rex-test.lua")
        let source = Self.fakeAPI + "\nrex.args.open = '\(mode.rawValue)'\n" + setup
            + "\nlocal ok, err = pcall(function()\n" + CommandRunner.rexProgram + "\nend)\n"
            + (expectsSuccess ? "assert(ok, err)\n" : "") + assertions
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: luaURL)
        process.arguments = [sourceURL.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
    }

    private static let fakeAPI = #"""
    local actions, writes, createdWindows, createdSessions = {}, {}, {}, {}
    local refuseActions = false
    local refuseNewTabSelection = false
    local noAppWindow, windowReadyAfter, sleeps = false, 0, 0
    local reopens = {}
    local attachedSessions = {}
    local appWindowsCreated = 0
    local localAppConnected = true
    local restoreExistingWindow, unrelatedSession, appOwnerReadyAfter, secondAppSession = false, false, 0, false
    local client = {
      client_id = "client:local", info = { kind = "app", platform = "macos" },
      principal = { transport = "unix" }, session_ids = { "session:attached" }
    }
    local serverSessions = { { session_id = "session:other" }, { session_id = "session:attached" } }
    local focusedBlock = { block_id = "block:focused", creator_name = "com.superlogical.terminal", owner = "client:local" }
    local view = { active_window_id = "window:active", windows = {
      { window_id = "window:other", focused_block_id = "block:other" },
      { window_id = "window:active", focused_block_id = "block:focused", layers = { { blocks = { focusedBlock } } } }
    } }
    local function appWindow()
      appWindowsCreated = appWindowsCreated + 1
      table.insert(serverSessions, { session_id = "session:app" })
      table.insert(client.session_ids, "session:app")
    end
    rex = {
      args = { command = "echo '$HOME'; printf '%s' \"Привет\"\necho done" },
      sleep = function()
        sleeps = sleeps + 1
        if noAppWindow and #reopens > 0 and sleeps >= windowReadyAfter then
          noAppWindow = false
          localAppConnected = true
          if not restoreExistingWindow then appWindow() end
        end
      end,
      exec = function(argv)
        table.insert(reopens, argv)
        return { ok = true, code = 0 }
      end,
      layout = { block = function(options) return { block = options } end },
      session = { attach = function(args) return rex.call("session.attach", args) end },
      call = function(method, args)
        if method == "client.list" then return { clients = localAppConnected and { client } or {} } end
        if method == "session.list" then
          local copy = {}
          for i, session in ipairs(serverSessions) do copy[i] = session end
          return { sessions = copy }
        end
        if method == "session.attach" then
          attachedSessions[args.session_id] = true
          if args.session_id == "session:app" then
            return { view = { active_window_id = "window:app", windows = { {
              window_id = "window:app", focused_block_id = "block:app", layers = { { blocks = { {
                block_id = "block:app", flavor = "com.superlogical.terminal.shell",
                owner = sleeps >= appOwnerReadyAfter and "client:local" or "client:other"
              } } } }
            } } } }
          end
          return { client_id = "client:script", view = view }
        end
        if args and args.session_id and method ~= "session.create" and method ~= "client.perform"
            and not attachedSessions[args.session_id] then
          return nil, 'stream is not attached to session ' .. args.session_id .. ' (status=409 code=conflict)'
        end
        if method == "client.perform" then
          assert(args.client_id == "client:local")
          if refuseActions then return nil, "Turn on Remote Control in Settings under Rex Server." end
          if refuseNewTabSelection and args.action == "session.select" and args.args.window_id == "window:new" then
            return nil, "selection failed"
          end
          if noAppWindow then return nil, 'stream response "control-2" failed: Rex Beta has no window to act in. (status=400 code=not_supported)' end
          table.insert(actions, args)
          if args.action == "client.window.new" then
            if unrelatedSession then table.insert(serverSessions, { session_id = "session:unrelated" }) end
            appWindow()
            if secondAppSession then table.insert(client.session_ids, "session:second") end
          end
          return { performed_by = args.client_id }
        end
        if method == "session.create" then
          table.insert(createdSessions, args)
          return { session_id = "session:new", initial_windows = { { window_id = "window:new", block_ids = { "block:new-session" } } } }
        end
        if method == "session.new_window" then
          table.insert(createdWindows, args)
          return { window_id = "window:new", block_ids = { "block:new-tab" } }
        end
        if method == "com.superlogical.terminal.write" then table.insert(writes, args); return {} end
        error("Unexpected method: " .. method)
      end
    }
    """#
}
