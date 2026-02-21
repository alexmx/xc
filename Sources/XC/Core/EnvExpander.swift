import Foundation

enum EnvExpander {
    /// Expand `${VAR}` and `${VAR:-default}` patterns in a string.
    /// Only the `${}` syntax is supported — bare `$VAR` is not expanded.
    static func expand(_ string: String) -> String {
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

            if let envValue = ProcessInfo.processInfo.environment[varName], !envValue.isEmpty {
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

extension String {
    var envExpanded: String { EnvExpander.expand(self) }
}

extension ProjectConfig {
    func expandingEnvVars() -> ProjectConfig {
        ProjectConfig(
            project: project?.envExpanded,
            workspace: workspace?.envExpanded,
            destinations: destinations?.mapValues { $0.envExpanded },
            defaults: defaults?.expandingEnvVars(),
            commands: commands?.mapValues { $0.expandingEnvVars() }
        )
    }
}

extension CommandConfig {
    func expandingEnvVars() -> CommandConfig {
        CommandConfig(
            scheme: scheme?.envExpanded,
            configuration: configuration?.envExpanded,
            destination: destination?.envExpanded,
            archivePath: archivePath?.envExpanded,
            extraArgs: extraArgs?.map { $0.envExpanded },
            hooks: hooks?.expandingEnvVars(),
            variants: variants?.mapValues { $0.expandingEnvVars() }
        )
    }
}

extension HookConfig {
    func expandingEnvVars() -> HookConfig {
        HookConfig(
            pre: pre?.envExpanded,
            post: post?.envExpanded
        )
    }
}
