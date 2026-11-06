enum CommandResolver {
    struct ResolvedCommand: Sendable {
        enum Action: Equatable {
            /// A `run:` command, executed with `/bin/sh -c`.
            case script(String)
            /// An xcodebuild invocation (starting with "xcodebuild"); output is piped
            /// through `formatter`, the `settings.formatter` value (see `CommandRunner.formatterCommand`).
            case xcodebuild(arguments: [String], formatter: String?)
        }

        let action: Action
        let hooks: HookConfig?
    }

    static func resolve(
        commandName: String,
        variant: String?,
        config: ConfigLoader.LoadedConfig,
        destOverride: String?,
        extraArgs: [String]
    ) throws -> ResolvedCommand {
        let commands = config.project.commands ?? [:]
        guard let commandConfig = commands[commandName] else {
            throw XCError.unknownCommand(commandName, available: Array(commands.keys))
        }

        if let variant, commandConfig.variants?[variant] == nil {
            throw XCError.unknownVariant(commandName, variant, available: Array((commandConfig.variants ?? [:]).keys))
        }
        let variantConfig = variant.flatMap { commandConfig.variants?[$0] }

        // Most specific first. Some settings belong to the command alone; the rest fall
        // back to the project's and then the global config's defaults.
        let commandLayers = [variantConfig, commandConfig].compactMap(\.self)
        let allLayers = commandLayers + [config.project.defaults, config.global?.defaults].compactMap(\.self)

        let hooks = first(\.hooks, in: commandLayers)

        let configExtraArgs = first(\.extraArgs, in: commandLayers) ?? []

        // A `run:` makes this a script command.
        if let script = first(\.run, in: commandLayers) {
            var fullScript = script
            // Config-authored extraArgs are trusted (same authorship as the run string)
            // and may intentionally use shell syntax, so they are appended verbatim.
            if !configExtraArgs.isEmpty {
                fullScript += " " + configExtraArgs.joined(separator: " ")
            }
            // CLI passthrough args (after `--`) are untrusted: the script runs via
            // `/bin/sh -c`, so each arg must be shell-quoted or it gets re-parsed by
            // the shell (breaking on metacharacters, and opening an injection surface).
            if !extraArgs.isEmpty {
                fullScript += " " + extraArgs.map(shellQuote).joined(separator: " ")
            }
            return ResolvedCommand(action: .script(fullScript), hooks: hooks)
        }

        let scheme = first(\.scheme, in: allLayers)
        let configuration = first(\.configuration, in: allLayers)
        let rawDest = destOverride.map { OneOrMany($0) } ?? first(\.destination, in: allLayers)
        let testPlan = first(\.testPlan, in: allLayers)
        let resultBundlePath = first(\.resultBundlePath, in: allLayers)
        let xcconfig = first(\.xcconfig, in: allLayers)
        let derivedDataPath = first(\.derivedDataPath, in: allLayers)
        let archivePath = first(\.archivePath, in: commandLayers)

        let resolvedDests = resolveDestinations(rawDest, destinations: config.project.destinations)

        let action = commandName

        var args = ["xcodebuild", action] + config.project.containerArgs

        if let xcconfig {
            args += ["-xcconfig", xcconfig]
        }
        if let scheme {
            args += ["-scheme", scheme]
        }
        if let configuration {
            args += ["-configuration", configuration]
        }
        for dest in resolvedDests {
            args += ["-destination", dest]
        }

        if let derivedDataPath {
            args += ["-derivedDataPath", derivedDataPath]
        }

        if action == "test" || action == "test-without-building" {
            if let testPlan {
                args += ["-testPlan", testPlan]
            }
            if let resultBundlePath {
                args += ["-resultBundlePath", resultBundlePath]
            }
        }

        if let archivePath, action == "archive" {
            args += ["-archivePath", archivePath]
        }

        args += configExtraArgs
        args += extraArgs

        let formatter = config.project.settings?.formatter ?? config.global?.settings?.formatter
        return ResolvedCommand(action: .xcodebuild(arguments: args, formatter: formatter), hooks: hooks)
    }

    /// The setting from the first layer that sets it.
    static func first<Value>(_ setting: KeyPath<CommandConfig, Value?>, in layers: [CommandConfig]) -> Value? {
        layers.lazy.compactMap { $0[keyPath: setting] }.first
    }

    /// POSIX-quote an argument so it survives re-parsing by `/bin/sh -c`.
    /// Shell-safe args are returned unchanged; anything else is wrapped in single
    /// quotes with embedded quotes escaped as `'\''` (close quote, escaped quote, reopen).
    static func shellQuote(_ arg: String) -> String {
        guard !arg.isEmpty else { return "''" }
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%_-+=:,./")
        if arg.allSatisfy({ safe.contains($0) }) {
            return arg
        }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func resolveDestinations(_ raw: OneOrMany?, destinations: [String: String]?) -> [String] {
        guard let raw else { return [] }
        return raw.values.map { destinations?[$0] ?? $0 }
    }
}
