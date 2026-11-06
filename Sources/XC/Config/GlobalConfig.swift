struct GlobalConfig: Codable, Sendable {
    var defaults: CommandConfig?
    var settings: Settings?
}

/// `settings` in a project or global config.
struct Settings: Codable, Sendable {
    var formatter: String?
    var verbose: Bool?
}
