import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute a configured command"
    )

    @Argument(help: "Command to run, optionally with variant (e.g. build, test, build:release)")
    var command: String?

    @Flag(name: .long, help: "Show raw xcodebuild output without formatting")
    var raw: Bool = false

    @Flag(name: .shortAndLong, help: "Show the resolved xcodebuild invocation")
    var verbose: Bool = false

    @Flag(name: .long, help: "Print the resolved command without executing it")
    var dryRun: Bool = false

    @Option(name: .long, help: "Override destination (name or raw destination string)")
    var dest: String?

    @Argument(parsing: .postTerminator)
    var passthroughArgs: [String] = []

    func run() async throws {
        guard let command else {
            try ListCommand.printCommands()
            return
        }

        let (commandName, variantName) = Self.parseCommand(command)

        let config = try ConfigLoader.load()

        let resolved = try CommandResolver.resolve(
            commandName: commandName,
            variant: variantName,
            config: config,
            destOverride: dest,
            extraArgs: passthroughArgs
        )

        let projectRoot = config.projectRoot

        // Dry-run: print the resolved command and exit
        if dryRun {
            if let script = resolved.script {
                print(script)
            } else {
                print(Self.shellEscape(resolved.invocation))
            }
            return
        }

        // Pre-hook
        if let preHook = resolved.hooks?.pre {
            try HookRunner.run(preHook, label: "pre-\(commandName)", workingDirectory: projectRoot)
        }

        // Verbose
        if verbose {
            if let script = resolved.script {
                print("$ \(script)")
            } else {
                print("$ \(Self.shellEscape(resolved.invocation))")
            }
            fflush(stdout)
        }

        // Execute
        if let script = resolved.script {
            try HookRunner.run(script, label: commandName, workingDirectory: projectRoot, quiet: true)
        } else {
            let formatter = raw ? nil : resolved.formatter
            try CommandRunner.exec(args: resolved.invocation, formatter: formatter, workingDirectory: projectRoot)
        }

        // Post-hook
        if let postHook = resolved.hooks?.post {
            try HookRunner.run(postHook, label: "post-\(commandName)", workingDirectory: projectRoot)
        }
    }

    static func shellEscape(_ args: [String]) -> String {
        args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    static func parseCommand(_ input: String) -> (command: String, variant: String?) {
        let parts = input.split(separator: ":", maxSplits: 1)
        let command = String(parts[0])
        let variant = parts.count > 1 ? String(parts[1]) : nil
        return (command, variant)
    }
}
