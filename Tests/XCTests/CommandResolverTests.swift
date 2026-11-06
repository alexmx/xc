import Foundation
import Testing
@testable import xc

@Suite("CommandResolver Tests")
struct CommandResolverTests {
    // MARK: - Test Data

    let fullConfig = ConfigLoader.LoadedConfig(
        project: ProjectConfig(
            project: "MyApp.xcodeproj",
            destinations: [
                "sim": "platform:iOS Simulator,name:iPhone 16",
                "device": "platform:iOS,name:My iPhone",
                "mac": "platform:macOS"
            ],
            defaults: CommandConfig(
                scheme: "MyApp",
                configuration: "Debug",
                destination: "sim"
            ),
            commands: [
                "build": CommandConfig(
                    hooks: HookConfig(pre: "swiftlint lint", post: "echo done"),
                    variants: [
                        "release": CommandConfig(
                            configuration: "Release",
                            destination: "device"
                        )
                    ]
                ),
                "test": CommandConfig(
                    scheme: "MyAppTests",
                    destination: "sim",
                    extraArgs: ["-enableCodeCoverage", "YES"]
                ),
                "clean": CommandConfig(),
                "archive": CommandConfig(
                    configuration: "Release",
                    archivePath: "./build/MyApp.xcarchive",
                    variants: [
                        "staging": CommandConfig(
                            extraArgs: ["STAGING=1"]
                        )
                    ]
                )
            ]
        ),
        global: GlobalConfig(
            defaults: CommandConfig(scheme: "GlobalDefault"),
            settings: Settings(formatter: "xcbeautify")
        )
    )

    let minimalConfig = ConfigLoader.LoadedConfig(
        project: ProjectConfig(
            commands: [
                "build": CommandConfig(scheme: "Minimal")
            ]
        ),
        global: nil
    )

    // MARK: - Basic Resolution

