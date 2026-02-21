import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute a configured command"
    )

    @Argument(help: "Command to run, optionally with variant (e.g. build, test, build:release)")
    var command: String

    @Flag(name: .long, help: "Show raw xcodebuild output without formatting")
    var raw: Bool = false

    @Flag(name: .shortAndLong, help: "Show the resolved xcodebuild invocation")
    var verbose: Bool = false

    @Option(name: .long, help: "Override destination (name or raw destination string)")
    var dest: String?

    @Argument(parsing: .postTerminator)
    var passthroughArgs: [String] = []

    func run() async throws {
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

        if let preHook = resolved.hooks?.pre {
            try HookRunner.run(preHook, label: "pre-\(commandName)", workingDirectory: projectRoot)
        }

        if verbose {
            let shellSafe = resolved.invocation.map { arg in
                arg.contains(" ") ? "\"\(arg)\"" : arg
            }.joined(separator: " ")
            print("$ \(shellSafe)")
            fflush(stdout)
        }

        let useFormatter = !raw && resolved.formatter != "raw"
        try CommandRunner.exec(args: resolved.invocation, useFormatter: useFormatter, workingDirectory: projectRoot)

        if let postHook = resolved.hooks?.post {
            try HookRunner.run(postHook, label: "post-\(commandName)", workingDirectory: projectRoot)
        }
    }

    static func parseCommand(_ input: String) -> (command: String, variant: String?) {
        let parts = input.split(separator: ":", maxSplits: 1)
        let command = String(parts[0])
        let variant = parts.count > 1 ? String(parts[1]) : nil
        return (command, variant)
    }
}
