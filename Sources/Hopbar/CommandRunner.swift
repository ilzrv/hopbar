import AppKit
import Foundation

enum MenuAction: Equatable {
    case openURL(URL)
    case runCommand(String, terminal: TerminalPreference, open: OpenMode)
}

@MainActor
protocol CommandRunning {
    func run(_ action: MenuAction) throws
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

    func run(_ action: MenuAction) throws {
        switch action {
        case .openURL(let url):
            urlOpener.open(url)
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
        }
    }

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
