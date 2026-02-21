import Testing
@testable import xc

@Suite("ListCommand Tests")
struct ListCommandTests {
    @Test("summarizeVariant with configuration only")
    func summarizeConfiguration() {
        let variant = CommandConfig(configuration: "Release")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "configuration: Release")
    }

    @Test("summarizeVariant with scheme only")
    func summarizeScheme() {
        let variant = CommandConfig(scheme: "Core")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "scheme: Core")
    }

    @Test("summarizeVariant with destination only")
    func summarizeDestination() {
        let variant = CommandConfig(destination: "sim-ipad")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "destination: sim-ipad")
    }

    @Test("summarizeVariant with extra-args")
    func summarizeExtraArgs() {
        let variant = CommandConfig(extraArgs: ["-enableCodeCoverage", "YES"])
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "extra-args: -enableCodeCoverage YES")
    }

    @Test("summarizeVariant with multiple fields")
    func summarizeMultiple() {
        let variant = CommandConfig(
            scheme: "Core",
            configuration: "Release",
            destination: "device"
        )
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "scheme: Core, configuration: Release, destination: device")
    }

    @Test("summarizeVariant with empty variant")
    func summarizeEmpty() {
        let variant = CommandConfig()
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "")
    }

    @Test("summarizeVariant with test-plan")
    func summarizeTestPlan() {
        let variant = CommandConfig(testPlan: "IntegrationTests")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "test-plan: IntegrationTests")
    }

    @Test("summarizeCommand shows run for script command")
    func summarizeScriptCommand() {
        let command = CommandConfig(run: "swiftlint lint --strict")
        let result = ListCommand.summarizeCommand(command)
        #expect(result == "$ swiftlint lint --strict")
    }

    @Test("summarizeVariant shows run for script variant")
    func summarizeScriptVariant() {
        let variant = CommandConfig(run: "swiftlint lint --fix")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "$ swiftlint lint --fix")
    }

    @Test("summarizeVariant with xcconfig")
    func summarizeXcconfig() {
        let variant = CommandConfig(xcconfig: "Release.xcconfig")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "xcconfig: Release.xcconfig")
    }

    @Test("summarizeVariant with derived-data-path")
    func summarizeDerivedDataPath() {
        let variant = CommandConfig(derivedDataPath: "./DerivedData")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "derived-data-path: ./DerivedData")
    }

    @Test("summarizeVariant with result-bundle-path")
    func summarizeResultBundlePath() {
        let variant = CommandConfig(resultBundlePath: "./build/tests.xcresult")
        let result = ListCommand.summarizeVariant(variant)
        #expect(result == "result-bundle-path: ./build/tests.xcresult")
    }

    @Test("summarizeParts returns empty array for empty config")
    func summarizePartsEmpty() {
        let config = CommandConfig()
        let parts = ListCommand.summarizeParts(config)
        #expect(parts.isEmpty)
    }

    @Test("summarizeParts returns array of formatted parts")
    func summarizePartsMultiple() {
        let config = CommandConfig(
            scheme: "App",
            configuration: "Release",
            destination: "sim"
        )
        let parts = ListCommand.summarizeParts(config)
        #expect(parts == ["scheme: App", "configuration: Release", "destination: sim"])
    }
}
