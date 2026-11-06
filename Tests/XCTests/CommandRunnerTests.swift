import Testing
@testable import xc

@Suite("CommandRunner Tests")
struct CommandRunnerTests {
    @Test("formatterCommand with raw returns nil")
    func formatterCommandRaw() {
        let result = CommandRunner.formatterCommand(for: "raw")
        #expect(result == nil)
    }

    @Test("formatterCommand with custom command returns it as-is")
    func formatterCommandCustom() {
        let result = CommandRunner.formatterCommand(for: "xcbeautify --disable-logging")
        #expect(result == "xcbeautify --disable-logging")
    }

    @Test("formatterCommand with xcpretty returns it as-is")
    func formatterCommandXcpretty() {
        let result = CommandRunner.formatterCommand(for: "xcpretty")
        #expect(result == "xcpretty")
    }

    @Test("formatterCommand nil and xcbeautify use same code path")
    func formatterCommandNilMatchesXcbeautify() {
        let fromNil = CommandRunner.formatterCommand(for: nil)
        let fromExplicit = CommandRunner.formatterCommand(for: "xcbeautify")
        #expect(fromNil == fromExplicit)
    }

    @Test("findInPath returns path for known tool")
    func findInPathKnown() {
        let result = CommandRunner.findInPath("sh")
        #expect(result != nil)
        #expect(result?.contains("sh") == true)
    }

    @Test("findInPath returns nil for nonexistent tool")
    func findInPathUnknown() {
        let result = CommandRunner.findInPath("nonexistent-tool-that-does-not-exist")
        #expect(result == nil)
    }
}
