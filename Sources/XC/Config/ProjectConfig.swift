struct ProjectConfig: Codable, Sendable {
    var project: String?
    var workspace: String?
    var destinations: [String: String]?
    var defaults: CommandConfig?
    var commands: [String: CommandConfig]?
}

struct CommandConfig: Codable, Sendable {
    var run: String?
    var scheme: String?
    var configuration: String?
    var destination: String?
    var archivePath: String?
    var extraArgs: [String]?
    var hooks: HookConfig?
    var variants: [String: CommandConfig]?

    enum CodingKeys: String, CodingKey {
        case run, scheme, configuration, destination
        case archivePath = "archive-path"
        case extraArgs = "extra-args"
        case hooks, variants
    }
}

struct HookConfig: Codable, Sendable {
    var pre: String?
    var post: String?
}
