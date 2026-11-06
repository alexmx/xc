import Foundation
import Subprocess
import System

enum HookRunner {
    static func run(
        _ command: String,
        label: String,
        workingDirectory: String? = nil,
        quiet: Bool = false,
        environment: [String: String]? = nil
    ) async throws {
        if !quiet {
            print("→ Running \(label) hook...")
            // Flush before the child writes, or piped output shows the banner last.
            fflush(stdout)
        }

        let result = try await Subprocess.run(
            .path("/bin/sh"),
            arguments: ["-c", command],
            environment: environment.map { .exactly($0) } ?? .inherit,
            workingDirectory: workingDirectory.map { FilePath($0) },
            input: .currentStandardInput,
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if let code = result.terminationStatus.failureCode {
            throw XCError.hookFailed(label, code)
        }
    }
}
