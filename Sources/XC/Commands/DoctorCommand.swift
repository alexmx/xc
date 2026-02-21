import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Validate project setup and diagnose common issues"
    )

    func run() throws {
        var hasErrors = false

        // 1. Check xc.yaml
        let (projectConfig, projectRoot): (ProjectConfig, String)
        do {
            (projectConfig, projectRoot) = try ConfigLoader.loadProjectConfig()
            printCheck("xc.yaml", status: .ok)
        } catch {
            if case XCError.configNotFound = error {
                printCheck("xc.yaml", status: .fail, detail: "Not found. Run 'xc init' to generate one.")
            } else if case XCError.invalidConfig(let reason) = error {
                printCheck("xc.yaml", status: .fail, detail: reason)
            } else {
                printCheck("xc.yaml", status: .fail, detail: error.localizedDescription)
            }
            return
        }

        // 2. Validate config structure
        do {
            try ConfigLoader.validate(projectConfig)
        } catch {
            printCheck("xc.yaml", status: .fail, detail: error.localizedDescription)
            hasErrors = true
        }

        // 3. Check project/workspace exists on disk
        if let project = projectConfig.project {
            let path = projectRoot + "/" + project
            if FileManager.default.fileExists(atPath: path) {
                printCheck("Project", status: .ok, detail: project)
            } else {
                printCheck("Project", status: .fail, detail: "\(project) not found")
                hasErrors = true
            }
        } else if let workspace = projectConfig.workspace {
            let path = projectRoot + "/" + workspace
            if FileManager.default.fileExists(atPath: path) {
                printCheck("Workspace", status: .ok, detail: workspace)
            } else {
                printCheck("Workspace", status: .fail, detail: "\(workspace) not found")
                hasErrors = true
            }
        }

        // 4. Check schemes exist
        let availableSchemes = querySchemes(projectConfig: projectConfig, projectRoot: projectRoot)
        let referencedSchemes = collectSchemes(from: projectConfig)

        if let availableSchemes {
            for scheme in referencedSchemes.sorted() {
                if availableSchemes.contains(scheme) {
                    printCheck("Scheme: \(scheme)", status: .ok)
                } else {
                    printCheck(
                        "Scheme: \(scheme)",
                        status: .fail,
                        detail: "Not found. Available: \(availableSchemes.sorted().joined(separator: ", "))"
                    )
                    hasErrors = true
                }
            }
        }

        // 5. Check named destinations resolve to installed simulators
        if let destinations = projectConfig.destinations, !destinations.isEmpty {
            let installedSimulators = queryInstalledSimulatorNames()

            for (name, value) in destinations.sorted(by: { $0.key < $1.key }) {
                if value.contains("platform=macOS") {
                    printCheck("Dest: \(name)", status: .ok, detail: "macOS")
                } else if let simName = extractSimulatorName(from: value) {
                    if installedSimulators.contains(simName) {
                        printCheck("Dest: \(name)", status: .ok, detail: simName)
                    } else {
                        printCheck(
                            "Dest: \(name)",
                            status: .fail,
                            detail: "\(simName) not found. Run 'xc destinations' to see available simulators."
                        )
                        hasErrors = true
                    }
                } else {
                    printCheck("Dest: \(name)", status: .ok, detail: value)
                }
            }
        }

        // 6. Check xcbeautify
        if CommandRunner.findInPath("xcbeautify") != nil {
            printCheck("xcbeautify", status: .ok)
        } else {
            printCheck(
                "xcbeautify",
                status: .warn,
                detail: "Not installed. Output will be raw. Install: brew install xcbeautify"
            )
        }

        // 7. Check global config
        do {
            if let _ = try ConfigLoader.loadGlobalConfig() {
                printCheck("Global config", status: .ok, detail: "~/.config/xc/config.yaml")
            } else {
                printCheck("Global config", status: .skip, detail: "not found (optional)")
            }
        } catch {
            printCheck("Global config", status: .warn, detail: "Parse error: \(error.localizedDescription)")
        }

        if hasErrors {
            print()
            print("Some checks failed. Fix the issues above and run 'xc doctor' again.")
        }
    }

    // MARK: - Output formatting

    enum CheckStatus {
        case ok, warn, fail, skip

        var label: String {
            switch self {
            case .ok: "OK"
            case .warn: "WARN"
            case .fail: "FAIL"
            case .skip: "-"
            }
        }
    }

    static func printCheck(_ name: String, status: CheckStatus, detail: String? = nil) {
        let statusLabel = status.label.padding(toLength: 4, withPad: " ", startingAt: 0)
        if let detail {
            print("  \(statusLabel)  \(name)\t\(detail)")
        } else {
            print("  \(statusLabel)  \(name)")
        }
    }

    private func printCheck(_ name: String, status: CheckStatus, detail: String? = nil) {
        Self.printCheck(name, status: status, detail: detail)
    }

    // MARK: - Queries

    func querySchemes(projectConfig: ProjectConfig, projectRoot: String) -> [String]? {
        var args = ["xcodebuild", "-list", "-json"]

        if let workspace = projectConfig.workspace {
            args += ["-workspace", workspace]
        } else if let project = projectConfig.project {
            args += ["-project", project]
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let container = json["workspace"] as? [String: Any]
            ?? json["project"] as? [String: Any]
            ?? [:]

        return container["schemes"] as? [String]
    }

    func queryInstalledSimulatorNames() -> Set<String> {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "-j"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]] else {
            return []
        }

        var names = Set<String>()
        for (_, devices) in devicesMap {
            for device in devices {
                if let name = device["name"] as? String,
                   let available = device["isAvailable"] as? Bool,
                   available {
                    names.insert(name)
                }
            }
        }
        return names
    }

    // MARK: - Helpers

    /// Collect all scheme names referenced in defaults + commands + variants.
    static func collectSchemes(from config: ProjectConfig) -> Set<String> {
        var schemes = Set<String>()
        if let s = config.defaults?.scheme { schemes.insert(s) }
        for (_, cmd) in config.commands ?? [:] {
            if let s = cmd.scheme { schemes.insert(s) }
            for (_, variant) in cmd.variants ?? [:] {
                if let s = variant.scheme { schemes.insert(s) }
            }
        }
        return schemes
    }

    private func collectSchemes(from config: ProjectConfig) -> Set<String> {
        Self.collectSchemes(from: config)
    }

    /// Extract simulator name from a destination string like "platform=iOS Simulator,name=iPhone 17 Pro"
    static func extractSimulatorName(from destination: String) -> String? {
        let parts = destination.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name=") {
                return String(trimmed.dropFirst("name=".count))
            }
        }
        return nil
    }

    private func extractSimulatorName(from destination: String) -> String? {
        Self.extractSimulatorName(from: destination)
    }
}
