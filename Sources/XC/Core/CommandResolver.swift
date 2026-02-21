enum CommandResolver {
    struct ResolvedCommand: Sendable {
        let invocation: [String]
        let script: String?
        let hooks: HookConfig?
        let formatter: String?
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

        let hooks = variantConfig?.hooks ?? commandConfig.hooks
        let formatter = config.project.settings?.formatter
            ?? config.global?.settings?.formatter

        // Check if this is a script command
        let script = variantConfig?.run ?? commandConfig.run
        if let script {
            var fullScript = script
            let scriptExtraArgs = variantConfig?.extraArgs ?? commandConfig.extraArgs ?? []
            let allArgs = scriptExtraArgs + extraArgs
            if !allArgs.isEmpty {
                fullScript += " " + allArgs.joined(separator: " ")
            }
            return ResolvedCommand(invocation: [], script: fullScript, hooks: hooks, formatter: formatter)
        }

        // xcodebuild command — layer: variant > command > project defaults > global defaults
        let scheme = variantConfig?.scheme
            ?? commandConfig.scheme
            ?? config.project.defaults?.scheme
            ?? config.global?.defaults?.scheme

        let configuration = variantConfig?.configuration
            ?? commandConfig.configuration
            ?? config.project.defaults?.configuration
            ?? config.global?.defaults?.configuration

        let rawDest: OneOrMany? = destOverride.map { OneOrMany($0) }
            ?? variantConfig?.destination
            ?? commandConfig.destination
            ?? config.project.defaults?.destination
            ?? config.global?.defaults?.destination

        let testPlan = variantConfig?.testPlan
            ?? commandConfig.testPlan
            ?? config.project.defaults?.testPlan
            ?? config.global?.defaults?.testPlan

        let resultBundlePath = variantConfig?.resultBundlePath
            ?? commandConfig.resultBundlePath
            ?? config.project.defaults?.resultBundlePath
            ?? config.global?.defaults?.resultBundlePath

        let xcconfig = variantConfig?.xcconfig
            ?? commandConfig.xcconfig
            ?? config.project.defaults?.xcconfig
            ?? config.global?.defaults?.xcconfig

        let derivedDataPath = variantConfig?.derivedDataPath
            ?? commandConfig.derivedDataPath
            ?? config.project.defaults?.derivedDataPath
            ?? config.global?.defaults?.derivedDataPath

        let archivePath = variantConfig?.archivePath
            ?? commandConfig.archivePath

        let configExtraArgs = variantConfig?.extraArgs
            ?? commandConfig.extraArgs
            ?? []

        let resolvedDests = resolveDestinations(rawDest, destinations: config.project.destinations)

        let action = xcodebuildAction(for: commandName)

        var args = ["xcodebuild", action]

        if let project = config.project.project {
            args += ["-project", project]
        } else if let workspace = config.project.workspace {
            args += ["-workspace", workspace]
        }

        if let xcconfig { args += ["-xcconfig", xcconfig] }
        if let scheme { args += ["-scheme", scheme] }
        if let configuration { args += ["-configuration", configuration] }
        for dest in resolvedDests {
            args += ["-destination", dest]
        }

        if let derivedDataPath { args += ["-derivedDataPath", derivedDataPath] }

        if action == "test" || action == "test-without-building" {
            if let testPlan { args += ["-testPlan", testPlan] }
            if let resultBundlePath { args += ["-resultBundlePath", resultBundlePath] }
        }

        if let archivePath, action == "archive" {
            args += ["-archivePath", archivePath]
        }

        args += configExtraArgs
        args += extraArgs

        return ResolvedCommand(invocation: args, script: nil, hooks: hooks, formatter: formatter)
    }

    static func xcodebuildAction(for command: String) -> String {
        command
    }

    static func resolveDestinations(_ raw: OneOrMany?, destinations: [String: String]?) -> [String] {
        guard let raw else { return [] }
        return raw.values.map { destinations?[$0] ?? $0 }
    }
}
