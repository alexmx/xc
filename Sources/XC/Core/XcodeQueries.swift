import Foundation
import Subprocess
import System

/// Runs a command and collects its standard output, for the read-only queries
/// (simctl, xcodebuild -list) that parse what a tool prints.
enum Capture {
    /// Far above what simctl or xcodebuild print; a runaway tool fails instead of filling memory.
    static let limit = 16 * 1024 * 1024

    /// Standard output, or nil if the command can't launch, exits non-zero, or exceeds `limit`.
    /// Standard error is discarded.
    static func output(_ executable: String, _ arguments: [String], in directory: String? = nil) async -> Data? {
        let result = try? await run(
            .path(FilePath(executable)),
            arguments: Arguments(arguments),
            workingDirectory: directory.map { FilePath($0) },
            output: .data(limit: limit),
            error: .discarded
        )
        guard let result, result.terminationStatus.isSuccess else { return nil }
        return result.standardOutput
    }

    static func xcrun(_ arguments: [String], in directory: String? = nil) async -> Data? {
        await output("/usr/bin/xcrun", arguments, in: directory)
    }
}

/// Available simulators, from `xcrun simctl list devices available -j`.
enum Simulators {
    /// Runtime ID (e.g. "com.apple.CoreSimulator.SimRuntime.iOS-26-0") → available device
    /// names in simctl's order. Runtimes without available devices are left out.
    static func available() async -> [String: [String]] {
        guard let data = await Capture.xcrun(["simctl", "list", "devices", "available", "-j"]) else { return [:] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [String: [String]] {
        struct List: Decodable {
            struct Device: Decodable {
                let name: String?
                let isAvailable: Bool?
            }

            let devices: [String: [Device]]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return [:] }
        return list.devices
            .mapValues { devices in devices.filter { $0.isAvailable == true }.compactMap(\.name) }
            .filter { !$0.value.isEmpty }
    }
}

/// Scheme names, from `xcrun xcodebuild -list -json`.
enum Schemes {
    /// `containerArgs` is `["-workspace", path]`, `["-project", path]`, or empty for a package.
    static func list(containerArgs: [String], in directory: String) async -> [String]? {
        guard let data = await Capture.xcrun(["xcodebuild", "-list", "-json"] + containerArgs, in: directory)
        else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> [String]? {
        struct List: Decodable {
            struct Container: Decodable {
                let schemes: [String]?
            }

            let workspace: Container?
            let project: Container?
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
        return (list.workspace ?? list.project)?.schemes
    }
}
