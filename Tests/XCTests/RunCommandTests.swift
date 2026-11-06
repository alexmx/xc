import Testing
@testable import xc

@Suite("RunCommand Tests")
struct RunCommandTests {
    private func config(project: Bool?, global: Bool?) -> ConfigLoader.LoadedConfig {
        ConfigLoader.LoadedConfig(
            project: ProjectConfig(settings: Settings(verbose: project)),
            global: GlobalConfig(settings: Settings(verbose: global)),
            projectRoot: "/p"
        )
    }

    @Test("settings.verbose turns on -v, the project setting overriding the global one", arguments: [
        (false, nil, nil, false),
        (false, true, nil, true),
        (false, nil, true, true),
        (false, false, true, false),
        (false, true, false, true),
        (true, false, false, true)
    ] as [(Bool, Bool?, Bool?, Bool)])
    func verboseSetting(flag: Bool, project: Bool?, global: Bool?, expected: Bool) {
        #expect(RunCommand.isVerbose(flag: flag, config: config(project: project, global: global)) == expected)
    }

    @Test("--raw means no formatter, whatever is configured", arguments: [nil, "xcbeautify", "cat"])
    func rawMeansNoFormatter(configured: String?) {
        #expect(RunCommand.formatterCommand(raw: true, configured: configured) == nil)
    }

    @Test("without --raw the configured formatter becomes its command")
    func configuredFormatterKept() {
        #expect(RunCommand.formatterCommand(raw: false, configured: "xcbeautify --quiet") == "xcbeautify --quiet")
        #expect(RunCommand.formatterCommand(raw: false, configured: "raw") == nil)
        #expect(RunCommand.formatterCommand(raw: false, configured: nil) == CommandRunner.findInPath("xcbeautify"))
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
