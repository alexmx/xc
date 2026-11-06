/// A command as typed on the command line: `[member/]name[:variant]`.
struct CommandRef: Equatable {
    let member: String?
    let name: String
    let variant: String?

    init(member: String?, name: String, variant: String?) {
        self.member = member
        self.name = name
        self.variant = variant
    }

    /// The reference as it would be typed: `core/build:release`.
    var text: String {
        (member.map { "\($0)/" } ?? "") + name + (variant.map { ":\($0)" } ?? "")
    }

    /// The first "/" ends the member and the first ":" starts the variant, so
    /// `build:a:b` is variant `a:b`. A leading "/" means no member.
    init(parsing input: String) throws {
        var rest = Substring(input)
        var member: String?
        if let slash = rest.firstIndex(of: "/") {
            member = rest[..<slash].isEmpty ? nil : String(rest[..<slash])
            rest = rest[rest.index(after: slash)...]
        }
        var variant: String?
        if let colon = rest.firstIndex(of: ":") {
            variant = String(rest[rest.index(after: colon)...])
            rest = rest[..<colon]
        }
        guard !rest.isEmpty else {
            throw XCError.invalidCommand(input, reason: "missing a command name")
        }
        if variant?.isEmpty == true {
            throw XCError.invalidCommand(input, reason: "missing a variant name after ':'")
        }
        self.init(member: member, name: String(rest), variant: variant)
    }
}
