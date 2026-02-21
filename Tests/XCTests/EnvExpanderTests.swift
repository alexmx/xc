import Testing
@testable import xc

@Suite("EnvExpander Tests")
struct EnvExpanderTests {
    // MARK: - expand

    @Test("no variables returns string unchanged")
    func noVariables() {
        #expect(EnvExpander.expand("hello world") == "hello world")
    }

    @Test("expands known environment variable")
    func expandKnown() {
        // HOME is always set on macOS
        let result = EnvExpander.expand("dir=${HOME}/config")
        #expect(result.contains("/Users/") || result.contains("/var/"))
        #expect(result.hasSuffix("/config"))
        #expect(!result.contains("${"))
    }

    @Test("unknown variable expands to empty string")
    func expandUnknown() {
        let result = EnvExpander.expand("val=${XC_TEST_NONEXISTENT_VAR_12345}")
        #expect(result == "val=")
    }

    @Test("default value used when variable is not set")
    func expandDefault() {
        let result = EnvExpander.expand("${XC_TEST_NONEXISTENT_VAR_12345:-fallback}")
        #expect(result == "fallback")
    }

    @Test("default value ignored when variable is set")
    func expandSetOverridesDefault() {
        // HOME is always set
        let result = EnvExpander.expand("${HOME:-/tmp}")
        #expect(result != "/tmp")
        #expect(!result.isEmpty)
    }

    @Test("multiple variables in one string")
    func expandMultiple() {
        let result = EnvExpander.expand("${XC_TEST_NONEXISTENT_A:-a} and ${XC_TEST_NONEXISTENT_B:-b}")
        #expect(result == "a and b")
    }

    @Test("bare dollar sign is not expanded")
    func bareDollar() {
        #expect(EnvExpander.expand("cost is $5") == "cost is $5")
    }

    @Test("unclosed brace treated as literal")
    func unclosedBrace() {
        #expect(EnvExpander.expand("${UNCLOSED") == "${UNCLOSED")
    }

    @Test("empty variable name expands to empty")
    func emptyVarName() {
        #expect(EnvExpander.expand("${}") == "")
    }

    @Test("default value can contain special characters")
    func defaultWithSpecialChars() {
        let result = EnvExpander.expand("${XC_TEST_NONEXISTENT:-platform=iOS Simulator,name=iPhone 17 Pro}")
        #expect(result == "platform=iOS Simulator,name=iPhone 17 Pro")
    }

    // MARK: - parseVarExpression

    @Test("parseVarExpression with no default")
    func parseNoDefault() {
        let (name, def) = EnvExpander.parseVarExpression("MY_VAR")
        #expect(name == "MY_VAR")
        #expect(def == nil)
    }

    @Test("parseVarExpression with default")
    func parseWithDefault() {
        let (name, def) = EnvExpander.parseVarExpression("MY_VAR:-hello")
        #expect(name == "MY_VAR")
        #expect(def == "hello")
    }

    @Test("parseVarExpression with empty default")
    func parseEmptyDefault() {
        let (name, def) = EnvExpander.parseVarExpression("MY_VAR:-")
        #expect(name == "MY_VAR")
        #expect(def == "")
    }

    // MARK: - Config expansion

    @Test("ProjectConfig expands env vars in all fields")
    func projectConfigExpansion() {
        let config = ProjectConfig(
            project: "${XC_TEST_NONEXISTENT:-MyApp.xcodeproj}",
            destinations: [
                "sim": "${XC_TEST_NONEXISTENT:-platform=iOS Simulator,name=iPhone 17 Pro}"
            ],
            defaults: CommandConfig(scheme: "${XC_TEST_NONEXISTENT:-DefaultScheme}"),
            commands: [
                "build": CommandConfig(
                    configuration: "${XC_TEST_NONEXISTENT:-Debug}",
                    variants: [
                        "release": CommandConfig(configuration: "${XC_TEST_NONEXISTENT:-Release}")
                    ]
                )
            ]
        )

        let expanded = config.expandingEnvVars()
        #expect(expanded.project == "MyApp.xcodeproj")
        #expect(expanded.destinations?["sim"] == "platform=iOS Simulator,name=iPhone 17 Pro")
        #expect(expanded.defaults?.scheme == "DefaultScheme")
        #expect(expanded.commands?["build"]?.configuration == "Debug")
        #expect(expanded.commands?["build"]?.variants?["release"]?.configuration == "Release")
    }

    @Test("HookConfig expands env vars")
    func hookConfigExpansion() {
        let hooks = HookConfig(
            pre: "${XC_TEST_NONEXISTENT:-swiftlint lint}",
            post: "${XC_TEST_NONEXISTENT:-echo done}"
        )
        let expanded = hooks.expandingEnvVars()
        #expect(expanded.pre == "swiftlint lint")
        #expect(expanded.post == "echo done")
    }
}
