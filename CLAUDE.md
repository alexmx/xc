# xc

A Swift CLI (SwiftPM, Swift 6.2, macOS 15+) that runs `xcodebuild` and project tasks from an `xc.yaml`. This repo's own `xc.yaml` drives its workflow.

## Verify

- `xc gate`: lint (swiftformat), build and test, with a timing summary. Run it before every commit. Without an installed xc: `swift run xc gate`.
- `xc lint:fix` reformats.

## Before a release

- `xc smoke`: builds the universal release binary and runs `scripts/smoke.py` against this repo, `Examples/` and temporary fixtures (a couple of minutes). It needs tuist (via mise), swiftlint, xcbeautify, an iPhone simulator and the "iPad Pro 13-inch (M5)" simulator. `xc smoke -- <group>` runs one group. Fixtures and logs go to `.build/smoke`.
- `xc build:release` builds the same universal binary the release workflow ships.
- To release: bump `.xc-version` on `main` and push. `.github/workflows/release.yml` tags `vX.Y.Z` and publishes the binary. Commit the bump as `fix: bump version to X.Y.Z`.

## Layout

- `Sources/XC/Commands`: one file per subcommand; `RunCommand+Steps.swift` runs `steps:` commands.
- `Sources/XC/Config`: `xc.yaml` models and loading (`${VAR}` expansion, `XC_ROOT`, members, global config).
- `Sources/XC/Core`: `CommandResolver` turns a command into a script, xcodebuild invocation or steps; `CommandRunner` and `ShellRunner` run them; `XcodeQueries` reads simctl and `xcodebuild -list`.
- `Tests/XCTests`: Swift Testing. `RunCommandRunTests` drives `xc run` end to end through ArgumentParser against temporary projects.

## Conventions

- Tests use Swift Testing with `@Test("...")` names (`.swiftformat` keeps that style). A bug fix starts with a test that fails on the bug.
- Child processes go through swift-subprocess, never Foundation's `Process`.
- A user-visible change updates `README.md` and `skills/use-xc/SKILL.md` in the same change.
