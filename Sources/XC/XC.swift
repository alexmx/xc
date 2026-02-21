import ArgumentParser

@main
struct XC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A better way to run xcodebuild",
        version: xcVersion,
        subcommands: [RunCommand.self, DestinationsCommand.self, InitCommand.self, ListCommand.self],
        defaultSubcommand: RunCommand.self
    )
}
