import Foundation

enum CommandRunner {
    static func exec(args: [String], useFormatter: Bool, workingDirectory: String? = nil) throws {
        let xcodebuild = Process()
        xcodebuild.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        xcodebuild.arguments = args
        if let workingDirectory {
            xcodebuild.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        if useFormatter, let formatterURL = findXcbeautify() {
            let pipe = Pipe()
            xcodebuild.standardOutput = pipe
            xcodebuild.standardError = pipe

            let formatter = Process()
            formatter.executableURL = formatterURL
            formatter.standardInput = pipe
            formatter.standardOutput = FileHandle.standardOutput
            formatter.standardError = FileHandle.standardError

            try xcodebuild.run()
            do {
                try formatter.run()
            } catch {
                xcodebuild.terminate()
                xcodebuild.waitUntilExit()
                throw error
            }

            xcodebuild.waitUntilExit()
            pipe.fileHandleForWriting.closeFile()
            formatter.waitUntilExit()

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

    static func findXcbeautify() -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["xcbeautify"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}