    @Test("resolve build with defaults")
    func resolveBuildDefaults() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments == [
            "xcodebuild", "build",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyApp",
            "-configuration", "Debug",
            "-destination", "platform:iOS Simulator,name:iPhone 16"
        ])
    }

    @Test("resolve build:release variant overrides")
    func resolveBuildRelease() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: "release",
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments == [
            "xcodebuild", "build",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyApp",
            "-configuration", "Release",
            "-destination", "platform:iOS,name:My iPhone"
        ])
    }

    @Test("resolve test with command-level overrides and extra args")
    func resolveTest() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments == [
            "xcodebuild", "test",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyAppTests",
            "-configuration", "Debug",
            "-destination", "platform:iOS Simulator,name:iPhone 16",
            "-enableCodeCoverage", "YES"
        ])
    }

    @Test("resolve clean uses only defaults")
    func resolveClean() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "clean",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments == [
            "xcodebuild", "clean",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyApp",
            "-configuration", "Debug",
            "-destination", "platform:iOS Simulator,name:iPhone 16"
        ])
    }

    // MARK: - Archive

    @Test("resolve archive includes archivePath")
    func resolveArchive() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "archive",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-archivePath"))
        #expect(try resolved.xcodebuild().arguments.contains("./build/MyApp.xcarchive"))
    }

    // MARK: - xcconfig

    @Test("resolve build with xcconfig")
    func resolveXcconfig() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(xcconfig: "Config/Release.xcconfig")
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-xcconfig"))
        #expect(try resolved.xcodebuild().arguments.contains("Config/Release.xcconfig"))
    }

    @Test("xcconfig variant overrides command")
    func xcconfigVariantOverride() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        xcconfig: "Config/Debug.xcconfig",
                        variants: [
                            "release": CommandConfig(xcconfig: "Config/Release.xcconfig")
                        ]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: "release",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("Config/Release.xcconfig"))
        #expect(try !resolved.xcodebuild().arguments.contains("Config/Debug.xcconfig"))
    }

    @Test("xcconfig placed before scheme in invocation")
    func xcconfigBeforeScheme() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        scheme: "MyApp",
                        xcconfig: "Config/Debug.xcconfig"
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        let xcconfigIdx = try #require(try resolved.xcodebuild().arguments.firstIndex(of: "-xcconfig"))
        let schemeIdx = try #require(try resolved.xcodebuild().arguments.firstIndex(of: "-scheme"))
        #expect(xcconfigIdx < schemeIdx)
    }

    @Test("archivePath only added for archive action")
    func archivePathOnlyForArchive() throws {
        // build should not include archivePath even if configured
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(archivePath: "./should-not-appear")
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try !resolved.xcodebuild().arguments.contains("-archivePath"))
    }

    // MARK: - Test Plan

    @Test("resolve test with testPlan")
    func resolveTestPlan() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        scheme: "MyApp",
                        testPlan: "UnitTests"
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-testPlan"))
        #expect(try resolved.xcodebuild().arguments.contains("UnitTests"))
    }

    @Test("testPlan only added for test actions")
    func planOnlyForTest() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(testPlan: "should-not-appear")
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try !resolved.xcodebuild().arguments.contains("-testPlan"))
    }

    @Test("testPlan variant overrides command testPlan")
    func planVariantOverride() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        testPlan: "UnitTests",
                        variants: [
                            "integration": CommandConfig(testPlan: "IntegrationTests")
                        ]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: "integration",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("IntegrationTests"))
        #expect(try !resolved.xcodebuild().arguments.contains("UnitTests"))
    }

    @Test("testPlan works for test-without-building action")
    func planTestWithoutBuilding() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "test-without-building": CommandConfig(
                        scheme: "MyApp",
                        testPlan: "Smoke"
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test-without-building",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-testPlan"))
        #expect(try resolved.xcodebuild().arguments.contains("Smoke"))
    }

    // MARK: - Result Bundle Path

    @Test("resolve test with resultBundlePath")
    func resolveResultBundlePath() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        scheme: "MyApp",
                        resultBundlePath: "./results.xcresult"
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-resultBundlePath"))
        #expect(try resolved.xcodebuild().arguments.contains("./results.xcresult"))
    }

    @Test("resultBundlePath only added for test actions")
    func resultBundlePathOnlyForTest() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(resultBundlePath: "./should-not-appear")
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try !resolved.xcodebuild().arguments.contains("-resultBundlePath"))
    }

    @Test("resultBundlePath variant overrides command")
    func resultBundlePathVariantOverride() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        resultBundlePath: "./local.xcresult",
                        variants: [
                            "ci": CommandConfig(resultBundlePath: "/tmp/ci.xcresult")
                        ]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: "ci",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("/tmp/ci.xcresult"))
        #expect(try !resolved.xcodebuild().arguments.contains("./local.xcresult"))
    }

    // MARK: - Derived Data Path

    @Test("resolve build with derivedDataPath")
    func resolveDerivedDataPath() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(derivedDataPath: "./DerivedData")
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-derivedDataPath"))
        #expect(try resolved.xcodebuild().arguments.contains("./DerivedData"))
    }

    @Test("derivedDataPath from defaults applies to all actions")
    func derivedDataPathFromDefaults() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                defaults: CommandConfig(derivedDataPath: "./DD"),
                commands: [
                    "test": CommandConfig(scheme: "MyApp")
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-derivedDataPath"))
        #expect(try resolved.xcodebuild().arguments.contains("./DD"))
    }

    @Test("derivedDataPath variant overrides command")
    func derivedDataPathVariantOverride() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        derivedDataPath: "./DD",
                        variants: [
                            "ci": CommandConfig(derivedDataPath: "/tmp/ci-dd")
                        ]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: "ci",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("/tmp/ci-dd"))
        #expect(try !resolved.xcodebuild().arguments.contains("./DD"))
    }

    // MARK: - Destination Resolution

    @Test("named destination is expanded")
    func namedDestination() {
        let result = CommandResolver.resolveDestinations(OneOrMany("sim"), destinations: [
            "sim": "platform:iOS Simulator,name:iPhone 16"
        ])
        #expect(result == ["platform:iOS Simulator,name:iPhone 16"])
    }

    @Test("raw destination passes through")
    func rawDestination() {
        let result = CommandResolver.resolveDestinations(
            OneOrMany("platform:macOS"),
            destinations: ["sim": "platform:iOS Simulator,name:iPhone 16"]
        )
        #expect(result == ["platform:macOS"])
    }

    @Test("nil destination returns empty")
    func nilDestination() {
        let result = CommandResolver.resolveDestinations(nil, destinations: ["sim": "test"])
        #expect(result.isEmpty)
    }

    @Test("multiple destinations are all resolved")
    func multipleDestinations() {
        let result = CommandResolver.resolveDestinations(
            OneOrMany(["sim", "platform:macOS"]),
            destinations: ["sim": "platform:iOS Simulator,name:iPhone 16"]
        )
        #expect(result == [
            "platform:iOS Simulator,name:iPhone 16",
            "platform:macOS"
        ])
    }

    @Test("multiple destinations emit multiple flags in invocation")
    func multipleDestinationsInvocation() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                destinations: [
                    "sim": "platform:iOS Simulator,name:iPhone 16",
                    "sim-ipad": "platform:iOS Simulator,name:iPad Pro"
                ],
                commands: [
                    "test": CommandConfig(
                        scheme: "MyApp",
                        destination: ["sim", "sim-ipad"]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        let destFlags = try resolved.xcodebuild().arguments.enumerated().filter {
            $0.element == "-destination"
        }.map { try resolved.xcodebuild().arguments[$0.offset + 1] }

        #expect(destFlags == [
            "platform:iOS Simulator,name:iPhone 16",
            "platform:iOS Simulator,name:iPad Pro"
        ])
    }

    @Test("CLI dest override takes priority")
    func destOverridePriority() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: "mac",
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("platform:macOS"))
    }

    // MARK: - Extra Args

    @Test("passthrough extra args appended at end")
    func passthroughArgs() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: ["-enableAddressSanitizer", "YES"]
        )

        let last2 = try Array(resolved.xcodebuild().arguments.suffix(2))
        #expect(last2 == ["-enableAddressSanitizer", "YES"])
    }

    @Test("variant extra-args replace command extra-args")
    func variantExtraArgsReplace() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "archive",
            variant: "staging",
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("STAGING=1"))
        // Should NOT contain any other extra args from base (there are none in this case)
    }

    // MARK: - Hooks

    @Test("hooks resolved from command config")
    func hooksFromCommand() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.hooks?.pre == "swiftlint lint")
        #expect(resolved.hooks?.post == "echo done")
    }

    @Test("variant hooks override command hooks")
    func variantHooksOverride() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        hooks: HookConfig(pre: "base-hook"),
                        variants: [
                            "release": CommandConfig(
                                hooks: HookConfig(pre: "variant-hook")
                            )
                        ]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: "release",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.hooks?.pre == "variant-hook")
    }

    @Test("no hooks when none defined")
    func noHooks() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "clean",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.hooks == nil)
    }

    // MARK: - Error Cases

    @Test("unknown command throws")
    func unknownCommand() {
        #expect(throws: XCError.self) {
            try CommandResolver.resolve(
                commandName: "nonexistent",
                variant: nil,
                config: fullConfig,
                destOverride: nil,
                extraArgs: []
            )
        }
    }

    @Test("unknown variant throws")
    func unknownVariant() {
        #expect(throws: XCError.self) {
            try CommandResolver.resolve(
                commandName: "build",
                variant: "nonexistent",
                config: fullConfig,
                destOverride: nil,
                extraArgs: []
            )
        }
    }

    // MARK: - Workspace & SPM

    @Test("workspace used instead of project")
    func workspaceConfig() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                workspace: "MyApp.xcworkspace",
                commands: ["build": CommandConfig()]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("-workspace"))
        #expect(try resolved.xcodebuild().arguments.contains("MyApp.xcworkspace"))
        #expect(try !resolved.xcodebuild().arguments.contains("-project"))
    }

    @Test("SPM project has no project or workspace flags")
    func spmProject() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["build": CommandConfig(scheme: "MyPackage")]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try !resolved.xcodebuild().arguments.contains("-project"))
        #expect(try !resolved.xcodebuild().arguments.contains("-workspace"))
        #expect(try resolved.xcodebuild().arguments.contains("-scheme"))
    }

    // MARK: - Global Config Fallback

    @Test("global defaults used when project defaults missing")
    func globalFallback() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["build": CommandConfig()]
            ),
            global: GlobalConfig(
                defaults: CommandConfig(scheme: "GlobalScheme", configuration: "GlobalConfig")
            )
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments.contains("GlobalScheme"))
        #expect(try resolved.xcodebuild().arguments.contains("GlobalConfig"))
    }

    @Test("formatter resolved from global settings")
    func formatterFromGlobal() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().formatter == "xcbeautify")
    }

    @Test("project formatter overrides global formatter")
    func formatterProjectOverridesGlobal() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["build": CommandConfig()],
                settings: Settings(formatter: "xcbeautify --disable-logging")
            ),
            global: GlobalConfig(
                settings: Settings(formatter: "xcbeautify")
            )
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().formatter == "xcbeautify --disable-logging")
    }

    @Test("project formatter used when no global config")
    func formatterProjectOnly() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["build": CommandConfig()],
                settings: Settings(formatter: "xcpretty")
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().formatter == "xcpretty")
    }

    // MARK: - Minimal Config

    @Test("minimal config with only command scheme")
    func minimalConfigResolve() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: minimalConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try resolved.xcodebuild().arguments == [
            "xcodebuild", "build",
            "-scheme", "Minimal"
        ])
    }

    // MARK: - Script Commands

    @Test("script command returns script instead of invocation")
    func scriptCommand() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["lint": CommandConfig(run: "swiftlint lint --strict")]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "lint",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.action == .script("swiftlint lint --strict"))
    }

    @Test("script command with passthrough args")
    func scriptCommandPassthrough() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["lint": CommandConfig(run: "swiftlint lint")]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "lint",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: ["--fix"]
        )

        #expect(resolved.action == .script("swiftlint lint --fix"))
    }

    @Test("script passthrough args with shell metacharacters are quoted")
    func scriptCommandPassthroughQuoting() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["review": CommandConfig(run: "./codechat review reply")]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "review",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: ["--body", "Addressed - switched to makeThing()."]
        )

        // The metacharacter-laden arg must be single-quoted so `sh -c` treats it
        // as one literal token instead of parsing the "(".
        #expect(resolved.action == .script("./codechat review reply --body 'Addressed - switched to makeThing().'"))
    }

    @Test("script passthrough neutralizes injection and expansion")
    func scriptCommandPassthroughInjection() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["run": CommandConfig(run: "./tool")]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "run",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: ["$HOME", "a; touch b", "it's", "`whoami`"]
        )

        // No unquoted $, ;, backtick, or apostrophe escapes into the shell string.
        #expect(resolved.action == .script("./tool '$HOME' 'a; touch b' 'it'\\''s' '`whoami`'"))
    }

    @Test("script command variant overrides run")
    func scriptCommandVariant() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "lint": CommandConfig(
                        run: "swiftlint lint --strict",
                        variants: [
                            "fix": CommandConfig(run: "swiftlint lint --fix")
                        ]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "lint",
            variant: "fix",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.action == .script("swiftlint lint --fix"))
    }

    @Test("script command preserves hooks")
    func scriptCommandHooks() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "generate": CommandConfig(
                        run: "tuist generate",
                        hooks: HookConfig(pre: "echo pre", post: "echo post")
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "generate",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.action == .script("tuist generate"))
        #expect(resolved.hooks?.pre == "echo pre")
        #expect(resolved.hooks?.post == "echo post")
    }

    @Test("script command with extra-args in config")
    func scriptCommandExtraArgs() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "lint": CommandConfig(
                        run: "swiftlint lint",
                        extraArgs: ["--reporter", "json"]
                    )
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "lint",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.action == .script("swiftlint lint --reporter json"))
    }

    @Test("non-script command has nil script")
    func nonScriptCommand() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: minimalConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(try !resolved.xcodebuild().arguments.isEmpty)
    }
}

extension CommandResolver.ResolvedCommand {
    struct NotXcodebuild: Error {}

    /// The xcodebuild case's values; throws if this resolved to a script.
    func xcodebuild() throws -> (arguments: [String], formatter: String?) {
        guard case .xcodebuild(let arguments, let formatter) = action else { throw NotXcodebuild() }
        return (arguments, formatter)
    }
}
