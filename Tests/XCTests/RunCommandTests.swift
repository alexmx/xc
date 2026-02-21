import Testing
@testable import xc

@Suite("RunCommand Tests")
struct RunCommandTests {
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

    @Test("shellEscape with simple args")
    func shellEscapeSimple() {
        let result = RunCommand.shellEscape(["xcodebuild", "build"])
        #expect(result == "xcodebuild build")
    }

    @Test("shellEscape quotes args with spaces")
    func shellEscapeSpaces() {
        let result = RunCommand.shellEscape(["-destination", "platform=iOS Simulator,name=iPhone 17 Pro"])
        #expect(result == "-destination \"platform=iOS Simulator,name=iPhone 17 Pro\"")
    }

    @Test("shellEscape with empty array")
    func shellEscapeEmpty() {
        let result = RunCommand.shellEscape([])
        #expect(result == "")
    }

    @Test("shellEscape with mixed args")
    func shellEscapeMixed() {
        let result = RunCommand.shellEscape(["xcodebuild", "build", "-scheme", "My App"])
        #expect(result == "xcodebuild build -scheme \"My App\"")
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
