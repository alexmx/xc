import Foundation
import Testing
@testable import xc

@Suite("CommandResolver Tests")
struct CommandResolverTests {
    // MARK: - Test Data

    let fullConfig = loaded(
        ProjectConfig(
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

    let minimalConfig = loaded(
        ProjectConfig(
            commands: [
                "build": CommandConfig(scheme: "Minimal")
            ]
        )
    )

    // MARK: - Basic Resolution

    @Test("resolve build with defaults")
    func resolveBuildDefaults() throws {
        let resolved = try resolve("build", in: fullConfig)

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
        let resolved = try resolve("build", variant: "release", in: fullConfig)

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
        let resolved = try resolve("test", in: fullConfig)

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
        let resolved = try resolve("clean", in: fullConfig)

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
        let resolved = try resolve("archive", in: fullConfig)

        #expect(try resolved.xcodebuild().arguments.contains("-archivePath"))
        #expect(try resolved.xcodebuild().arguments.contains("./build/MyApp.xcarchive"))
    }

    // MARK: - xcconfig

    @Test("resolve build with xcconfig")
    func resolveXcconfig() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(xcconfig: "Config/Release.xcconfig")
                ]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-xcconfig"))
        #expect(try resolved.xcodebuild().arguments.contains("Config/Release.xcconfig"))
    }

