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

    private let env = ["APP": "MyApp", "SIM": "iPhone 17 Pro", "FMT": "xcbeautify --quiet", "ON": "true"]

    @Test("every project config value expands, nested ones included")
    func projectConfigExpansion() throws {
        let yaml = """
        project: ${APP}.xcodeproj
        destinations:
          sim: "platform=iOS Simulator,name=${SIM}"
        defaults:
          scheme: ${APP}
          destination: [sim, "${UNSET:-mac}"]
        settings:
          formatter: ${FMT}
          verbose: ${ON}
        commands:
          build:
            configuration: ${UNSET:-Debug}
            extra-args: ["-derivedDataPath", "${APP}/DD"]
            hooks: { pre: "echo ${APP}" }
            variants:
              release: { configuration: "${UNSET:-Release}" }
        """
        let config = try ConfigLoader.decode(ProjectConfig.self, yaml: yaml, environment: env)
        #expect(config.project == "MyApp.xcodeproj")
        #expect(config.destinations?["sim"] == "platform=iOS Simulator,name=iPhone 17 Pro")
        #expect(config.defaults?.scheme == "MyApp")
        #expect(config.defaults?.destination == ["sim", "mac"])
        #expect(config.settings?.formatter == "xcbeautify --quiet")
        #expect(config.settings?.verbose == true)
        #expect(config.commands?["build"]?.configuration == "Debug")
        #expect(config.commands?["build"]?.extraArgs == ["-derivedDataPath", "MyApp/DD"])
        #expect(config.commands?["build"]?.hooks?.pre == "echo MyApp")
        #expect(config.commands?["build"]?.variants?["release"]?.configuration == "Release")
    }

    @Test("global config values expand")
    func globalConfigExpansion() throws {
        let yaml = """
        defaults:
          scheme: ${APP}
        settings:
          formatter: ${FMT}
        """
        let config = try ConfigLoader.decode(GlobalConfig.self, yaml: yaml, environment: env)
        #expect(config.defaults?.scheme == "MyApp")
        #expect(config.settings?.formatter == "xcbeautify --quiet")
    }

    @Test("keys stay literal")
    func keysNotExpanded() throws {
        let yaml = """
        destinations:
          ${APP}: "platform=macOS"
        commands:
          ${APP}: { run: "true" }
        """
        let config = try ConfigLoader.decode(ProjectConfig.self, yaml: yaml, environment: env)
        #expect(config.destinations?.keys.sorted() == ["${APP}"])
        #expect(config.commands?.keys.sorted() == ["${APP}"])
    }

    @Test("a value that expands to empty, null or ~ stays that string")
    func nullishExpansionStaysString() throws {
        let yaml = """
        commands:
          empty:
            run: ${UNSET}
          quoted:
            run: "${UNSET}"
          null:
            run: ${NULLISH}
          tilde:
            run: ${TILDE}
        """
        let environment = ["NULLISH": "null", "TILDE": "~"]
        let config = try ConfigLoader.decode(ProjectConfig.self, yaml: yaml, environment: environment)
        #expect(config.commands?["empty"]?.run == "")
        #expect(config.commands?["quoted"]?.run == "")
        #expect(config.commands?["null"]?.run == "null")
        #expect(config.commands?["tilde"]?.run == "~")
    }

    @Test("YAML anchors and merge keys still work")
    func mergeKeys() throws {
        let yaml = """
        defaults: &base
          scheme: ${APP}
        commands:
          build:
            <<: *base
            configuration: Release
        """
        let config = try ConfigLoader.decode(ProjectConfig.self, yaml: yaml, environment: env)
        #expect(config.commands?["build"]?.scheme == "MyApp")
        #expect(config.commands?["build"]?.configuration == "Release")
    }
}
