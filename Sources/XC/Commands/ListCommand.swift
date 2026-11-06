import ArgumentParser

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show available commands and variants"
    )

    func run() throws {
        try Self.printCommands()
    }

    static func printCommands() throws {
        let config = try ConfigLoader.load()
        let commands = config.project.commands ?? [:]

        // Calculate column width so summaries align across commands, variants, and defaults
        var prefixWidths: [Int] = [2 + "defaults".count] // "  defaults"
        for (name, command) in commands {
            prefixWidths.append(2 + name.count) // "  name"
            for variantName in (command.variants ?? [:]).keys {
                prefixWidths.append(4 + 1 + variantName.count) // "    :variant"
            }
        }
        let columnWidth = (prefixWidths.max() ?? 0) + 2

        // Show defaults if defined
        if let defaults = config.project.defaults {
            let summary = summarize(defaults)
            if !summary.isEmpty {
                let prefix = "  defaults".padding(toLength: columnWidth, withPad: " ", startingAt: 0)
                print("\(prefix) \(summary)")
                print()
            }
        }

        for (name, command) in commands.sorted(by: { $0.key < $1.key }) {
            let summary = summarize(command)
            let prefix = "  \(name)".padding(toLength: columnWidth, withPad: " ", startingAt: 0)
            if summary.isEmpty {
                print(prefix)
            } else {
                print("\(prefix) \(summary)")
            }

            let variants = command.variants ?? [:]
            for (variantName, variant) in variants.sorted(by: { $0.key < $1.key }) {
                let variantSummary = summarize(variant)
                let variantPrefix = "    :\(variantName)".padding(toLength: columnWidth, withPad: " ", startingAt: 0)
                if variantSummary.isEmpty {
                    print(variantPrefix)
                } else {
                    print("\(variantPrefix) \(variantSummary)")
                }
            }
        }

        printMembers(config)
    }

    /// List nested member projects and the commands each one exposes (addressable as `member/command`).
    static func printMembers(_ config: ConfigLoader.LoadedConfig) {
        let members = ConfigLoader.members(of: config.project, root: config.projectRoot)
        guard !members.isEmpty else { return }

        print()
        print("members:")
        for member in members {
            if let memberConfig = try? ConfigLoader.loadExact(from: member.directory) {
                let commandNames = (memberConfig.project.commands ?? [:]).keys.sorted()
                print("  \(member.name)  → \(member.path)")
                print("    \(commandNames.joined(separator: ", "))")
            } else {
                print("  \(member.name)  → \(member.path)  (unavailable — run 'xc doctor')")
            }
        }
    }

    /// One line describing a command, variant or the defaults: its `run:` script, or its settings.
    static func summarize(_ config: CommandConfig) -> String {
        if let run = config.run {
            return "$ \(run)"
        }
        return summarizeParts(config).joined(separator: ", ")
    }

    static func summarizeParts(_ config: CommandConfig) -> [String] {
        var parts: [String] = []
        if let scheme = config.scheme {
            parts.append("scheme: \(scheme)")
        }
        if let configuration = config.configuration {
            parts.append("configuration: \(configuration)")
        }
        if let dest = config.destination {
            let display = dest.values.joined(separator: ", ")
            parts.append("destination: \(display)")
        }
        if let testPlan = config.testPlan {
            parts.append("test-plan: \(testPlan)")
        }
        if let rbp = config.resultBundlePath {
            parts.append("result-bundle-path: \(rbp)")
        }
        if let xcconfig = config.xcconfig {
            parts.append("xcconfig: \(xcconfig)")
        }
        if let ddp = config.derivedDataPath {
            parts.append("derived-data-path: \(ddp)")
        }
        if let archivePath = config.archivePath {
            parts.append("archive-path: \(archivePath)")
        }
        if let args = config.extraArgs, !args.isEmpty {
            parts.append("extra-args: \(args.joined(separator: " "))")
        }
        return parts
    }
}
