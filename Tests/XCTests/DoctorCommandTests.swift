import Foundation
import Testing
@testable import xc

@Suite("DoctorCommand Tests")
struct DoctorCommandTests {
    // MARK: - extractSimulatorName

    @Test("extractSimulatorName from iOS Simulator destination")
    func extractiOSSimName() {
        let result = DoctorCommand.extractSimulatorName(from: "platform=iOS Simulator,name=iPhone 17 Pro")
        #expect(result == "iPhone 17 Pro")
    }

    @Test("extractSimulatorName from destination with extra fields")
    func extractWithExtraFields() {
        let result = DoctorCommand
            .extractSimulatorName(from: "platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2")
        #expect(result == "iPad Pro 13-inch (M5)")
    }

    @Test("extractSimulatorName returns nil for macOS destination")
    func extractMacOS() {
        let result = DoctorCommand.extractSimulatorName(from: "platform=macOS")
        #expect(result == nil)
    }

    @Test("extractSimulatorName returns nil for empty string")
    func extractEmpty() {
        let result = DoctorCommand.extractSimulatorName(from: "")
        #expect(result == nil)
    }

    // MARK: - collectSchemes

    @Test("collectSchemes gathers from defaults, commands, and variants")
    func collectAll() {
        let config = ProjectConfig(
            defaults: CommandConfig(scheme: "DefaultScheme"),
            commands: [
                "build": CommandConfig(
                    scheme: "BuildScheme",
                    variants: [
                        "core": CommandConfig(scheme: "CoreScheme")
                    ]
                ),
                "test": CommandConfig(scheme: "TestScheme"),
                "clean": CommandConfig()
            ]
        )

        let schemes = DoctorCommand.collectSchemes(from: config)
        #expect(schemes == ["DefaultScheme", "BuildScheme", "CoreScheme", "TestScheme"])
    }

    @Test("collectSchemes returns empty when no schemes referenced")
    func collectEmpty() {
        let config = ProjectConfig(
            commands: ["build": CommandConfig(), "clean": CommandConfig()]
        )
        let schemes = DoctorCommand.collectSchemes(from: config)
        #expect(schemes.isEmpty)
    }

    @Test("collectSchemes deduplicates same scheme used in multiple places")
    func collectDeduplicates() {
        let config = ProjectConfig(
            defaults: CommandConfig(scheme: "MyApp"),
            commands: [
                "build": CommandConfig(scheme: "MyApp"),
                "test": CommandConfig(scheme: "MyApp")
            ]
        )
        let schemes = DoctorCommand.collectSchemes(from: config)
        #expect(schemes == ["MyApp"])
    }

    // MARK: - Checks

    private typealias Check = DoctorCommand.Check

    @Test("destination checks: macOS and non-simulator values pass, missing simulators fail")
    func destinationChecks() {
        let checks = DoctorCommand.destinationChecks(
            [
                "mac": "platform=macOS",
                "sim": "platform=iOS Simulator,name=iPhone 17 Pro",
                "gone": "platform=iOS Simulator,name=iPhone 1",
                "id": "id=1234"
            ],
            installedSimulators: ["iPhone 17 Pro"]
        )
        #expect(checks == [
            Check("Dest: gone", .fail, "iPhone 1 not found. Run 'xc destinations' to see available simulators."),
            Check("Dest: id", .ok, "id=1234"),
            Check("Dest: mac", .ok, "macOS"),
            Check("Dest: sim", .ok, "iPhone 17 Pro")
        ])
    }

    @Test("scheme checks are skipped when schemes couldn't be listed")
    func schemeChecksSkipped() {
        let config = ProjectConfig(defaults: CommandConfig(scheme: "App"))
        #expect(DoctorCommand.schemeChecks(config, available: nil).isEmpty)
    }

    @Test("scheme checks flag unknown schemes and list the available ones")
    func schemeChecks() {
        let config = ProjectConfig(
            defaults: CommandConfig(scheme: "App"),
            commands: ["build": CommandConfig(scheme: "Nope")]
        )
        #expect(DoctorCommand.schemeChecks(config, available: ["Core", "App"]) == [
            Check("Scheme: App", .ok),
            Check("Scheme: Nope", .fail, "Not found. Available: App, Core")
        ])
    }

    @Test("container check reports a missing project and finds an existing workspace")
    func containerChecks() throws {
        let dir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/App.xcworkspace", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let missing = DoctorCommand.containerChecks(ProjectConfig(project: "App.xcodeproj"), projectRoot: dir)
        #expect(missing == [Check("Project", .fail, "App.xcodeproj not found")])
        let found = DoctorCommand.containerChecks(ProjectConfig(workspace: "App.xcworkspace"), projectRoot: dir)
        #expect(found == [Check("Workspace", .ok, "App.xcworkspace")])
        #expect(DoctorCommand.containerChecks(ProjectConfig(), projectRoot: dir).isEmpty)
    }

    @Test("member checks pass loadable members and explain the rest")
    func memberChecks() throws {
        let dir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/ok", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "commands:\n  build: {}\n".write(toFile: dir + "/ok/xc.yaml", atomically: true, encoding: .utf8)

        let config = ProjectConfig(members: ["ok": "ok", "gone": "gone"])
        let checks = DoctorCommand.memberChecks(config, projectRoot: dir)
        #expect(checks.map(\.name) == ["Member: gone", "Member: ok"])
        #expect(checks.map(\.status) == [.fail, .ok])
        #expect(checks[0].detail?.hasPrefix("gone — No xc.yaml") == true)
    }

    @Test("a missing xc.yaml points at xc init")
    func configFileCheck() {
        #expect(DoctorCommand.configFileCheck(XCError.configNotFound(directory: "/a", searchedParents: true))
            == Check("xc.yaml", .fail, "Not found. Run 'xc init' to generate one."))
        #expect(DoctorCommand.configFileCheck(XCError.invalidConfig("bad"))
            == Check("xc.yaml", .fail, "bad"))
    }
}
