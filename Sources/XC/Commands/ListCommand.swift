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

        guard !commands.isEmpty else {
            print("No commands defined in xc.yaml.")
            return
        }

        for (name, command) in commands.sorted(by: { $0.key < $1.key }) {
            let summary = summarizeCommand(command)
            if summary.isEmpty {
                print(name)
            } else {
                print("\(name)\t\(summary)")
            }

            let variants = command.variants ?? [:]
            for (variantName, variant) in variants.sorted(by: { $0.key < $1.key }) {
                let variantSummary = summarizeVariant(variant)
                if variantSummary.isEmpty {
                    print("  :\(variantName)")
                } else {
                    print("  :\(variantName)\t\(variantSummary)")
                }
            }
        }
    }

    static func summarizeCommand(_ command: CommandConfig) -> String {
        if let run = command.run {
            return "run: \(run)"
        }
        return summarizeVariant(command)
    }

    static func summarizeVariant(_ variant: CommandConfig) -> String {
        var parts: [String] = []

        if let run = variant.run {
            parts.append("run: \(run)")
            return parts.joined(separator: ", ")
        }
        if let scheme = variant.scheme {
            parts.append("scheme: \(scheme)")
        }
        if let config = variant.configuration {
            parts.append("configuration: \(config)")
        }
        if let dest = variant.destination {
            let display = dest.values.joined(separator: ", ")
            parts.append("destination: \(display)")
        }
        if let testPlan = variant.testPlan {
            parts.append("test-plan: \(testPlan)")
        }
        if let rbp = variant.resultBundlePath {
            parts.append("result-bundle-path: \(rbp)")
        }
        if let xcconfig = variant.xcconfig {
            parts.append("xcconfig: \(xcconfig)")
        }
        if let ddp = variant.derivedDataPath {
            parts.append("derived-data-path: \(ddp)")
        }
        if let args = variant.extraArgs, !args.isEmpty {
            parts.append("extra-args: \(args.joined(separator: " "))")
        }

        return parts.joined(separator: ", ")
    }
}
