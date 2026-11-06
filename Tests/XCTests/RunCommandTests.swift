import Testing
@testable import xc

@Suite("RunCommand Tests")
struct RunCommandTests {
    @Test("--raw disables formatting even when none is configured")
    func rawDisablesDefaultFormatter() {
        let formatter = RunCommand.formatter(raw: true, configured: nil)
        #expect(formatter == "raw")
        #expect(CommandRunner.resolveFormatter(formatter) == nil)
    }

    @Test("--raw overrides a configured formatter")
    func rawOverridesConfiguredFormatter() {
        #expect(RunCommand.formatter(raw: true, configured: "xcbeautify --quiet") == "raw")
    }

    @Test("without --raw the configured formatter is kept")
    func configuredFormatterKept() {
        #expect(RunCommand.formatter(raw: false, configured: "xcbeautify --quiet") == "xcbeautify --quiet")
        #expect(RunCommand.formatter(raw: false, configured: nil) == nil)
    }

    @Test("parseCommand with no variant")
    func parseCommandNoVariant() {
        let (command, variant) = RunCommand.parseCommand("build")
        #expect(command == "build")
        #expect(variant == nil)
    }

    @Test("parseCommand with variant")
    func parseCommandWithVariant() {
        let (command, variant) = RunCommand.parseCommand("build:release")
        #expect(command == "build")
        #expect(variant == "release")
    }

    @Test("parseCommand with hyphenated variant")
    func parseCommandHyphenatedVariant() {
        let (command, variant) = RunCommand.parseCommand("build:my-custom")
        #expect(command == "build")
        #expect(variant == "my-custom")
    }

    @Test("parseCommand with colon in variant preserves rest")
    func parseCommandMultipleColons() {
        let (command, variant) = RunCommand.parseCommand("build:a:b")
        #expect(command == "build")
        #expect(variant == "a:b")
    }

    @Test("parseCommand with hyphenated command")
    func parseCommandHyphenated() {
        let (command, variant) = RunCommand.parseCommand("build-for-testing")
        #expect(command == "build-for-testing")
        #expect(variant == nil)
    }

    @Test("parseCommand with hyphenated command and variant")
    func parseCommandHyphenatedWithVariant() {
        let (command, variant) = RunCommand.parseCommand("build-for-testing:ci")
        #expect(command == "build-for-testing")
        #expect(variant == "ci")
    }

    private func line(_ arguments: [String]) -> String {
        RunCommand.commandLine(.xcodebuild(arguments: arguments, formatter: nil))
    }

    @Test("commandLine leaves shell-safe args bare")
    func commandLineSimple() {
        #expect(line(["xcodebuild", "build", "-scheme", "App"]) == "xcodebuild build -scheme App")
    }

    @Test("commandLine single-quotes args with spaces")
    func commandLineSpaces() {
        #expect(line(["-destination", "platform=iOS Simulator,name=iPhone 17 Pro"])
            == "-destination 'platform=iOS Simulator,name=iPhone 17 Pro'")
    }

    @Test("commandLine prints a script unchanged")
    func commandLineScript() {
        #expect(RunCommand.commandLine(.script("swiftlint lint | tee out")) == "swiftlint lint | tee out")
    }

    @Test("commandLine output pastes back into a shell as the same arguments")
    func commandLineRoundTrip() async throws {
        let arguments = ["OTHER_SWIFT_FLAGS=$(inherited) -DDEBUG", "a;b", "it's", "`whoami`", "*", "x&y", "\"q\"", ""]
        let output = try #require(await Capture.output("/bin/sh", ["-c", "printf '%s\\n' " + line(arguments)]))
        let printed = String(decoding: output, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(printed.dropLast().map(String.init) == arguments)
    }
}

@Suite("DestinationsCommand Tests")
struct DestinationsCommandTests {
    private let command = DestinationsCommand()

    @Test("formatRuntime parses iOS runtime ID")
    func formatRuntimeIOS() {
        let result = command.formatRuntime("com.apple.CoreSimulator.SimRuntime.iOS-18-5")
        #expect(result == "iOS 18.5")
    }

    @Test("formatRuntime parses tvOS runtime ID")
    func formatRuntimeTVOS() {
        let result = command.formatRuntime("com.apple.CoreSimulator.SimRuntime.tvOS-18-0")
        #expect(result == "tvOS 18.0")
    }

    @Test("formatRuntime parses watchOS runtime ID")
    func formatRuntimeWatchOS() {
        let result = command.formatRuntime("com.apple.CoreSimulator.SimRuntime.watchOS-11-2")
        #expect(result == "watchOS 11.2")
    }

    @Test("simulator platforms come from the runtime ID", arguments: [
        ("com.apple.CoreSimulator.SimRuntime.iOS-26-0", "iOS Simulator"),
        ("com.apple.CoreSimulator.SimRuntime.tvOS-18-0", "tvOS Simulator"),
        ("com.apple.CoreSimulator.SimRuntime.watchOS-11-2", "watchOS Simulator"),
        ("com.apple.CoreSimulator.SimRuntime.xrOS-2-3", "visionOS Simulator"),
        ("com.apple.CoreSimulator.SimRuntime.fooOS-1-0", "fooOS 1.0")
    ])
    func simulatorPlatform(runtimeID: String, platform: String) {
        #expect(command.simulatorPlatform(forRuntimeID: runtimeID) == platform)
    }

    @Test("formatRuntime parses visionOS runtime ID")
    func formatRuntimeVisionOS() {
        let result = command.formatRuntime("com.apple.CoreSimulator.SimRuntime.xrOS-2-3")
        #expect(result == "xrOS 2.3")
    }

    @Test("formatRuntime handles single version segment")
    func formatRuntimeSingleVersion() {
        let result = command.formatRuntime("com.apple.CoreSimulator.SimRuntime.iOS-26")
        #expect(result == "iOS 26")
    }
}
