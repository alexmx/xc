import Foundation

enum HookRunner {
    static func run(_ command: String, label: String) async throws {
        print("→ Running \(label) hook...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw XCError.hookFailed(label, process.terminationStatus)
        }
    }
}
