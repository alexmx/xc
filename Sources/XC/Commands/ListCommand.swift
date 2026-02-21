import ArgumentParser

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show available commands and variants"
    )

    func run() throws {
        let config = try ConfigLoader.load()
        let commands = config.project.commands ?? [:]

        guard !commands.isEmpty else {
            print("No commands defined in xc.yaml.")
            return
        }

        for (name, command) in commands.sorted(by: { $0.key < $1.key }) {
            print(name)

            let variants = command.variants ?? [:]
            for (variantName, variant) in variants.sorted(by: { $0.key < $1.key }) {
                let summary = Self.summarizeVariant(variant)
                if summary.isEmpty {
                    print("  :\(variantName)")
                } else {
                    print("  :\(variantName)\t\(summary)")
                }
            }
        }
    }

    static func summarizeVariant(_ variant: CommandConfig) -> String {
        var parts: [String] = []

        if let scheme = variant.scheme {
            parts.append("scheme: \(scheme)")
        }
        if let config = variant.configuration {
            parts.append("configuration: \(config)")
        }
        if let dest = variant.destination {
            parts.append("destination: \(dest)")
        }
        if let args = variant.extraArgs, !args.isEmpty {
            parts.append("extra-args: \(args.joined(separator: " "))")
        }

        return parts.joined(separator: ", ")
    }
}
