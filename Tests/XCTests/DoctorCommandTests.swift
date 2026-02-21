@testable import xc
import Testing

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
        let result = DoctorCommand.extractSimulatorName(from: "platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2")
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
                "clean": CommandConfig(),
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
                "test": CommandConfig(scheme: "MyApp"),
            ]
        )
        let schemes = DoctorCommand.collectSchemes(from: config)
        #expect(schemes == ["MyApp"])
    }
}
