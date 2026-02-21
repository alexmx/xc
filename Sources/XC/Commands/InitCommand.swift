import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Generate an xc.yaml configuration file"
    )

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let configPath = cwd + "/xc.yaml"

        guard !FileManager.default.fileExists(atPath: configPath) else {
            print("xc.yaml already exists in this directory.")
            return
        }

        let detection = detectProject(in: cwd)
        let schemes = querySchemes(detection: detection, in: cwd)
        let primaryScheme = Self.pickPrimaryScheme(schemes: schemes, detection: detection)
        let platform = detectPlatform(detection: detection, scheme: primaryScheme, in: cwd)
        let defaultSimulator = platform == .iOS ? findDefaultiPhoneSimulator() : nil

        let yaml = Self.generateConfig(
            detection: detection,
            primaryScheme: primaryScheme,
            platform: platform,
            defaultSimulator: defaultSimulator
        )

        try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)

        let projectLabel: String
        switch detection {
        case .workspace(let name, _): projectLabel = "Workspace: \(name)"
        case .project(let name, _): projectLabel = "Project: \(name)"
        case .spm: projectLabel = "Swift Package"
        case .none: projectLabel = "No project detected"
        }

        print("Created xc.yaml")
        print()
        print("  \(projectLabel)")
        if !schemes.isEmpty {
            print("  Schemes: \(schemes.joined(separator: ", "))")
        }
        if let primaryScheme {
            print("  Default scheme: \(primaryScheme)")
        }
        print("  Platform: \(platform.displayName)")
        print()
        print("Run 'xc build' to get started, or edit xc.yaml to customize.")
    }

    // MARK: - Types

    enum ProjectType: Equatable {
        case workspace(name: String, path: String)
        case project(name: String, path: String)
        case spm
        case none

        var name: String {
            switch self {
            case .workspace(let name, _), .project(let name, _): name
            case .spm: "Package"
            case .none: "Project"
            }
        }
    }

    enum Platform: Equatable {
        case iOS, macOS, unknown

        var displayName: String {
            switch self {
            case .iOS: "iOS"
            case .macOS: "macOS"
            case .unknown: "unknown"
            }
        }
    }

    // MARK: - Detection (uses Process)

    func detectProject(in directory: String) -> ProjectType {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return .none }

        let workspaces = contents.filter { $0.hasSuffix(".xcworkspace") }.sorted()
        if let ws = workspaces.first {
            let name = String(ws.dropLast(".xcworkspace".count))
            return .workspace(name: name, path: ws)
        }

        let projects = contents.filter { $0.hasSuffix(".xcodeproj") }.sorted()
        if let proj = projects.first {
            let name = String(proj.dropLast(".xcodeproj".count))
            return .project(name: name, path: proj)
        }

        if contents.contains("Package.swift") {
            return .spm
        }

        return .none
    }

    func querySchemes(detection: ProjectType, in directory: String) -> [String] {
        var args = ["xcodebuild", "-list", "-json"]

        switch detection {
        case .workspace(_, let path): args += ["-workspace", path]
        case .project(_, let path): args += ["-project", path]
        case .spm, .none: break
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let container = json["workspace"] as? [String: Any]
            ?? json["project"] as? [String: Any]
            ?? [:]

        let schemes = container["schemes"] as? [String] ?? []

        return schemes.filter { scheme in
            !scheme.hasPrefix("Generate ") && !scheme.hasSuffix("-Workspace")
        }
    }

    func detectPlatform(detection: ProjectType, scheme: String?, in directory: String) -> Platform {
        guard let scheme else { return .unknown }

        var args = ["xcodebuild", "-showdestinations", "-scheme", scheme]

        switch detection {
        case .workspace(_, let path): args += ["-workspace", path]
        case .project(_, let path): args += ["-project", path]
        case .spm, .none: break
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if output.contains("platform:iOS Simulator") {
            return .iOS
        } else if output.contains("platform:macOS") {
            return .macOS
        }

        return .unknown
    }

    func findDefaultiPhoneSimulator() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "-j"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]] else {
            return nil
        }

        // Search newest runtimes first for an iPhone (prefer Pro non-Max)
        for (_, devices) in devicesMap.sorted(by: { $0.key > $1.key }) {
            let iphones = devices.compactMap { device -> String? in
                guard let name = device["name"] as? String,
                      let available = device["isAvailable"] as? Bool,
                      available, name.contains("iPhone") else { return nil }
                return name
            }
            if let pro = iphones.first(where: { $0.contains("Pro") && !$0.contains("Max") }) {
                return pro
            }
            if let first = iphones.first {
                return first
            }
        }

        return nil
    }

    // MARK: - Pure logic (testable)

    static func pickPrimaryScheme(schemes: [String], detection: ProjectType) -> String? {
        guard !schemes.isEmpty else { return nil }

        let projectName: String?
        switch detection {
        case .workspace(let name, _), .project(let name, _): projectName = name
        case .spm, .none: projectName = nil
        }

        if let name = projectName, schemes.contains(name) {
            return name
        }

        return schemes.first
    }

    static func generateConfig(
        detection: ProjectType,
        primaryScheme: String?,
        platform: Platform,
        defaultSimulator: String?
    ) -> String {
        var lines: [String] = []

        lines.append("# xc configuration for \(detection.name)")
        lines.append("# Run 'xc destinations' to see all available destinations")
        lines.append("")

        switch detection {
        case .workspace(_, let path):
            lines.append("workspace: \(path)")
        case .project(_, let path):
            lines.append("project: \(path)")
        case .spm, .none:
            break
        }

        lines.append("")
        lines.append("destinations:")
        switch platform {
        case .iOS:
            let sim = defaultSimulator ?? "iPhone 17 Pro"
            lines.append("  sim: \"platform=iOS Simulator,name=\(sim)\"")
            lines.append("  mac: \"platform=macOS\"")
        case .macOS:
            lines.append("  mac: \"platform=macOS\"")
        case .unknown:
            lines.append("  sim: \"platform=iOS Simulator,name=iPhone 17 Pro\"")
            lines.append("  mac: \"platform=macOS\"")
        }

        lines.append("")
        lines.append("defaults:")
        if let scheme = primaryScheme {
            lines.append("  scheme: \(scheme)")
        }
        lines.append("  configuration: Debug")
        lines.append("  destination: \(platform == .macOS ? "mac" : "sim")")

        lines.append("")
        lines.append("commands:")
        lines.append("  build:")
        lines.append("    variants:")
        lines.append("      release:")
        lines.append("        configuration: Release")
        lines.append("")
        lines.append("  test: {}")
        lines.append("")
        lines.append("  clean: {}")
        lines.append("")
        lines.append("  archive:")
        lines.append("    configuration: Release")
        lines.append("    archive-path: \"./build/\(detection.name).xcarchive\"")
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
