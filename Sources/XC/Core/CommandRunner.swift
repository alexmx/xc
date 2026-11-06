import Foundation
import Subprocess
import System

enum CommandRunner {
    /// Execute xcodebuild, piping its output through `formatter` (a shell command such as
    /// "xcbeautify --quiet") when one is given. See `formatterCommand(for:)`.
    static func exec(
        args: [String],
        formatter: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws {
        let xcrun = Executable.path("/usr/bin/xcrun")
        let arguments = Arguments(args)
        let env: Subprocess.Environment = environment.map { .exactly($0) } ?? .inherit
        let directory = workingDirectory.map { FilePath($0) }

        let status: TerminationStatus
        if let formatter {
            // xcodebuild starts only once the formatter is running, so a formatter that
            // can't launch never leaves xcodebuild writing into an unread pipe. The write
            // end is handed to xcodebuild, closing with it so the formatter sees EOF.
            // (With closeAfterSpawningProcess: false, swift-subprocess 1.0.2 keeps a copy
            // of the descriptor open and the formatter never finishes.)
            let pipe = try FileDescriptor.pipe()
            var writeEndHandedOff = false
            defer {
                if !writeEndHandedOff {
                    try? pipe.writeEnd.close()
                }
            }
            let formatted = try await Subprocess.run(
                .path("/bin/sh"),
                arguments: ["-c", formatter],
                input: .fileDescriptor(pipe.readEnd, closeAfterSpawningProcess: true),
                output: .currentStandardOutput,
                error: .currentStandardError
            ) { _ in
                writeEndHandedOff = true
                return try await Subprocess.run(
                    xcrun,
                    arguments: arguments,
                    environment: env,
                    workingDirectory: directory,
                    input: .currentStandardInput,
                    output: .fileDescriptor(pipe.writeEnd, closeAfterSpawningProcess: true),
                    error: .combinedWithOutput
                ).terminationStatus
            }
            status = formatted.closureResult
        } else {
            status = try await Subprocess.run(
                xcrun,
                arguments: arguments,
                environment: env,
                workingDirectory: directory,
                input: .currentStandardInput,
                output: .currentStandardOutput,
                error: .currentStandardError
            ).terminationStatus
        }

        if let code = status.failureCode {
            throw XCError.buildFailed(code)
        }
    }

    /// The command for a `settings.formatter` value, or nil for no formatting:
    /// - nil or "xcbeautify": xcbeautify if installed, else none
    /// - "raw": none
    /// - anything else: used as a shell command
    static func formatterCommand(for configured: String?) -> String? {
        let value = configured ?? "xcbeautify"

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
