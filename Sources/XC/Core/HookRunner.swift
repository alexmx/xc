import Foundation

enum HookRunner {
    static func run(
        _ command: String,
        label: String,
        workingDirectory: String? = nil,
        quiet: Bool = false,
        environment: [String: String]? = nil
    ) throws {
        if !quiet {
            print("→ Running \(label) hook...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        if let environment {
            process.environment = environment
        }
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw XCError.hookFailed(label, process.terminationStatus)
        }
    }
}