    @Test("xcconfig variant overrides command")
    func xcconfigVariantOverride() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        xcconfig: "Config/Debug.xcconfig",
                        variants: [
                            "release": CommandConfig(xcconfig: "Config/Release.xcconfig")
                        ]
                    )
                ]
            )
        )

        let resolved = try resolve("build", variant: "release", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("Config/Release.xcconfig"))
        #expect(try !resolved.xcodebuild().arguments.contains("Config/Debug.xcconfig"))
    }

    @Test("xcconfig placed before scheme in invocation")
    func xcconfigBeforeScheme() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        scheme: "MyApp",
                        xcconfig: "Config/Debug.xcconfig"
                    )
                ]
            )
        )

        let resolved = try resolve("build", in: config)

        let xcconfigIdx = try #require(try resolved.xcodebuild().arguments.firstIndex(of: "-xcconfig"))
        let schemeIdx = try #require(try resolved.xcodebuild().arguments.firstIndex(of: "-scheme"))
        #expect(xcconfigIdx < schemeIdx)
    }

    @Test("archivePath only added for archive action")
    func archivePathOnlyForArchive() throws {
        // build should not include archivePath even if configured
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(archivePath: "./should-not-appear")
                ]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try !resolved.xcodebuild().arguments.contains("-archivePath"))
    }

    // MARK: - Test Plan

    @Test("resolve test with testPlan")
    func resolveTestPlan() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        scheme: "MyApp",
                        testPlan: "UnitTests"
                    )
                ]
            )
        )

        let resolved = try resolve("test", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-testPlan"))
        #expect(try resolved.xcodebuild().arguments.contains("UnitTests"))
    }

    @Test("testPlan only added for test actions")
    func planOnlyForTest() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(testPlan: "should-not-appear")
                ]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try !resolved.xcodebuild().arguments.contains("-testPlan"))
    }

    @Test("testPlan variant overrides command testPlan")
    func planVariantOverride() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        testPlan: "UnitTests",
                        variants: [
                            "integration": CommandConfig(testPlan: "IntegrationTests")
                        ]
                    )
                ]
            )
        )

        let resolved = try resolve("test", variant: "integration", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("IntegrationTests"))
        #expect(try !resolved.xcodebuild().arguments.contains("UnitTests"))
    }

    @Test("testPlan works for test-without-building action")
    func planTestWithoutBuilding() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "test-without-building": CommandConfig(
                        scheme: "MyApp",
                        testPlan: "Smoke"
                    )
                ]
            )
        )

        let resolved = try resolve("test-without-building", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-testPlan"))
        #expect(try resolved.xcodebuild().arguments.contains("Smoke"))
    }

    // MARK: - Result Bundle Path

    @Test("resolve test with resultBundlePath")
    func resolveResultBundlePath() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        scheme: "MyApp",
                        resultBundlePath: "./results.xcresult"
                    )
                ]
            )
        )

        let resolved = try resolve("test", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-resultBundlePath"))
        #expect(try resolved.xcodebuild().arguments.contains("./results.xcresult"))
    }

    @Test("resultBundlePath only added for test actions")
    func resultBundlePathOnlyForTest() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(resultBundlePath: "./should-not-appear")
                ]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try !resolved.xcodebuild().arguments.contains("-resultBundlePath"))
    }

    @Test("resultBundlePath variant overrides command")
    func resultBundlePathVariantOverride() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "test": CommandConfig(
                        resultBundlePath: "./local.xcresult",
                        variants: [
                            "ci": CommandConfig(resultBundlePath: "/tmp/ci.xcresult")
                        ]
                    )
                ]
            )
        )

        let resolved = try resolve("test", variant: "ci", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("/tmp/ci.xcresult"))
        #expect(try !resolved.xcodebuild().arguments.contains("./local.xcresult"))
    }

    // MARK: - Derived Data Path

    @Test("resolve build with derivedDataPath")
    func resolveDerivedDataPath() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(derivedDataPath: "./DerivedData")
                ]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-derivedDataPath"))
        #expect(try resolved.xcodebuild().arguments.contains("./DerivedData"))
    }

    @Test("derivedDataPath from defaults applies to all actions")
    func derivedDataPathFromDefaults() throws {
        let config = loaded(
            ProjectConfig(
                defaults: CommandConfig(derivedDataPath: "./DD"),
                commands: [
                    "test": CommandConfig(scheme: "MyApp")
                ]
            )
        )

        let resolved = try resolve("test", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-derivedDataPath"))
        #expect(try resolved.xcodebuild().arguments.contains("./DD"))
    }

    @Test("derivedDataPath variant overrides command")
    func derivedDataPathVariantOverride() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        derivedDataPath: "./DD",
                        variants: [
                            "ci": CommandConfig(derivedDataPath: "/tmp/ci-dd")
                        ]
                    )
                ]
            )
        )

        let resolved = try resolve("build", variant: "ci", in: config)

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
        let config = loaded(
            ProjectConfig(
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
            )
        )

        let resolved = try resolve("test", in: config)

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
        let resolved = try resolve("build", in: fullConfig, dest: "mac")

        #expect(try resolved.xcodebuild().arguments.contains("platform:macOS"))
    }

    // MARK: - Extra Args

    @Test("passthrough extra args appended at end")
    func passthroughArgs() throws {
        let resolved = try resolve("build", in: fullConfig, extraArgs: ["-enableAddressSanitizer", "YES"])

        let last2 = try Array(resolved.xcodebuild().arguments.suffix(2))
        #expect(last2 == ["-enableAddressSanitizer", "YES"])
    }

    @Test("variant extra-args replace command extra-args")
    func variantExtraArgsReplace() throws {
        let resolved = try resolve("archive", variant: "staging", in: fullConfig)

        #expect(try resolved.xcodebuild().arguments.contains("STAGING=1"))
        // Should NOT contain any other extra args from base (there are none in this case)
    }

    // MARK: - Hooks

    @Test("hooks resolved from command config")
    func hooksFromCommand() throws {
        let resolved = try resolve("build", in: fullConfig)

        #expect(resolved.hooks?.pre == "swiftlint lint")
        #expect(resolved.hooks?.post == "echo done")
    }

    @Test("variant hooks override command hooks")
    func variantHooksOverride() throws {
        let config = loaded(
            ProjectConfig(
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
            )
        )

        let resolved = try resolve("build", variant: "release", in: config)

        #expect(resolved.hooks?.pre == "variant-hook")
    }

    @Test("no hooks when none defined")
    func noHooks() throws {
        let resolved = try resolve("clean", in: fullConfig)

        #expect(resolved.hooks == nil)
    }

    // MARK: - Error Cases

    @Test("unknown command throws")
    func unknownCommand() {
        #expect(throws: XCError.self) {
            try resolve("nonexistent", in: fullConfig)
        }
    }

    @Test("unknown variant throws")
    func unknownVariant() {
        #expect(throws: XCError.self) {
            try resolve("build", variant: "nonexistent", in: fullConfig)
        }
    }

    // MARK: - Workspace & SPM

    @Test("workspace used instead of project")
    func workspaceConfig() throws {
        let config = loaded(
            ProjectConfig(
                workspace: "MyApp.xcworkspace",
                commands: ["build": CommandConfig()]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("-workspace"))
        #expect(try resolved.xcodebuild().arguments.contains("MyApp.xcworkspace"))
        #expect(try !resolved.xcodebuild().arguments.contains("-project"))
    }

    @Test("SPM project has no project or workspace flags")
    func spmProject() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["build": CommandConfig(scheme: "MyPackage")]
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try !resolved.xcodebuild().arguments.contains("-project"))
        #expect(try !resolved.xcodebuild().arguments.contains("-workspace"))
        #expect(try resolved.xcodebuild().arguments.contains("-scheme"))
    }

    // MARK: - Global Config Fallback

    @Test("global defaults used when project defaults missing")
    func globalFallback() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["build": CommandConfig()]
            ),
            global: GlobalConfig(
                defaults: CommandConfig(scheme: "GlobalScheme", configuration: "GlobalConfig")
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try resolved.xcodebuild().arguments.contains("GlobalScheme"))
        #expect(try resolved.xcodebuild().arguments.contains("GlobalConfig"))
    }

    @Test("formatter resolved from global settings")
    func formatterFromGlobal() throws {
        let resolved = try resolve("build", in: fullConfig)

        #expect(try resolved.xcodebuild().formatter == "xcbeautify")
    }

    @Test("project formatter overrides global formatter")
    func formatterProjectOverridesGlobal() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["build": CommandConfig()],
                settings: Settings(formatter: "xcbeautify --disable-logging")
            ),
            global: GlobalConfig(
                settings: Settings(formatter: "xcbeautify")
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try resolved.xcodebuild().formatter == "xcbeautify --disable-logging")
    }

    @Test("project formatter used when no global config")
    func formatterProjectOnly() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["build": CommandConfig()],
                settings: Settings(formatter: "xcpretty")
            )
        )

        let resolved = try resolve("build", in: config)

        #expect(try resolved.xcodebuild().formatter == "xcpretty")
    }

    // MARK: - Minimal Config

    @Test("minimal config with only command scheme")
    func minimalConfigResolve() throws {
        let resolved = try resolve("build", in: minimalConfig)

        #expect(try resolved.xcodebuild().arguments == [
            "xcodebuild", "build",
            "-scheme", "Minimal"
        ])
    }

    // MARK: - Script Commands

    @Test("script command returns script instead of invocation")
    func scriptCommand() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["lint": CommandConfig(run: "swiftlint lint --strict")]
            )
        )

        let resolved = try resolve("lint", in: config)

        #expect(resolved.action == .script("swiftlint lint --strict"))
    }

    @Test("script command with passthrough args")
    func scriptCommandPassthrough() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["lint": CommandConfig(run: "swiftlint lint")]
            )
        )

        let resolved = try resolve("lint", in: config, extraArgs: ["--fix"])

        #expect(resolved.action == .script("swiftlint lint --fix"))
    }

    @Test("script passthrough args with shell metacharacters are quoted")
    func scriptCommandPassthroughQuoting() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["review": CommandConfig(run: "./codechat review reply")]
            )
        )

        let resolved = try resolve(
            "review",
            in: config,
            extraArgs: ["--body", "Addressed - switched to makeThing()."]
        )

        // The metacharacter-laden arg must be single-quoted so `sh -c` treats it
        // as one literal token instead of parsing the "(".
        #expect(resolved.action == .script("./codechat review reply --body 'Addressed - switched to makeThing().'"))
    }

    @Test("script passthrough neutralizes injection and expansion")
    func scriptCommandPassthroughInjection() throws {
        let config = loaded(
            ProjectConfig(
                commands: ["run": CommandConfig(run: "./tool")]
            )
        )

        let resolved = try resolve("run", in: config, extraArgs: ["$HOME", "a; touch b", "it's", "`whoami`"])

        // No unquoted $, ;, backtick, or apostrophe escapes into the shell string.
        #expect(resolved.action == .script("./tool '$HOME' 'a; touch b' 'it'\\''s' '`whoami`'"))
    }

    @Test("script command variant overrides run")
    func scriptCommandVariant() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "lint": CommandConfig(
                        run: "swiftlint lint --strict",
                        variants: [
                            "fix": CommandConfig(run: "swiftlint lint --fix")
                        ]
                    )
                ]
            )
        )

        let resolved = try resolve("lint", variant: "fix", in: config)

        #expect(resolved.action == .script("swiftlint lint --fix"))
    }

    @Test("script command preserves hooks")
    func scriptCommandHooks() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "generate": CommandConfig(
                        run: "tuist generate",
                        hooks: HookConfig(pre: "echo pre", post: "echo post")
                    )
                ]
            )
        )

        let resolved = try resolve("generate", in: config)

        #expect(resolved.action == .script("tuist generate"))
        #expect(resolved.hooks?.pre == "echo pre")
        #expect(resolved.hooks?.post == "echo post")
    }

    @Test("script command with extra-args in config")
    func scriptCommandExtraArgs() throws {
        let config = loaded(
            ProjectConfig(
                commands: [
                    "lint": CommandConfig(
                        run: "swiftlint lint",
                        extraArgs: ["--reporter", "json"]
                    )
                ]
            )
        )

        let resolved = try resolve("lint", in: config)

        #expect(resolved.action == .script("swiftlint lint --reporter json"))
    }

    @Test("non-script command has nil script")
    func nonScriptCommand() throws {
        let resolved = try resolve("build", in: minimalConfig)

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

/// `CommandResolver.resolve` with the arguments most tests leave at their defaults.
private func resolve(
    _ command: String,
    variant: String? = nil,
    in config: ConfigLoader.LoadedConfig,
    dest: String? = nil,
    extraArgs: [String] = []
) throws -> CommandResolver.ResolvedCommand {
    try CommandResolver.resolve(
        commandName: command,
        variant: variant,
        config: config,
        destOverride: dest,
        extraArgs: extraArgs
    )
}

private func loaded(_ project: ProjectConfig, global: GlobalConfig? = nil) -> ConfigLoader.LoadedConfig {
    ConfigLoader.LoadedConfig(project: project, global: global, projectRoot: "/repo")
}
