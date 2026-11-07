import AppKit
import Foundation

enum MenuAction: Equatable {
    case openURL(URL)
    case runCommand(String, terminal: TerminalPreference, open: OpenMode)

    var usesRex: Bool {
        if case .runCommand(_, .rex, _) = self { return true }
        return false
    }
}

@MainActor
protocol CommandRunning {
    func run(_ action: MenuAction) async throws
}

protocol AppleScriptExecuting {
    func execute(_ source: String) throws
}

struct AppleScriptExecutionError: Error, Equatable, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

private struct RexCommandError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

struct NSAppleScriptExecutor: AppleScriptExecuting {
    func execute(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptExecutionError(message: "Could not create AppleScript.")
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript execution failed."
            throw AppleScriptExecutionError(message: message)
        }
    }
}

@MainActor
protocol URLOpening {
    func open(_ url: URL)
}

@MainActor
struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class CommandRunner: CommandRunning {
    private let scriptExecutor: AppleScriptExecuting
    private let urlOpener: URLOpening

    init(
        scriptExecutor: AppleScriptExecuting = NSAppleScriptExecutor(),
        urlOpener: URLOpening = WorkspaceURLOpener()
    ) {
        self.scriptExecutor = scriptExecutor
        self.urlOpener = urlOpener
    }

    func run(_ action: MenuAction) async throws {
        switch action {
        case .openURL(let url):
            urlOpener.open(url)
        case .runCommand(let command, .rex, let open):
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.rexBundleID) else {
                throw RexCommandError(message: "Rex is not installed.")
            }
            let cli = appURL.appendingPathComponent("Contents/Helpers/Rex Server.rex/Contents/MacOS/rex")
            try await Task.detached(priority: .userInitiated) {
                try Self.runRexCLI(at: cli, command: command, open: open)
            }.value
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.rexBundleID)
            if running.count == 1 { running[0].activate(options: []) }
        case .runCommand(let command, let terminal, let open):
            try scriptExecutor.execute(Self.script(command: command, terminal: terminal, open: open))
        }
    }

    static func script(command: String, terminal: TerminalPreference, open: OpenMode) -> String {
        switch terminal {
        case .iterm:
            return itermScript(command: command, open: open)
        case .terminal:
            return terminalScript(command: command, open: open)
        case .ghostty:
            return ghosttyScript(command: command, open: open)
        case .rex:
            preconditionFailure("Rex uses its bundled CLI")
        }
    }

    private static let rexBundleID = "com.superlogical.rex"

    nonisolated static func runRexCLI(at cli: URL, command: String, open: OpenMode) throws {
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw RexCommandError(message: "The installed Rex app does not include its command-line tool.")
        }
        let arguments = try JSONEncoder().encode(["command": command, "open": open.rawValue])
        let input = try rexInput(arguments)
        defer { try? input.close() }
        let process = Process()
        let output = Pipe()
        process.executableURL = cli
        process.arguments = ["do", "-e", rexProgram, "--args", "-"]
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("REX_") }
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = output
        try process.run()
        let deadline = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(30), execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            throw RexCommandError(message: "Rex CLI stopped before confirming the command. Check Rex before retrying.")
        }
        if process.terminationStatus != 0 {
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw RexCommandError(message: message.isEmpty ? "Rex CLI exited with status \(process.terminationStatus)." : message)
        }
    }

    nonisolated private static func rexInput(_ data: Data) throws -> FileHandle {
        // Use an unlinked file so arguments never appear in argv and even large inputs cannot block a pipe.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hopbar-rex.XXXXXX")
        var path = Array(url.path.utf8CString)
        let descriptor = mkstemp(&path)
        guard descriptor >= 0 else { throw RexCommandError(message: "Could not prepare Rex CLI input.") }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard unlink(path) == 0 else { throw RexCommandError(message: "Could not secure Rex CLI input.") }
        try input.write(contentsOf: data)
        try input.seek(toOffset: 0)
        return input
    }

    // Rex calls tabs "windows". Keep commands as JSON data, separate from the Lua program.
    nonisolated static let rexProgram = #"""
    local function call(method, args)
      local result, err = rex.call(method, args)
      if not result then error(err or (method .. " failed")) end
      return result
    end

    local client
    local launchedApp = false
    local sessionsBeforeLaunch
    for attempt = 1, 20 do
      for _, candidate in ipairs(call("client.list").clients or {}) do
        local info = candidate.info or {}
        local principal = candidate.principal or {}
        if info.kind == "app" and info.platform == "macos" and principal.transport == "unix"
            and candidate.connection_state ~= "lost" then
          if client then error("More than one local Rex app is connected. Keep one app connected and try again.") end
          client = candidate
        end
      end
      if client then break end
      if not launchedApp then
        sessionsBeforeLaunch = call("session.list").sessions or {}
        local opened, err = rex.exec({ "/usr/bin/open", "-b", "com.superlogical.rex" }, { timeout = 5 })
        if not opened or not opened.ok then error(err or "Could not open Rex.") end
        launchedApp = true
      end
      rex.sleep(0.1)
    end
    if not client then error("Rex is not connected to its local server. Open Rex and try again.") end

    local appOpenRequested = launchedApp
    local function perform(action, args)
      local request = { client_id = client.client_id, action = action, args = args }
      local result, err = rex.call("client.perform", request)
      local function missingWindow(message)
        return message and string.find(message, "has no window to act in", 1, true)
            and string.find(message, "code=not_supported", 1, true)
      end
      if not result and missingWindow(err) then
        -- Activation alone doesn't reopen a closed app window. Ask Launch Services to reopen it.
        if not appOpenRequested then
          local opened, openError = rex.exec({ "/usr/bin/open", "-b", "com.superlogical.rex" }, { timeout = 5 })
          if not opened or not opened.ok then
            error(openError or (opened and opened.stderr) or "Could not reopen Rex.")
          end
          appOpenRequested = true
        end
        -- Reopening an app without windows already creates its first window.
        if action == "client.window.new" then return { reopened = true } end
        -- Repeat only an explicitly rejected action; never repeat terminal input or session creation.
        for attempt = 1, 30 do
          rex.sleep(0.1)
          result, err = rex.call("client.perform", request)
          if result or not missingWindow(err) then break end
        end
      end
      if not result then error(err or (action .. " failed")) end
      return result
    end

    local layout = rex.layout.block { flavor = "com.superlogical.terminal.shell" }

    local function sendCommand(sessionID, blockID)
      if not blockID then error("Rex did not return a terminal for the command.") end
      local result, err = rex.call("com.superlogical.terminal.write", {
        session_id = sessionID, block_id = blockID, args = { data = rex.args.command .. "\r" }
      })
      if not result then error("Rex did not confirm delivery. Check the terminal before retrying. " .. (err or "")) end
    end

    local function attachSession(sessionID)
      local attached, err = rex.session.attach({ session_id = sessionID })
      if not attached then error(err or "Could not attach to the Rex session.") end
      return attached.view
    end

    local function createSession(label)
      local created = call("session.create", { label = label, initial_windows = { { layout = layout } } })
      attachSession(created.session_id)
      local tab = created.initial_windows[1]
      perform("session.select", { session_id = created.session_id, window_id = tab.window_id })
      sendCommand(created.session_id, (tab.block_ids or {})[1])
    end

    local function createTab(sessionID)
      local created = call("session.new_window", { session_id = sessionID, layout = layout })
      perform("session.select", { session_id = sessionID, window_id = created.window_id })
      sendCommand(sessionID, (created.block_ids or {})[1])
    end

    local function newSession()
      local before = {}
      for _, session in ipairs(sessionsBeforeLaunch or call("session.list").sessions or {}) do
        before[session.session_id] = true
      end
      local reusedAppWindow = launchedApp
      if not launchedApp then reusedAppWindow = perform("client.window.new").reopened end
      local attemptedAfterLaunch = false
      -- New Window creates a session and a shell itself. Only type into a new shell owned by this app.
      for attempt = 1, 30 do
        local target, attached
        for _, connected in ipairs(call("client.list").clients or {}) do
          if connected.client_id == client.client_id and connected.connection_state ~= "lost" then
            attached = connected.session_ids or {}
            for _, sessionID in ipairs(attached) do
              if not before[sessionID] then
                if target then error("Rex opened more than one session; no command was sent.") end
                target = sessionID
              end
            end
            break
          end
        end
        if target then
          local view = attachSession(target)
          local windows = view.windows or {}
          local window = windows[1]
          if #windows == 1 and window.window_id == view.active_window_id then
            local layers = window.layers or {}
            local blocks = #layers == 1 and layers[1].blocks or {}
            local block = blocks[1]
            if #blocks == 1 and block.block_id == window.focused_block_id
                and block.flavor == "com.superlogical.terminal.shell" and block.owner == client.client_id then
              if reusedAppWindow then perform("client.update.status") end
              sendCommand(target, block.block_id)
              return
            end
          end
        end
        -- On reopen Rex can restore a previous window. Never type into its existing terminal.
        if not target and reusedAppWindow and attached and #attached == 1 and attempt == 30 then
          local restoredID = attached[1]
          perform("session.select", { session_id = restoredID })
          attachSession(restoredID)
          createTab(restoredID)
          return
        end
        if not target and reusedAppWindow and not attemptedAfterLaunch and attempt == 15
            and attached and #attached ~= 1 then
          -- Rex may launch without a workspace, or restore several. Request one new window
          -- only after giving startup time to attach its windows.
          attemptedAfterLaunch = true
          reusedAppWindow = perform("client.window.new").reopened
        end
        rex.sleep(0.1)
      end
      error("Rex did not provide a single new terminal. Open a Rex window and try again; no command was sent.")
    end

    if rex.args.open == "window" then
      newSession()
      return
    end

    local sessions = client.session_ids or {}
    if launchedApp and #sessions == 0 then
      -- The app can connect before its window attaches. Do not target a detached session on startup.
      newSession()
      return
    end
    local sessionID
    if #sessions == 1 then
      sessionID = sessions[1]
    else
      local sessionsOnServer = call("session.list").sessions or {}
      if #sessionsOnServer == 0 then
        newSession()
        return
      end
      if #sessionsOnServer == 1 then sessionID = sessionsOnServer[1].session_id end
      if not sessionID then
        for _, session in ipairs(sessionsOnServer) do
          local attachedToApp = false
          for _, attachedID in ipairs(sessions) do
            if attachedID == session.session_id then attachedToApp = true; break end
          end
          if session.label == "Hopbar" and attachedToApp then
            if sessionID then error("More than one Rex session is named Hopbar. Rename one and try again.") end
            sessionID = session.session_id
          end
        end
        if not sessionID then
          -- A read-only client action checks Remote Control without changing an existing session.
          perform("client.update.status")
          createSession("Hopbar")
          return
        end
      end
    end

    -- This also checks Remote Control before sending any terminal input.
    perform("session.select", { session_id = sessionID })
    local view = attachSession(sessionID)
    if rex.args.open == "current" and not launchedApp and not appOpenRequested and #sessions == 1 then
      for _, window in ipairs(view.windows or {}) do
        if window.window_id == view.active_window_id and window.focused_block_id then
          for _, layer in ipairs(window.layers or {}) do
            for _, block in ipairs(layer.blocks or {}) do
              if block.block_id == window.focused_block_id and block.creator_name == "com.superlogical.terminal"
                  and block.owner == client.client_id then
                sendCommand(sessionID, block.block_id)
                return
              end
            end
          end
        end
      end
    end
    createTab(sessionID)
    """#

    private static func itermScript(command: String, open: OpenMode) -> String {
        let command = command.appleScriptLiteral

        switch open {
        case .window:
            return """
            tell application "iTerm"
              activate
              create window with default profile
              tell current session of current window
                write text "\(command)"
              end tell
            end tell
            """
        case .tab:
            return """
            tell application "iTerm"
              activate
              if (count of windows) is 0 then
                create window with default profile
              else
                tell current window
                  create tab with default profile
                end tell
              end if
              tell current session of current window
                write text "\(command)"
              end tell
            end tell
            """
        case .current:
            return """
            tell application "iTerm"
              activate
              if (count of windows) is 0 then
                create window with default profile
              end if
              tell current session of current window
                write text "\(command)"
              end tell
            end tell
            """
        }
    }

    private static func terminalScript(command: String, open: OpenMode) -> String {
        let command = command.appleScriptLiteral

        switch open {
        case .window:
            return """
            tell application "Terminal"
              activate
              do script "\(command)"
            end tell
            """
        case .tab:
            return """
            tell application "Terminal"
              activate
              if (count of windows) is 0 then
                do script "\(command)"
              else
                tell application "System Events"
                  tell process "Terminal"
                    keystroke "t" using {command down}
                  end tell
                end tell
                delay 0.2
                do script "\(command)" in selected tab of front window
              end if
            end tell
            """
        case .current:
            return """
            tell application "Terminal"
              activate
              if (count of windows) is 0 then
                do script "\(command)"
              else
                do script "\(command)" in selected tab of front window
              end if
            end tell
            """
        }
    }

    private static func ghosttyScript(command: String, open: OpenMode) -> String {
        let command = command.appleScriptLiteral

        switch open {
        case .window:
            return """
            tell application "Ghostty"
              activate
              set cfg to new surface configuration
              set win to new window with configuration cfg
              set term to focused terminal of selected tab of win
              input text "\(command)" to term
              send key "enter" to term
            end tell
            """
        case .tab:
            return """
            tell application "Ghostty"
              activate
              set cfg to new surface configuration
              if (count of windows) is 0 then
                set win to new window with configuration cfg
                set term to focused terminal of selected tab of win
              else
                set tabRef to new tab in front window with configuration cfg
                set term to focused terminal of tabRef
              end if
              input text "\(command)" to term
              send key "enter" to term
            end tell
            """
        case .current:
            return """
            tell application "Ghostty"
              activate
              if (count of windows) is 0 then
                set cfg to new surface configuration
                set win to new window with configuration cfg
                set term to focused terminal of selected tab of win
              else
                set term to focused terminal of selected tab of front window
              end if
              input text "\(command)" to term
              send key "enter" to term
            end tell
            """
        }
    }
}

private extension String {
    var appleScriptLiteral: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
