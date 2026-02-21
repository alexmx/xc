@testable import xc
import Testing

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
}
