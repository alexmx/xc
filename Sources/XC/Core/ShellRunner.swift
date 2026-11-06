import Foundation
import Subprocess
import System

/// Runs a shell snippet (a hook or a `run:` command) with `/bin/sh -c`, attached to
/// the terminal. Callers turn a failure into their own error.
enum ShellRunner {
    /// The failure code (exit code, or signal number), or nil if the script succeeded.
    static func run(
        _ script: String,
        in workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> Int32? {
        try await Subprocess.run(
            .path("/bin/sh"),
            arguments: ["-c", script],
            environment: environment.map { .exactly($0) } ?? .inherit,
            workingDirectory: workingDirectory.map { FilePath($0) },
            input: .currentStandardInput,
            output: .currentStandardOutput,
            error: .currentStandardError
        ).terminationStatus.failureCode
    }
}
