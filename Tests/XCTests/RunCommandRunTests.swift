import Foundation
import Testing
@testable import xc

/// Runs `xc run` end to end against a temporary project, through ArgumentParser.
@Suite("RunCommand run Tests", .timeLimit(.minutes(1)))
struct RunCommandRunTests {
    /// The XCError message `xc <arguments>` fails with in a project with `yaml`, or nil.
    private func failure(_ arguments: [String], yaml: String) async throws -> String? {
        let dir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

        let command = try RunCommand.parseAsRoot(["-C", dir] + arguments) as? RunCommand
        do {
            try await command?.run()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test("a failing run: command is reported as a command, not a hook")
    func failingScript() async throws {
        let yaml = """
        commands:
          lint:
            run: "exit 3"
        """
        #expect(try await failure(["lint"], yaml: yaml) == "Command 'lint' exited with code 3.")
    }

    @Test("a failing hook is reported as a hook")
    func failingHook() async throws {
        let yaml = """
        commands:
          lint:
            run: "true"
            hooks:
              pre: "exit 2"
        """
        #expect(try await failure(["lint"], yaml: yaml) == "Hook 'pre-lint' failed with exit code 2.")
    }
}
