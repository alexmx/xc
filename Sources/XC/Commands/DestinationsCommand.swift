import ArgumentParser
import Foundation

struct DestinationsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "destinations",
        abstract: "List available destinations"
    )

    func run() async throws {
        // Show named destinations from xc.yaml if available
        let projectConfig = try? ConfigLoader.loadProjectConfig().config
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
        let simulators = await querySimulators()
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

    func querySimulators() async -> [String: [SimDevice]] {
        let devicesMap = await Simulators.available()
        var result: [String: [SimDevice]] = [:]

        for (runtimeID, names) in devicesMap {
            // Runtime IDs look like "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
            let platform = simulatorPlatform(forRuntimeID: runtimeID)
            result[formatRuntime(runtimeID)] = names.sorted().map { name in
                SimDevice(name: name, destination: "platform=\(platform),name=\(name)")
            }
        }

        return result
    }

    /// The xcodebuild destination platform for a simulator runtime ID, e.g.
    /// "com.apple.CoreSimulator.SimRuntime.xrOS-2-3" → "visionOS Simulator".
    func simulatorPlatform(forRuntimeID runtimeID: String) -> String {
        let os = runtimeID
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .prefix { $0 != "-" }
        switch os {
        case "iOS", "tvOS", "watchOS", "visionOS": return "\(os) Simulator"
        // visionOS simulator runtimes still carry the platform's old name, xrOS.
        case "xrOS": return "visionOS Simulator"
        default: return formatRuntime(runtimeID)
        }
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
