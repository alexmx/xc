import Testing
@testable import xc

/// The exact xc.yaml `xc init` writes, pinned before the template was rewritten.
@Suite("Init template golden Tests")
struct InitTemplateGoldenTests {
    @Test("init template: workspaceIOS")
    func workspaceIOS() {
        let yaml = InitCommand.generateConfig(
            detection: .workspace(name: "App", path: "App.xcworkspace"),
            primaryScheme: "App",
            platform: .iOS,
            defaultSimulator: "iPhone 16 Pro"
        )
        #expect(yaml == """
        # xc configuration for App
        # Run 'xc destinations' to see all available destinations
        
        workspace: App.xcworkspace
        
        destinations:
          sim: "platform=iOS Simulator,name=iPhone 16 Pro"
          mac: "platform=macOS"
        
        defaults:
          scheme: App
          configuration: Debug
          destination: sim
        
        commands:
          build:
            variants:
              release:
                configuration: Release
        
          test: {}
        
          clean: {}
        
          archive:
            configuration: Release
            archive-path: "./build/App.xcarchive"
        """ + "\n")
    }

    @Test("init template: projectMacOS")
    func projectMacOS() {
        let yaml = InitCommand.generateConfig(
            detection: .project(name: "Mac", path: "Mac.xcodeproj"),
            primaryScheme: "Mac",
            platform: .macOS,
            defaultSimulator: nil
        )
        #expect(yaml == """
        # xc configuration for Mac
        # Run 'xc destinations' to see all available destinations
        
        project: Mac.xcodeproj
        
        destinations:
          mac: "platform=macOS"
        
        defaults:
          scheme: Mac
          configuration: Debug
          destination: mac
        
        commands:
          build:
            variants:
              release:
                configuration: Release
        
          test: {}
        
          clean: {}
        
          archive:
            configuration: Release
            archive-path: "./build/Mac.xcarchive"
        """ + "\n")
    }

    @Test("init template: packageUnknown")
    func packageUnknown() {
        let yaml = InitCommand.generateConfig(
            detection: .spm,
            primaryScheme: "Pkg",
            platform: .unknown,
            defaultSimulator: nil
        )
        #expect(yaml == """
        # xc configuration for Package
        # Run 'xc destinations' to see all available destinations
        
        
        destinations:
          sim: "platform=iOS Simulator,name=iPhone 17 Pro"
          mac: "platform=macOS"
        
        defaults:
          scheme: Pkg
          configuration: Debug
          destination: sim
        
        commands:
          build:
            variants:
              release:
                configuration: Release
        
          test: {}
        
          clean: {}
        
          archive:
            configuration: Release
            archive-path: "./build/Package.xcarchive"
        """ + "\n")
    }

    @Test("init template: noneUnknown")
    func noneUnknown() {
        let yaml = InitCommand.generateConfig(
            detection: .none,
            primaryScheme: nil,
            platform: .unknown,
            defaultSimulator: nil
        )
        #expect(yaml == """
        # xc configuration for Project
        # Run 'xc destinations' to see all available destinations
        
        
        destinations:
          sim: "platform=iOS Simulator,name=iPhone 17 Pro"
          mac: "platform=macOS"
        
        defaults:
          configuration: Debug
          destination: sim
        
        commands:
          build:
            variants:
              release:
                configuration: Release
        
          test: {}
        
          clean: {}
        
          archive:
            configuration: Release
            archive-path: "./build/Project.xcarchive"
        """ + "\n")
    }
}
