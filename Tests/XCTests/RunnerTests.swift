import Foundation
import Testing
@testable import xc

/// End-to-end checks of the process runners, written against the behavior
/// they must keep: exit codes, signals, the formatter pipe and the environment.
@Suite("Runner Tests", .timeLimit(.minutes(1)))
struct RunnerTests {
    private func withTempDirectory(_ body: (String) async throws -> Void) async throws {
        let tempDir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        try await body(tempDir)
    }

    /// The XCError `body` throws, described, or nil if it doesn't throw one.
    private func failure(_ body: () async throws -> Void) async -> String? {
        do {
            try await body()
            return nil
        } catch {
            return (error as? XCError)?.errorDescription
        }
    }

    @Test("a failing script returns its exit code, a passing one nil")
    func shellExitCode() async throws {
        #expect(try await ShellRunner.run("exit 3") == 3)
        #expect(try await ShellRunner.run("true") == nil)
    }

    @Test("a script killed by a signal returns the signal number")
    func shellSignal() async throws {
        #expect(try await ShellRunner.run("kill -TERM $$") == 15)
    }

    @Test("a script runs in the working directory")
    func shellWorkingDirectory() async throws {
        try await withTempDirectory { dir in
            _ = try await ShellRunner.run("echo ok > out.txt", in: dir)
            #expect(FileManager.default.fileExists(atPath: dir + "/out.txt"))
        }
    }

    @Test("the formatter receives stdout and stderr, and the build's exit code is reported")
    func formatterPipe() async throws {
        try await withTempDirectory { dir in
            let out = dir + "/formatted.txt"
            let message = await failure {
                try await CommandRunner.exec(
                    args: ["sh", "-c", "echo out; echo err >&2; exit 4"],
                    formatter: "cat > '\(out)'"
                )
            }
            #expect(message == XCError.buildFailed(4).errorDescription)
            let formatted = try String(contentsOfFile: out, encoding: .utf8)
            #expect(formatted == "out\nerr\n")
        }
    }

    @Test("a successful build through the formatter doesn't throw")
    func formatterSuccess() async throws {
        try await CommandRunner.exec(args: ["sh", "-c", "exit 0"], formatter: "cat > /dev/null")
    }

    @Test("raw output reports the build's exit code")
    func rawExitCode() async {
        let message = await failure {
            try await CommandRunner.exec(args: ["sh", "-c", "exit 2"], formatter: "raw")
        }
        #expect(message == XCError.buildFailed(2).errorDescription)
    }

    @Test("xcodebuild runs in the working directory with the given environment")
    func execEnvironmentAndDirectory() async throws {
        try await withTempDirectory { dir in
            try await CommandRunner.exec(
                args: ["sh", "-c", "printf '%s' \"$XC_ROOT\" > root.txt"],
                formatter: "raw",
                workingDirectory: dir,
                environment: ConfigLoader.environment(root: dir)
            )
            let root = try String(contentsOfFile: dir + "/root.txt", encoding: .utf8)
            #expect(root == dir)
        }
    }
}
