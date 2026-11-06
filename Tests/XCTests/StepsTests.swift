import Testing
@testable import xc

@Suite("Steps Tests")
struct StepsTests {
    private func config(_ commands: [String: CommandConfig]) -> ConfigLoader.LoadedConfig {
        ConfigLoader.LoadedConfig(project: ProjectConfig(commands: commands), global: nil, projectRoot: "/repo")
    }

    private func validationError(_ commands: [String: CommandConfig]) -> String? {
        do {
            try ConfigLoader.validate(ProjectConfig(commands: commands))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test("a steps command can't also run a script or set xcodebuild settings")
    func stepsExcludeOtherSettings() {
        #expect(validationError(["gate": CommandConfig(run: "make", steps: ["lint"])])
            == "Invalid xc.yaml: Command 'gate' combines 'steps' with run. A steps command only lists other commands.")
        #expect(validationError(["gate": CommandConfig(scheme: "App", extraArgs: ["-quiet"], steps: ["lint"])])
            ==
            "Invalid xc.yaml: Command 'gate' combines 'steps' with scheme, extra-args. A steps command only lists other commands.")
    }

    @Test("a variant is checked too")
    func variantChecked() {
        let gate = CommandConfig(
            variants: ["quick": CommandConfig(configuration: "Debug", steps: ["lint"])],
            steps: ["lint"]
        )
        #expect(validationError(["gate": gate])
            ==
            "Invalid xc.yaml: Command 'gate:quick' combines 'steps' with configuration. A steps command only lists other commands.")
    }

    @Test("an empty steps list is rejected")
    func emptySteps() {
        #expect(validationError(["gate": CommandConfig(steps: [])])
            == "Invalid xc.yaml: Command 'gate' has an empty 'steps' list.")
    }

    @Test("a steps command resolves to its steps, parsed like the command line")
    func resolvesSteps() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "gate",
            variant: nil,
            config: config(["gate": CommandConfig(steps: ["lint", "build:release", "core/test"])]),
            destOverride: nil,
            extraArgs: []
        )
        #expect(resolved.action == .steps([
            CommandRef(member: nil, name: "lint", variant: nil),
            CommandRef(member: nil, name: "build", variant: "release"),
            CommandRef(member: "core", name: "test", variant: nil)
        ]))
    }

    @Test("a variant can replace the steps")
    func variantSteps() throws {
        let gate = CommandConfig(variants: ["quick": CommandConfig(steps: ["lint"])], steps: ["lint", "test"])
        let resolved = try CommandResolver.resolve(
            commandName: "gate",
            variant: "quick",
            config: config(["gate": gate]),
            destOverride: nil,
            extraArgs: []
        )
        #expect(resolved.action == .steps([CommandRef(member: nil, name: "lint", variant: nil)]))
    }

    @Test("an invalid step is reported with its command")
    func invalidStep() {
        do {
            _ = try CommandResolver.resolve(
                commandName: "gate",
                variant: nil,
                config: config(["gate": CommandConfig(steps: ["build:"])]),
                destOverride: nil,
                extraArgs: []
            )
            Issue.record("resolved an invalid step")
        } catch {
            #expect(error.localizedDescription
                == "Step 'build:' of 'gate': Invalid command 'build:': missing a variant name after ':'.")
        }
    }

    @Test("xc list shows a steps command's steps")
    func listSummary() {
        #expect(ListCommand.summarize(CommandConfig(steps: ["lint", "build:release"])) == "steps: lint, build:release")
    }

    @Test("a step reference prints the way it was written")
    func refText() throws {
        #expect(try CommandRef(parsing: "core/build:release").text == "core/build:release")
        #expect(try CommandRef(parsing: "lint").text == "lint")
    }
}
