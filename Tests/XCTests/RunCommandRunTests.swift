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

    // MARK: - Steps

    /// Commands a, b and bad append to `log` in the project root; `extra` adds more YAML.
    private func stepsProject(_ extra: String, files: [String: String] = [:]) throws -> String {
        try makeProject(files.merging(["xc.yaml": """
        commands:
          a:
            run: "echo a >> log"
          b:
            run: "echo b >> log"
          bad:
            run: "echo bad >> log; exit 1"
          bad2:
            run: "exit 1"
        \(extra)
        """]) { $1 })
    }

    private func log(_ dir: String) -> String? {
        try? String(contentsOfFile: dir + "/log", encoding: .utf8)
    }

    @Test("steps run in order")
    func stepsInOrder() async throws {
        let dir = try stepsProject("  gate:\n    steps: [a, b]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate"], in: dir) == nil)
        #expect(log(dir) == "a\nb\n")
    }

    @Test("a failing step stops the chain")
    func stepsFailFast() async throws {
        let dir = try stepsProject("  gate:\n    steps: [a, bad, b]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate"], in: dir) == "Step 'bad' failed.")
        #expect(log(dir) == "a\nbad\n")
    }

    @Test("--continue runs every step and lists the failures")
    func stepsContinue() async throws {
        let dir = try stepsProject("  gate:\n    steps: [bad, a, bad2, b]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate", "--continue"], in: dir) == "Steps failed: bad, bad2.")
        #expect(log(dir) == "bad\na\nb\n")
    }

    @Test("--dry-run runs nothing")
    func stepsDryRun() async throws {
        let dir = try stepsProject("  gate:\n    steps: [a, b]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate", "--dry-run"], in: dir) == nil)
        #expect(log(dir) == nil)
    }

    @Test("an unknown step fails before any step runs")
    func stepsUnknown() async throws {
        let dir = try stepsProject("  gate:\n    steps: [a, nope]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let message = try await failure(["gate"], in: dir)
        #expect(message?.hasPrefix("Step 'nope' of 'gate': Unknown command 'nope'.") == true)
        #expect(log(dir) == nil)
    }

    @Test("steps that loop back are rejected before any step runs")
    func stepsCycle() async throws {
        let dir = try stepsProject("  gate:\n    steps: [a, check]\n  check:\n    steps: [gate]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate"], in: dir) == "Steps of 'gate' loop: gate → check → gate.")
        #expect(log(dir) == nil)
    }

    @Test("arguments after -- are rejected for a steps command")
    func stepsPassthrough() async throws {
        let dir = try stepsProject("  gate:\n    steps: [a]")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate", "--", "-x"], in: dir)
            == "Invalid command 'gate': arguments after -- can't be passed to a steps command.")
        #expect(log(dir) == nil)
    }

    @Test("the steps command's hooks wrap the chain; each step keeps its own")
    func stepsHooks() async throws {
        let dir = try stepsProject("""
          gate:
            steps: [b]
            hooks:
              pre: "echo gate-pre >> log"
              post: "echo gate-post >> log"
          hooked:
            run: "echo hooked >> log"
            hooks:
              pre: "echo hooked-pre >> log"
          wrapped:
            steps: [gate, hooked]
        """)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["wrapped"], in: dir) == nil)
        #expect(log(dir) == "gate-pre\nb\ngate-post\nhooked-pre\nhooked\n")
    }

    @Test("a member step runs in the member")
    func stepsMember() async throws {
        let dir = try stepsProject(
            "  gate:\n    steps: [a, core/a]\nmembers:\n  core: core",
            files: ["core/xc.yaml": "commands:\n  a:\n    run: \"echo core >> log\"\n"]
        )
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["gate"], in: dir) == nil)
        #expect(log(dir) == "a\n")
        #expect(log(dir + "/core") == "core\n")
    }

    // MARK: - Names in failures

    @Test("a failing variant is named with its variant, in a step summary too")
    func failingVariantNamed() async throws {
        let yaml = """
        commands:
          test:
            run: "true"
            variants:
              all:
                run: "exit 1"
                hooks:
                  post: "true"
          gate:
            steps: [test:all]
          hooked:
            run: "true"
            variants:
              ci:
                hooks:
                  pre: "exit 2"
        """
        #expect(try await failure(["test:all"], yaml: yaml) == "Command 'test:all' exited with code 1.")
        #expect(try await failure(["hooked:ci"], yaml: yaml) == "Hook 'pre-hooked:ci' failed with exit code 2.")
        #expect(try await failure(["gate"], yaml: yaml) == "Step 'test:all' failed.")
    }

    @Test("a failing member command is named with its member")
    func failingMemberNamed() async throws {
        let dir = try makeProject([
            "xc.yaml": "commands:\n  gate:\n    steps: [core/test:all]\nmembers:\n  core: core\n",
            "core/xc.yaml": "commands:\n  test:\n    run: \"true\"\n    variants:\n      all:\n        run: \"exit 1\"\n"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(try await failure(["core/test:all"], in: dir) == "Command 'core/test:all' exited with code 1.")
    }
}
