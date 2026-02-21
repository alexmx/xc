import Testing
@testable import xc

@Suite("InitCommand Tests")
struct InitCommandTests {
    // MARK: - pickPrimaryScheme

    @Test("pickPrimaryScheme matches project name")
    func pickPrimarySchemeMatchesName() {
        let schemes = ["Core", "MyApp", "MyAppTests"]
        let detection = InitCommand.ProjectType.workspace(name: "MyApp", path: "MyApp.xcworkspace")
        let result = InitCommand.pickPrimaryScheme(schemes: schemes, detection: detection)
        #expect(result == "MyApp")
    }

    @Test("pickPrimaryScheme falls back to first when no match")
    func pickPrimarySchemeFirstFallback() {
        let schemes = ["Core", "HelperKit"]
        let detection = InitCommand.ProjectType.project(name: "MyApp", path: "MyApp.xcodeproj")
        let result = InitCommand.pickPrimaryScheme(schemes: schemes, detection: detection)
        #expect(result == "Core")
    }

    @Test("pickPrimaryScheme returns nil for empty schemes")
    func pickPrimarySchemeEmpty() {
        let result = InitCommand.pickPrimaryScheme(
            schemes: [],
            detection: .spm
        )
        #expect(result == nil)
    }

    @Test("pickPrimaryScheme with SPM detection uses first scheme")
    func pickPrimarySchemeSPM() {
        let schemes = ["MyPackage", "MyPackageTests"]
        let result = InitCommand.pickPrimaryScheme(schemes: schemes, detection: .spm)
        #expect(result == "MyPackage")
    }

    // MARK: - generateConfig

    @Test("generateConfig for iOS workspace")
    func generateConfigiOS() {
        let yaml = InitCommand.generateConfig(
            detection: .workspace(name: "MyApp", path: "MyApp.xcworkspace"),
            primaryScheme: "MyApp",
            platform: .iOS,
            defaultSimulator: "iPhone 17 Pro"
        )

        #expect(yaml.contains("workspace: MyApp.xcworkspace"))
        #expect(yaml.contains("sim: \"platform=iOS Simulator,name=iPhone 17 Pro\""))
        #expect(yaml.contains("mac: \"platform=macOS\""))
        #expect(yaml.contains("scheme: MyApp"))
        #expect(yaml.contains("destination: sim"))
        #expect(yaml.contains("configuration: Debug"))
        #expect(yaml.contains("archive-path: \"./build/MyApp.xcarchive\""))
        #expect(yaml.contains("build:"))
        #expect(yaml.contains("test: {}"))
        #expect(yaml.contains("clean: {}"))
    }

    @Test("generateConfig for macOS project")
    func generateConfigMacOS() {
        let yaml = InitCommand.generateConfig(
            detection: .project(name: "MyMacApp", path: "MyMacApp.xcodeproj"),
            primaryScheme: "MyMacApp",
            platform: .macOS,
            defaultSimulator: nil
        )

        #expect(yaml.contains("project: MyMacApp.xcodeproj"))
        #expect(!yaml.contains("workspace:"))
        #expect(yaml.contains("mac: \"platform=macOS\""))
        #expect(!yaml.contains("sim:"))
        #expect(yaml.contains("destination: mac"))
        #expect(yaml.contains("archive-path: \"./build/MyMacApp.xcarchive\""))
    }

    @Test("generateConfig for SPM omits project/workspace")
    func generateConfigSPM() {
        let yaml = InitCommand.generateConfig(
            detection: .spm,
            primaryScheme: "MyPackage",
            platform: .unknown,
            defaultSimulator: nil
        )

        #expect(!yaml.contains("project:"))
        #expect(!yaml.contains("workspace:"))
        #expect(yaml.contains("scheme: MyPackage"))
        #expect(yaml.contains("sim: \"platform=iOS Simulator,name=iPhone 17 Pro\""))
        #expect(yaml.contains("mac: \"platform=macOS\""))
    }

    @Test("generateConfig without scheme")
    func generateConfigNoScheme() {
        let yaml = InitCommand.generateConfig(
            detection: .none,
            primaryScheme: nil,
            platform: .iOS,
            defaultSimulator: "iPhone 17"
        )

        #expect(!yaml.contains("scheme:"))
        #expect(yaml.contains("sim: \"platform=iOS Simulator,name=iPhone 17\""))
        #expect(yaml.contains("configuration: Debug"))
    }

    @Test("generateConfig uses custom simulator name")
    func generateConfigCustomSimulator() {
        let yaml = InitCommand.generateConfig(
            detection: .workspace(name: "App", path: "App.xcworkspace"),
            primaryScheme: "App",
            platform: .iOS,
            defaultSimulator: "iPhone Air"
        )

        #expect(yaml.contains("sim: \"platform=iOS Simulator,name=iPhone Air\""))
    }

    @Test("generateConfig falls back to iPhone 17 Pro when no simulator")
    func generateConfigFallbackSimulator() {
        let yaml = InitCommand.generateConfig(
            detection: .workspace(name: "App", path: "App.xcworkspace"),
            primaryScheme: "App",
            platform: .iOS,
            defaultSimulator: nil
        )

        #expect(yaml.contains("sim: \"platform=iOS Simulator,name=iPhone 17 Pro\""))
    }

    // MARK: - ProjectType.name

    @Test("ProjectType.name returns correct values")
    func projectTypeName() {
        #expect(InitCommand.ProjectType.workspace(name: "Foo", path: "Foo.xcworkspace").name == "Foo")
        #expect(InitCommand.ProjectType.project(name: "Bar", path: "Bar.xcodeproj").name == "Bar")
        #expect(InitCommand.ProjectType.spm.name == "Package")
        #expect(InitCommand.ProjectType.none.name == "Project")
    }
}
