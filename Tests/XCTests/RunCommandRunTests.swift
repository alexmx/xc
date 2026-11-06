import Foundation
import Testing
@testable import xc

/// Runs `xc run` end to end against a temporary project, through ArgumentParser.
@Suite("RunCommand run Tests", .timeLimit(.minutes(1)))
struct RunCommandRunTests {
    /// A temporary project made of `files` (path relative to its root → contents).
    private func makeProject(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        for (path, contents) in files {
            let file = dir + "/" + path
            let folder = (file as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try contents.write(toFile: file, atomically: true, encoding: .utf8)
        }
        return dir
    }

    /// The error message `xc <arguments>` fails with in `dir`, or nil if it succeeds.
    private func failure(_ arguments: [String], in dir: String) async throws -> String? {
        let command = try RunCommand.parseAsRoot(["-C", dir] + arguments) as? RunCommand
        do {
            try await command?.run()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func failure(_ arguments: [String], yaml: String) async throws -> String? {
        let dir = try makeProject(["xc.yaml": yaml])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        return try await failure(arguments, in: dir)
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

    // MARK: - Fan-out

    /// Root and members a (fails), b (records that it ran) and c (has no `step`).
    /// `run:` scripts run in their own project folder, so "touch ran" marks that folder.
    private func fanOutProject() throws -> String {
        try makeProject([
            "xc.yaml": "commands:\n  step:\n    run: \"touch ran\"\nmembers:\n  a: a\n  b: b\n  c: c\n",
            "a/xc.yaml": "commands:\n  step:\n    run: \"exit 1\"\n",
            "b/xc.yaml": "commands:\n  step:\n    run: \"touch ran\"\n",
            "c/xc.yaml": "commands:\n  other:\n    run: \"true\"\n"
        ])
    }

    /// Whether `step` ran in `target` ("." for the root).
    private func ran(_ target: String, in dir: String) -> Bool {
        FileManager.default.fileExists(atPath: dir + "/" + target + "/ran")
    }

    @Test("--all runs the root first and stops at the first failing member")
    func fanOutFailFast() async throws {
        let dir = try fanOutProject()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["step", "--all"], in: dir) == "Failed in 1 member(s): a.")
        #expect(ran(".", in: dir))
        #expect(!ran("b", in: dir))
    }

    @Test("--continue keeps going after a failure and still reports it")
    func fanOutContinue() async throws {
        let dir = try fanOutProject()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["step", "--all", "--continue"], in: dir) == "Failed in 1 member(s): a.")
        #expect(ran("b", in: dir))
    }

    @Test("--members runs only those members, not the root")
    func fanOutSelectedMembers() async throws {
        let dir = try fanOutProject()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["step", "--members", "b"], in: dir) == nil)
        #expect(ran("b", in: dir))
        #expect(!ran(".", in: dir))
    }

    @Test("a member without the command is skipped, not failed")
    func fanOutSkips() async throws {
        let dir = try fanOutProject()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["step", "--members", "b,c"], in: dir) == nil)
    }

    @Test("an unknown member name lists the available ones")
    func fanOutUnknownMember() async throws {
        let dir = try fanOutProject()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["step", "--members", "ghost"], in: dir)
            == "Unknown member 'ghost'. Available members: a, b, c.")
    }
}
