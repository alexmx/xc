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
            for (runtime, devices) in simulators {
                print("  \(runtime.displayName):")
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

    /// Available simulators grouped by runtime, runtimes in version order.
    func querySimulators() async -> [(runtime: SimRuntime, devices: [SimDevice])] {
        await Simulators.available()
            .map { id, names in
                let runtime = SimRuntime(id: id)
                let devices = names.sorted().map { name in
                    SimDevice(name: name, destination: "platform=\(runtime.destinationPlatform),name=\(name)")
                }
                return (runtime, devices)
            }
            .sorted { $0.runtime < $1.runtime }
    }
}
