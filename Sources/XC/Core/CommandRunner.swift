import Foundation

enum CommandRunner {
    /// Execute xcodebuild, optionally piping through a formatter.
    /// - formatter: A shell command to pipe output through (e.g. "xcbeautify --quiet"),
    ///   or nil/​"raw" for no formatting. Defaults to xcbeautify if not specified.
    static func exec(
        args: [String],
        formatter: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) throws {
        let xcodebuild = Process()
        xcodebuild.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        xcodebuild.arguments = args
        if let environment {
            xcodebuild.environment = environment
        }
        if let workingDirectory {
            xcodebuild.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let formatterCommand = resolveFormatter(formatter)

        if let formatterCommand {
            let pipe = Pipe()
            xcodebuild.standardOutput = pipe
            xcodebuild.standardError = pipe

            let fmt = Process()
            fmt.executableURL = URL(fileURLWithPath: "/bin/sh")
            fmt.arguments = ["-c", formatterCommand]
            fmt.standardInput = pipe
            fmt.standardOutput = FileHandle.standardOutput
            fmt.standardError = FileHandle.standardError

            try xcodebuild.run()
            do {
                try fmt.run()
            } catch {
                xcodebuild.terminate()
                xcodebuild.waitUntilExit()
                throw error
            }

            xcodebuild.waitUntilExit()
            pipe.fileHandleForWriting.closeFile()
            fmt.waitUntilExit()

            if xcodebuild.terminationStatus != 0 {
                throw XCError.buildFailed(xcodebuild.terminationStatus)
            }
        } else {
            xcodebuild.standardOutput = FileHandle.standardOutput
            xcodebuild.standardError = FileHandle.standardError

            try xcodebuild.run()
            xcodebuild.waitUntilExit()

            if xcodebuild.terminationStatus != 0 {
                throw XCError.buildFailed(xcodebuild.terminationStatus)
            }
        }
    }

    /// Resolve the formatter command string.
    /// - nil or "xcbeautify": use xcbeautify if installed (with --disable-logging)
    /// - "raw": no formatter
    /// - anything else: use as a shell command
    static func resolveFormatter(_ formatter: String?) -> String? {
        let value = formatter ?? "xcbeautify"

        if value == "raw" {
            return nil
        }

        if value == "xcbeautify" {
            guard let path = findInPath("xcbeautify") else { return nil }
            return path
        }

        return value
    }

    /// Find an executable in PATH, like `which`.
    static func findInPath(_ name: String) -> String? {
        let fileManager = FileManager.default
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for directory in directories {
            let candidate = "\(directory)/\(name)"
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue,
               fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
