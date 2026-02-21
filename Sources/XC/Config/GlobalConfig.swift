struct GlobalConfig: Codable, Sendable {
    var defaults: CommandConfig?
    var settings: GlobalSettings?
}

struct GlobalSettings: Codable, Sendable {
    var formatter: String?
    var verbose: Bool?
}
