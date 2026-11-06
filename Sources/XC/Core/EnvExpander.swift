import Foundation
import Yams

enum EnvExpander {
    /// Expand `${VAR}` and `${VAR:-default}` patterns in a string.
    /// Only the `${}` syntax is supported — bare `$VAR` is not expanded.
    static func expand(
        _ string: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        var result = ""
        var remaining = string[...]

        while let dollarIndex = remaining.firstIndex(of: "$") {
            // Append everything before the $
            result += remaining[remaining.startIndex..<dollarIndex]

            let afterDollar = remaining.index(after: dollarIndex)
            guard afterDollar < remaining.endIndex, remaining[afterDollar] == "{" else {
                // Not ${...}, just a literal $
                result += "$"
                remaining = remaining[afterDollar...]
                continue
            }

            let afterBrace = remaining.index(after: afterDollar)
            guard let closingBrace = remaining[afterBrace...].firstIndex(of: "}") else {
                // No closing brace — treat as literal
                result += "${"
                remaining = remaining[afterBrace...]
                continue
            }

            let content = String(remaining[afterBrace..<closingBrace])
            let (varName, defaultValue) = parseVarExpression(content)

            if let envValue = environment[varName], !envValue.isEmpty {
                result += envValue
            } else if let defaultValue {
                result += defaultValue
            }
            // If no env value and no default, expand to empty string

            remaining = remaining[remaining.index(after: closingBrace)...]
        }

        result += remaining
        return result
    }

    /// Parse "VAR" or "VAR:-default" into (name, default).
    static func parseVarExpression(_ expr: String) -> (name: String, defaultValue: String?) {
        guard let range = expr.range(of: ":-") else {
            return (expr, nil)
        }
        let name = String(expr[expr.startIndex..<range.lowerBound])
        let defaultValue = String(expr[range.upperBound...])
        return (name, defaultValue)
    }
}

// MARK: - Config expansion

extension Node {
    /// What Yams' `NSNull.construct(from:)` reads as null in an unquoted scalar.
    private static let nullSpellings: Set<String> = ["", "~", "null", "Null", "NULL"]

    /// Expand `${VAR}` in every scalar value; mapping keys (command, destination and
    /// member names) stay literal.
    func expandingEnvVars(_ environment: [String: String]) -> Node {
        switch self {
        case .scalar(var scalar):
            let expanded = EnvExpander.expand(scalar.string, environment: environment)
            guard expanded != scalar.string else { return self }
            scalar.string = expanded
            // Yams reads an unquoted "", "~" or "null" as nil; an expanded value must stay
            // that string, so treat it as quoted. Other values keep their style, so
            // `verbose: ${FLAG}` still decodes as a Bool.
            if Self.nullSpellings.contains(expanded) {
                scalar.style = .doubleQuoted
            }
            return .scalar(scalar)
        case .mapping(var mapping):
            for index in mapping.indices {
                mapping[index].value = mapping[index].value.expandingEnvVars(environment)
            }
            return .mapping(mapping)
        case .sequence(var sequence):
            for index in sequence.indices {
                sequence[index] = sequence[index].expandingEnvVars(environment)
            }
            return .sequence(sequence)
        case .alias:
            return self
        }
    }
}
