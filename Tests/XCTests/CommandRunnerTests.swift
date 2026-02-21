import Testing
@testable import xc

@Suite("CommandRunner Tests")
struct CommandRunnerTests {
    @Test("resolveFormatter with raw returns nil")
    func resolveFormatterRaw() {
        let result = CommandRunner.resolveFormatter("raw")
        #expect(result == nil)
    }

    @Test("resolveFormatter with custom command returns it as-is")
    func resolveFormatterCustom() {
        let result = CommandRunner.resolveFormatter("xcbeautify --disable-logging")
        #expect(result == "xcbeautify --disable-logging")
    }

    @Test("resolveFormatter with xcpretty returns it as-is")
    func resolveFormatterXcpretty() {
        let result = CommandRunner.resolveFormatter("xcpretty")
        #expect(result == "xcpretty")
    }

    @Test("resolveFormatter nil and xcbeautify use same code path")
    func resolveFormatterNilMatchesXcbeautify() {
        let fromNil = CommandRunner.resolveFormatter(nil)
        let fromExplicit = CommandRunner.resolveFormatter("xcbeautify")
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
