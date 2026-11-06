import ArgumentParser
import Foundation

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Validate project setup and diagnose common issues"
    )

    /// Exits 1 when any check fails, so `xc doctor` can gate CI. Warnings don't fail it.
    func run() async throws {
        guard await Self.runChecks(from: nil) else {
            throw ExitCode.failure
        }
    }

    /// Run and print every check for the project found from `directory` (default: the
    /// current one). Returns whether none failed.
    static func runChecks(from directory: String?) async -> Bool {
        let projectConfig: ProjectConfig
        let projectRoot: String
        do {
            (projectConfig, projectRoot) = try ConfigLoader.loadProjectConfig(from: directory)
        } catch {
            printCheck(configFileCheck(error))
            return false
        }

        var failed = false
        func report(_ checks: [Check]) {
            for check in checks {
                printCheck(check)
                failed = failed || check.status == .fail
            }
        }

        report([Check("xc.yaml", .ok)])
        report(structureChecks(projectConfig))
        report(containerChecks(projectConfig, projectRoot: projectRoot))
        await report(schemeChecks(projectConfig, available: querySchemes(projectConfig, projectRoot: projectRoot)))
        if let destinations = projectConfig.destinations, !destinations.isEmpty {
            await report(destinationChecks(destinations, installedSimulators: queryInstalledSimulatorNames()))
        }
        report([formatterCheck(), globalConfigCheck()])
        report(memberChecks(projectConfig, projectRoot: projectRoot))

        if failed {
            print()
            print("Some checks failed. Fix the issues above and run 'xc doctor' again.")
        }
        return !failed
    }

    // MARK: - Checks

    struct Check: Equatable {
        let name: String
        let status: CheckStatus
        let detail: String?

        init(_ name: String, _ status: CheckStatus, _ detail: String? = nil) {
            self.name = name
            self.status = status
            self.detail = detail
        }
    }

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

    /// Why xc.yaml couldn't be loaded.
    static func configFileCheck(_ error: Error) -> Check {
        switch error {
        case XCError.configNotFound: Check(
                "xc.yaml",
                .fail,
                "Not found. Run 'xc init' to generate one."
            )
        case XCError.invalidConfig(let reason): Check("xc.yaml", .fail, reason)
        default: Check("xc.yaml", .fail, error.localizedDescription)
        }
    }

    static func structureChecks(_ config: ProjectConfig) -> [Check] {
        do {
            try ConfigLoader.validate(config)
            return []
        } catch {
            return [Check("xc.yaml", .fail, error.localizedDescription)]
        }
    }

    /// The project or workspace exists on disk.
    static func containerChecks(_ config: ProjectConfig, projectRoot: String) -> [Check] {
        let container = config.project.map { ("Project", $0) } ?? config.workspace.map { ("Workspace", $0) }
        guard let (label, path) = container else { return [] }
        return FileManager.default.fileExists(atPath: projectRoot + "/" + path)
            ? [Check(label, .ok, path)]
            : [Check(label, .fail, "\(path) not found")]
    }

    /// Every referenced scheme exists. `available` is nil when xcodebuild couldn't list them.
    static func schemeChecks(_ config: ProjectConfig, available: [String]?) -> [Check] {
        guard let available else { return [] }
        return collectSchemes(from: config).sorted().map { scheme in
            available.contains(scheme)
                ? Check("Scheme: \(scheme)", .ok)
                : Check(
                    "Scheme: \(scheme)",
                    .fail,
                    "Not found. Available: \(available.sorted().joined(separator: ", "))"
                )
        }
    }

    /// Named simulator destinations are installed.
    static func destinationChecks(_ destinations: [String: String], installedSimulators: Set<String>) -> [Check] {
        destinations.sorted(by: { $0.key < $1.key }).map { name, value in
            if value.contains("platform=macOS") {
                return Check("Dest: \(name)", .ok, "macOS")
            }
            guard let simName = extractSimulatorName(from: value) else {
                return Check("Dest: \(name)", .ok, value)
            }
            return installedSimulators.contains(simName)
                ? Check("Dest: \(name)", .ok, simName)
                : Check(
                    "Dest: \(name)",
                    .fail,
                    "\(simName) not found. Run 'xc destinations' to see available simulators."
                )
        }
    }

    static func formatterCheck() -> Check {
        CommandRunner.findInPath("xcbeautify") != nil
            ? Check("xcbeautify", .ok)
            : Check("xcbeautify", .warn, "Not installed. Output will be raw. Install: brew install xcbeautify")
    }

    static func globalConfigCheck(path: String? = ConfigLoader.globalConfigPath()) -> Check {
        guard let path else { return Check("Global config", .skip, "not found (optional)") }
        do {
            _ = try ConfigLoader.loadGlobalConfig(at: path)
            return Check("Global config", .ok, (path as NSString).abbreviatingWithTildeInPath)
        } catch {
            return Check("Global config", .warn, "Parse error: \(error.localizedDescription)")
        }
    }

    /// Each member has a loadable xc.yaml.
    static func memberChecks(_ config: ProjectConfig, projectRoot: String) -> [Check] {
        ConfigLoader.members(of: config, root: projectRoot).map { member in
            do {
                _ = try ConfigLoader.loadExact(from: member.directory)
                return Check("Member: \(member.name)", .ok, member.path)
            } catch {
                return Check("Member: \(member.name)", .fail, "\(member.path) — \(error.localizedDescription)")
            }
        }
    }

    static func printCheck(_ check: Check) {
        let statusLabel = check.status.label.padding(toLength: 4, withPad: " ", startingAt: 0)
        if let detail = check.detail {
            print("  \(statusLabel)  \(check.name)\t\(detail)")
        } else {
            print("  \(statusLabel)  \(check.name)")
        }
    }

    // MARK: - Queries

    static func querySchemes(_ projectConfig: ProjectConfig, projectRoot: String) async -> [String]? {
        await Schemes.list(containerArgs: projectConfig.containerArgs, in: projectRoot)
    }

    static func queryInstalledSimulatorNames() async -> Set<String> {
        await Set(Simulators.available().values.joined())
    }

    // MARK: - Helpers

    /// Collect all scheme names referenced in defaults + commands + variants.
    static func collectSchemes(from config: ProjectConfig) -> Set<String> {
        var schemes = Set<String>()
        if let s = config.defaults?.scheme {
            schemes.insert(s)
        }
        for (_, cmd) in config.commands ?? [:] {
            if let s = cmd.scheme {
                schemes.insert(s)
            }
            for (_, variant) in cmd.variants ?? [:] {
                if let s = variant.scheme {
                    schemes.insert(s)
                }
            }
        }
        return schemes
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
}
