import Foundation
@testable import Hopbar
import XCTest

@MainActor
final class CommandRunnerTests: XCTestCase {
    func testURLActionUsesWorkspaceOpener() throws {
        let opener = RecordingURLOpener()
        let runner = CommandRunner(scriptExecutor: RecordingAppleScriptExecutor(), urlOpener: opener)
        let url = URL(string: "https://example.com")!

        try runner.run(.openURL(url))

        XCTAssertEqual(opener.openedURLs, [url])
    }

    func testITermTabScriptCreatesTabWithDefaultProfile() {
        let script = CommandRunner.script(command: "ssh user@example.com", terminal: .iterm, open: .tab)

        XCTAssertTrue(script.contains("application \"iTerm\""))
        XCTAssertTrue(script.contains("create tab with default profile"))
        XCTAssertTrue(script.contains("write text \"ssh user@example.com\""))
    }

    func testITermWindowScriptCreatesWindow() {
        let script = CommandRunner.script(command: "pwd", terminal: .iterm, open: .window)

        XCTAssertTrue(script.contains("create window with default profile"))
        XCTAssertTrue(script.contains("write text \"pwd\""))
    }

    func testTerminalCurrentScriptRunsInSelectedTab() {
        let script = CommandRunner.script(command: "top", terminal: .terminal, open: .current)

        XCTAssertTrue(script.contains("application \"Terminal\""))
        XCTAssertTrue(script.contains("selected tab of front window"))
    }

    func testEscapesAppleScriptStringContent() {
        let script = CommandRunner.script(command: #"echo "hello" \ world"#, terminal: .iterm, open: .current)

        XCTAssertTrue(script.contains(#"write text "echo \"hello\" \\ world""#))
    }

    func testCommandActionExecutesGeneratedScript() throws {
        let executor = RecordingAppleScriptExecutor()
        let runner = CommandRunner(scriptExecutor: executor, urlOpener: RecordingURLOpener())

        try runner.run(.runCommand("pwd", terminal: .terminal, open: .window))

        XCTAssertEqual(executor.executedScripts.count, 1)
        XCTAssertTrue(executor.executedScripts[0].contains("application \"Terminal\""))
        XCTAssertTrue(executor.executedScripts[0].contains("do script \"pwd\""))
    }
}

private final class RecordingAppleScriptExecutor: AppleScriptExecuting {
    private(set) var executedScripts: [String] = []

    func execute(_ source: String) throws {
        executedScripts.append(source)
    }
}

@MainActor
private final class RecordingURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}
