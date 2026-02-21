import ArgumentParser
import Foundation

struct DestinationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "destinations",
        abstract: "List available destinations"
    )

    func run() throws {
        // Show named destinations from xc.yaml if available
        let projectConfig = try? ConfigLoader.loadProjectConfig()
        if let destinations = projectConfig?.destinations, !destinations.isEmpty {
            print("Named destinations (from xc.yaml):")
            let maxKeyLength = destinations.keys.map(\.count).max() ?? 0
            for (name, value) in destinations.sorted(by: { $0.key < $1.key }) {
                let padded = name.padding(toLength: maxKeyLength, withPad: " ", startingAt: 0)
                print("  \(padded)  →  \(value)")
            }
            print()
        }

        // Query available simulators
        let simulators = try querySimulators()
        if !simulators.isEmpty {
            print("Available simulators:")
            for (runtime, devices) in simulators.sorted(by: { $0.key < $1.key }) {
                print("  \(runtime):")
                let maxNameLength = devices.map(\.name.count).max() ?? 0
                for device in devices {
                    let padded = device.name.padding(toLength: maxNameLength, withPad: " ", startingAt: 0)
                    print("    \(padded)  →  \(device.destination)")
                }
            }
            print()
        }

        // Always show platform hints
        print("Other platforms:")
        print("  macOS            →  platform=macOS")
        print("  macOS (Rosetta)  →  platform=macOS,arch=x86_64")
        print("  iOS device       →  platform=iOS,name=<device name>")

        print()
        print("Use in xc.yaml:")
        print("  destinations:")
        print("    sim: \"platform=iOS Simulator,name=iPhone 17 Pro\"")
        print("    mac: \"platform=macOS\"")
    }

    // MARK: - Simulator query

    struct SimDevice {
        let name: String
        let destination: String
    }

    func querySimulators() throws -> [String: [SimDevice]] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "-j"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [:] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]] else {
            return [:]
        }

        var result: [String: [SimDevice]] = [:]

        for (runtimeID, devices) in devicesMap {
            // Runtime IDs look like "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
            let runtimeName = formatRuntime(runtimeID)
            var runtimeDevices: [SimDevice] = []

            for device in devices {
                guard let name = device["name"] as? String,
                      let isAvailable = device["isAvailable"] as? Bool,
                      isAvailable else { continue }

                let platform = runtimeName.contains("iOS") ? "iOS Simulator"
                    : runtimeName.contains("tvOS") ? "tvOS Simulator"
                    : runtimeName.contains("watchOS") ? "watchOS Simulator"
                    : runtimeName.contains("visionOS") ? "visionOS Simulator"
                    : runtimeName

                runtimeDevices.append(SimDevice(
                    name: name,
                    destination: "platform=\(platform),name=\(name)"
                ))
            }

            if !runtimeDevices.isEmpty {
                result[runtimeName] = runtimeDevices.sorted { $0.name < $1.name }
            }
        }

        return result
    }

    /// Convert "com.apple.CoreSimulator.SimRuntime.iOS-18-5" → "iOS 18.5"
    func formatRuntime(_ runtimeID: String) -> String {
        let stripped = runtimeID
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        // "iOS-18-5" → "iOS 18.5"
        let parts = stripped.split(separator: "-")
        guard parts.count >= 2 else { return stripped }

        // Find where the version numbers start (first numeric part)
        var platformParts: [String] = []
        var versionParts: [String] = []
        var foundVersion = false

        for part in parts {
            if !foundVersion && part.first?.isNumber == true {
                foundVersion = true
            }
            if foundVersion {
                versionParts.append(String(part))
            } else {
                platformParts.append(String(part))
            }
        }

        let platform = platformParts.joined(separator: " ")
        let version = versionParts.joined(separator: ".")

        return version.isEmpty ? platform : "\(platform) \(version)"
    }
}
