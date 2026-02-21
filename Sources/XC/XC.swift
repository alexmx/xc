import ArgumentParser

@main
struct XC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A better way to run xcodebuild",
        subcommands: [RunCommand.self],
        defaultSubcommand: RunCommand.self
    )

    @Flag(name: .shortAndLong, help: "Show version")
    var version = false

    mutating func run() throws {
        if version {
            print(xcVersion)
        } else {
            throw CleanExit.helpRequest(self)
        }
    }
}
