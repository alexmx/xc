import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute a configured command"
    )

    @Argument(help: "Command to run, optionally with variant or member (e.g. build, test:ci, core/build)")
    var command: String?

    @Flag(name: .long, help: "Show raw xcodebuild output without formatting")
    var raw: Bool = false

    @Flag(name: .shortAndLong, help: "Show the resolved xcodebuild invocation")
    var verbose: Bool = false

    @Flag(name: .long, help: "Print the resolved command without executing it")
    var dryRun: Bool = false

    @Option(name: .long, help: "Override destination (name or raw destination string)")
    var dest: String?

    @Option(
        name: [.customShort("C"), .customLong("directory")],
        help: "Run as if in this directory, using its xc.yaml"
    )
    var directory: String?

    @Flag(name: .long, help: "Run the command in the root project and every member")
    var all: Bool = false

    @Option(name: .long, help: "Comma-separated member names to run the command in")
    var members: String?

    @Flag(name: .customLong("continue"), help: "When fanning out, continue after a member fails")
    var continueOnFailure: Bool = false

    @Argument(parsing: .postTerminator)
    var passthroughArgs: [String] = []

    func run() async throws {
        guard let command else {
            try ListCommand.printCommands()
            return
        }

        let ref = try CommandRef(parsing: command)

        // Root config — honoring -C/--directory (walks up like a plain `cd dir && xc`).
        let rootConfig = try ConfigLoader.load(from: directory)

        // Fan-out across members.
        if all || members != nil {
            guard ref.member == nil else {
                throw XCError.invalidCommand(command, reason: "use either member/command or --all/--members, not both")
            }
            try await runFanOut(ref, rootConfig: rootConfig)
            return
        }

        // A member-addressed command, "member/command[:variant]", runs in that member.
        let config = try ref.member.map { try loadMember($0, rootConfig: rootConfig) } ?? rootConfig
        try await execute(ref, config: config)
    }

    // MARK: - Single execution

    /// Resolve and run one command against a loaded config, with its own directory as cwd.
    private func execute(_ ref: CommandRef, config: ConfigLoader.LoadedConfig) async throws {
        let commandName = ref.name
        let resolved = try CommandResolver.resolve(
            commandName: commandName,
            variant: ref.variant,
            config: config,
            destOverride: dest,
            extraArgs: passthroughArgs
        )

        let projectRoot = config.projectRoot
        let environment = config.environment

        if dryRun {
            print(Self.commandLine(resolved.action))
            return
        }

        if let preHook = resolved.hooks?.pre {
            try await runHook(preHook, label: "pre-\(commandName)", config: config)
        }

        if Self.isVerbose(flag: verbose, config: config) {
            print("$ \(Self.commandLine(resolved.action))")
            fflush(stdout)
        }

        switch resolved.action {
        case .script(let script):
            if let code = try await ShellRunner.run(script, in: projectRoot, environment: environment) {
                throw XCError.scriptFailed(commandName, code)
            }
        case .xcodebuild(let arguments, let configuredFormatter):
            try await CommandRunner.exec(
                args: arguments,
                formatter: Self.formatterCommand(raw: raw, configured: configuredFormatter),
                workingDirectory: projectRoot,
                environment: environment
            )
        }

        if let postHook = resolved.hooks?.post {
            try await runHook(postHook, label: "post-\(commandName)", config: config)
        }
    }

    private func runHook(_ script: String, label: String, config: ConfigLoader.LoadedConfig) async throws {
        Self.announce("→ Running \(label) hook...")
        if let code = try await ShellRunner.run(script, in: config.projectRoot, environment: config.environment) {
            throw XCError.hookFailed(label, code)
        }
    }

    // MARK: - Members

    private func loadMember(_ name: String, rootConfig: ConfigLoader.LoadedConfig) throws -> ConfigLoader.LoadedConfig {
        let members = ConfigLoader.members(of: rootConfig.project, root: rootConfig.projectRoot)
        guard let member = members.first(where: { $0.name == name }) else {
            throw XCError.unknownMember(name, available: members.map(\.name))
        }
        do {
            return try ConfigLoader.loadExact(from: member.directory)
        } catch {
            throw XCError.memberFailed(name, underlying: error.localizedDescription)
        }
    }

    /// Run `ref` in each selected target, sequentially.
    private func runFanOut(_ ref: CommandRef, rootConfig: ConfigLoader.LoadedConfig) async throws {
        let available = ConfigLoader.members(of: rootConfig.project, root: rootConfig.projectRoot).map(\.name)
        guard !available.isEmpty else {
            throw XCError.invalidConfig("No members defined. Add a 'members' section to use --all/--members.")
        }

        let targets = try Self.fanOutTargetNames(all: all, list: members, available: available)
        let commandName = ref.name

        var failed: [String] = []
        var ran = 0

        for target in targets {
            let isRoot = target == Self.rootTarget
            let label = isRoot ? "root" : target

            let config: ConfigLoader.LoadedConfig
            do {
                config = isRoot ? rootConfig : try loadMember(target, rootConfig: rootConfig)
            } catch {
                Self.announce("==> \(label): \(error.localizedDescription)")
                failed.append(label)
                if !continueOnFailure {
                    throw XCError.fanOutFailed(failed)
                }
                continue
            }

            // Targets legitimately differ, so skip those that don't define this command.
            guard (config.project.commands ?? [:])[commandName] != nil else {
                Self.announce("==> \(label) (skipped: no '\(commandName)')")
                continue
            }

            // Flush before handing the terminal to a child process so headers stay ordered.
            Self.announce("==> \(label)")
            ran += 1
            do {
                try await execute(ref, config: config)
            } catch {
                Self.announce("✗ \(label): \(error.localizedDescription)")
                failed.append(label)
                if !continueOnFailure {
                    throw XCError.fanOutFailed(failed)
                }
            }
        }

        if !failed.isEmpty {
            throw XCError.fanOutFailed(failed)
        }
        if ran == 0 {
            print("No selected target defines '\(commandName)'.")
        }
    }

    // MARK: - Parsing helpers

    /// The command to pipe xcodebuild output through, or nil: `--raw` turns formatting off
    /// whatever `settings.formatter` says.
    static func formatterCommand(raw: Bool, configured: String?) -> String? {
        raw ? nil : CommandRunner.formatterCommand(for: configured)
    }

    /// `-v`, or `settings.verbose` (the project's overriding the global config's).
    static func isVerbose(flag: Bool, config: ConfigLoader.LoadedConfig) -> Bool {
        flag || (config.project.settings?.verbose ?? config.global?.settings?.verbose ?? false)
    }

    /// What `--dry-run` and `-v` print for a resolved command: a line that pastes back
    /// into a shell as the same command.
    static func commandLine(_ action: CommandResolver.ResolvedCommand.Action) -> String {
        switch action {
        case .script(let script): script
        case .xcodebuild(let arguments, _): arguments.map(CommandResolver.shellQuote).joined(separator: " ")
        }
    }

    /// Internal label for the root project as a fan-out target. Members can't be named ".".
    static let rootTarget = "."

    /// Ordered fan-out targets. `--all` means all: the root project first, then every member.
    /// An explicit `--members` list selects those members only (root excluded).
    static func fanOutTargetNames(all: Bool, list: String?, available: [String]) throws -> [String] {
        let members = try selectMembers(all: all, list: list, available: available)
        return all ? [rootTarget] + members : members
    }

    /// Resolve the set of members to fan out over from `--all`/`--members`, validating names.
    static func selectMembers(all: Bool, list: String?, available: [String]) throws -> [String] {
        guard let list else { return available }
        let requested = list
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for name in requested where !available.contains(name) {
            throw XCError.unknownMember(name, available: available)
        }
        // Preserve the declared order, deduplicated.
        return available.filter { requested.contains($0) }
    }

    /// Print a line and flush, so buffered Swift output stays ordered relative to child-process output.
    static func announce(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
