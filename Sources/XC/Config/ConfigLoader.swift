import Foundation
import Yams

enum ConfigLoader {
    struct LoadedConfig: Sendable {
        let project: ProjectConfig
        let global: GlobalConfig?
    }

    static func load() throws -> LoadedConfig {
        let projectConfig = try loadProjectConfig()
        let globalConfig = loadGlobalConfig()
        return LoadedConfig(project: projectConfig, global: globalConfig)
    }

    static func loadProjectConfig() throws -> ProjectConfig {
        let path = FileManager.default.currentDirectoryPath + "/xc.yaml"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCError.configNotFound
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        return try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
    }

    static func loadGlobalConfig() -> GlobalConfig? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".config/xc/config.yaml").path
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let yaml = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return try? YAMLDecoder().decode(GlobalConfig.self, from: yaml)
    }
}
