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

    @Flag(name: .long, help: "Run the command in every member project")
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

        // Root config — honoring -C/--directory (walks up like a plain `cd dir && xc`).
        let rootConfig = try ConfigLoader.load(from: directory)

        // Shape 3 — fan-out across members.
        if all || members != nil {
            try runFanOut(command: command, rootConfig: rootConfig)
            return
        }

        // Shape 2 — member-addressed command "member/command[:variant]".
        let (memberName, commandToken) = Self.parseMemberPath(command)
        let config = try memberName.map { try loadMember($0, rootConfig: rootConfig) } ?? rootConfig

        try execute(commandToken, config: config)
    }

    // MARK: - Single execution

    /// Resolve and run one command against a loaded config, with its own directory as cwd.
    private func execute(_ commandString: String, config: ConfigLoader.LoadedConfig) throws {
        let (commandName, variantName) = Self.parseCommand(commandString)

        let resolved = try CommandResolver.resolve(
            commandName: commandName,
            variant: variantName,
            config: config,
            destOverride: dest,
            extraArgs: passthroughArgs
        )

        let projectRoot = config.projectRoot

        if dryRun {
            print(resolved.script ?? Self.shellEscape(resolved.invocation))
            return
        }

        if let preHook = resolved.hooks?.pre {
            try HookRunner.run(preHook, label: "pre-\(commandName)", workingDirectory: projectRoot)
        }

        if verbose {
            print("$ \(resolved.script ?? Self.shellEscape(resolved.invocation))")
            fflush(stdout)
        }

        if let script = resolved.script {
            try HookRunner.run(script, label: commandName, workingDirectory: projectRoot, quiet: true)
        } else {
            let formatter = raw ? nil : resolved.formatter
            try CommandRunner.exec(args: resolved.invocation, formatter: formatter, workingDirectory: projectRoot)
        }

        if let postHook = resolved.hooks?.post {
            try HookRunner.run(postHook, label: "post-\(commandName)", workingDirectory: projectRoot)
        }
    }

    // MARK: - Members

    private func loadMember(_ name: String, rootConfig: ConfigLoader.LoadedConfig) throws -> ConfigLoader.LoadedConfig {
        guard let dir = ConfigLoader.memberDirectory(name, config: rootConfig.project, projectRoot: rootConfig.projectRoot) else {
            throw XCError.unknownMember(name, available: ConfigLoader.memberNames(rootConfig.project))
        }
        do {
            return try ConfigLoader.loadExact(from: dir)
        } catch {
            throw XCError.memberFailed(name, underlying: Self.message(error))
        }
    }

    /// Shape 3 — run `command` in each selected member, sequentially.
    private func runFanOut(command: String, rootConfig: ConfigLoader.LoadedConfig) throws {
        let available = ConfigLoader.memberNames(rootConfig.project)
        guard !available.isEmpty else {
            throw XCError.invalidConfig("No members defined. Add a 'members' section to use --all/--members.")
        }

        let targets = try Self.selectMembers(all: all, list: members, available: available)
        let (commandName, _) = Self.parseCommand(command)

        var failed: [String] = []
        var ran = 0

        for name in targets {
            let memberConfig: ConfigLoader.LoadedConfig
            do {
                memberConfig = try loadMember(name, rootConfig: rootConfig)
            } catch {
                Self.announce("==> \(name): \(Self.message(error))")
                failed.append(name)
                if !continueOnFailure { throw XCError.fanOutFailed(failed) }
                continue
            }

            // Members legitimately differ — skip those that don't define this command.
            guard (memberConfig.project.commands ?? [:])[commandName] != nil else {
                Self.announce("==> \(name) — skipped (no '\(commandName)')")
                continue
            }

            // Flush before handing the terminal to a child process so headers stay ordered.
            Self.announce("==> \(name)")
            ran += 1
            do {
                try execute(command, config: memberConfig)
            } catch {
                Self.announce("✗ \(name): \(Self.message(error))")
                failed.append(name)
                if !continueOnFailure { throw XCError.fanOutFailed(failed) }
            }
        }

        if !failed.isEmpty { throw XCError.fanOutFailed(failed) }
        if ran == 0 { print("No selected member defines '\(commandName)'.") }
    }

    // MARK: - Parsing helpers

    static func shellEscape(_ args: [String]) -> String {
        args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    /// Split "command:variant" into its parts. The first ":" separates them.
    static func parseCommand(_ input: String) -> (command: String, variant: String?) {
        let parts = input.split(separator: ":", maxSplits: 1)
        let command = String(parts[0])
        let variant = parts.count > 1 ? String(parts[1]) : nil
        return (command, variant)
    }

    /// Split "member/command[:variant]" into the member name and the remaining command token.
    /// Returns a nil member when there is no "/".
    static func parseMemberPath(_ input: String) -> (member: String?, command: String) {
        guard let slash = input.firstIndex(of: "/") else { return (nil, input) }
        let member = String(input[..<slash])
        let command = String(input[input.index(after: slash)...])
        return (member.isEmpty ? nil : member, command)
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

    static func message(_ error: Error) -> String {
        (error as? XCError)?.errorDescription ?? error.localizedDescription
    }

    /// Print a line and flush, so buffered Swift output stays ordered relative to child-process output.
    static func announce(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
