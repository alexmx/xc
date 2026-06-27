---
name: use-xc
description: Use the xc CLI to build, test, archive, and run Xcode projects via a project's xc.yaml config. Use when the user asks to build, test, clean, archive, or lint an Xcode/iOS/macOS project, or to set up or edit an xc.yaml.
argument-hint: [command]
---

# xc: a better way to run xcodebuild

`xc` runs Xcode builds from short, named commands defined once in `xc.yaml` instead of long `xcodebuild` invocations. `xc build:release`, `xc test`, `xc archive`: no flag strings.

Requirements: macOS with Xcode. `xcbeautify` on PATH for formatted output (optional; falls back to raw). Run `xc doctor` to verify setup.

## Workflow

**Discover the config → run a command → inspect on failure.** Don't write raw `xcodebuild`: drive it through `xc`.

```bash
xc list                  # what commands + variants this project defines (START HERE)
xc build                 # run one
xc build:release         # run a variant
xc test --dest mac       # override destination for one run
```

- **Always `xc list` first** in an unfamiliar project: it's the source of truth for available commands, variants, and defaults. Don't guess command names.
- A project needs an `xc.yaml` at its root. If commands fail with "no config", run `xc doctor`, then `xc init` to generate one.
- **Never hand-roll `xcodebuild`** when an `xc` command exists. If a needed command isn't defined, add it to `xc.yaml` (see Editing the config) rather than bypassing xc.

## Command syntax

```
xc <command>[:<variant>] [options] [-- extra-xcodebuild-args...]
```

`<command>` and `<variant>` come from `xc list`. Everything after `--` is passed through to `xcodebuild` verbatim.

```bash
xc test:ci                                     # command "test", variant "ci"
xc test --raw -- -enableAddressSanitizer YES   # passthrough args after --
IOS_SIMULATOR="iPhone SE" xc test              # env vars feed ${VAR} in the config
```

## Options

- `--dest <name>`: override destination by config name (`sim`, `mac`, …) or a raw `platform=…` string. Names come from `xc destinations` / the config's `destinations` map.
- `--dry-run`: print the resolved command **without running it**. Use this to preview what xc will execute before a slow or destructive build.
- `-v`, `--verbose`: print the resolved `xcodebuild` invocation, then run it. Best first step when a build behaves unexpectedly.
- `--raw`: skip xcbeautify, stream raw xcodebuild output. Use when you need full diagnostics or xcbeautify is swallowing an error.
- `-C`, `--directory <dir>`: run as if you'd `cd <dir>` first, using that directory's `xc.yaml`. Works with no config changes.
- `--all` / `--members <names>`: fan a command out across member projects (see Monorepos below). `--continue` continues past a failing member.
- `--version`: print the xc version (also `xc --version`).

When a build fails, re-run with `--verbose` (see the real invocation) or `--raw` (see full output) before changing anything.

## Monorepos (members)

A root `xc.yaml` can register nested projects as **members** (`name: path`), each with its own standalone `xc.yaml`, e.g. a `Packages/` of SPM packages. Run `xc list` at the root to see members and their commands.

```yaml
members:
  core: Packages/Core
  network: Packages/Network
commands:
  lint: { run: "swiftlint lint --quiet" }   # root still needs ≥1 command
```

Three ways to drive nested projects:

```bash
xc -C Packages/Core test      # run in any directory's xc.yaml (no registration needed)
xc core/build                 # address a registered member: member/command[:variant]
xc test --all                 # fan out across all members that define `test`
xc build --members core,network --continue
```

Fan-out runs sequentially in declared order, **skips** members lacking the command, and stops at the first failure unless `--continue`. Members are one level deep and inherit nothing from the root: use global config (`~/.config/xc/config.yaml`) for cross-project defaults.

## Subcommands

### `xc <command>`: run a configured command (default)

The default subcommand. `xc build` is `xc run build`. Resolves the command (+ variant), layers in defaults and flags, runs xcodebuild or the command's `run:` script.

### `xc list`: show available commands and variants

Your map of the project. Prints each command, its variants (`:name`), script commands (`$ …`), and the active `defaults`. Run before doing anything else.

### `xc destinations`: list available simulators and platforms

What this machine can target. Use to pick a `--dest` value or to fill the `destinations` map in `xc.yaml`.

### `xc init`: generate xc.yaml

Auto-detects the project/workspace and schemes, writes a starter `xc.yaml`. Run once in a project that has none. Review and edit the result.

### `xc doctor`: validate setup

Checks `xc.yaml`, workspace/project, schemes, destinations, formatter, and global config: each line `OK`/error. First stop when commands fail to resolve.

## Editing the config

`xc.yaml` lives at the project root. Settings layer most- to least-specific: **CLI flags → variant → command → project `defaults` → global `~/.config/xc/config.yaml`**. A variant inherits its command and overrides only what it names.

```yaml
workspace: App.xcworkspace          # or `project: App.xcodeproj` (mutually exclusive)

destinations:                       # short names for long destination strings
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"
  mac: "platform=macOS"

defaults:                           # applied to every command
  scheme: App
  configuration: Debug
  destination: sim

commands:                           # required
  build:
    hooks: { pre: "tuist generate" }   # pre/post shell steps
    variants:
      release: { configuration: Release }   # inherits build, overrides config only
  test:
    scheme: AppTests
    destination: [sim, mac]            # a list tests on multiple destinations
  clean: {}                            # empty command = just the defaults
  archive:
    configuration: Release
    archive-path: "${BUILD_DIR:-./build}/App.xcarchive"
  build-for-testing: {}                # the command name IS the xcodebuild action
  test-without-building:               # → xcodebuild test-without-building (no recompile)
    test-plan: Smoke
  lint:
    run: "swiftlint lint --quiet"      # `run:` makes it a script command, not xcodebuild
    variants:
      fix: { run: "swiftlint lint --fix" }

settings:                             # optional project-level settings (also valid in global config)
  formatter: "xcbeautify --disable-logging"
  verbose: false
```

Key points when authoring:
- **Root fields**: `project` *or* `workspace` (mutually exclusive), `destinations`, `defaults`, `commands` (required), `settings`, `members` (nested projects: see Monorepos).
- **Command fields**: `run`, `scheme`, `configuration`, `destination` (string or list), `xcconfig`, `test-plan`, `result-bundle-path`, `derived-data-path`, `archive-path`, `extra-args` (list), `hooks` (`pre`/`post`), `variants`.
- **A command's name is passed to `xcodebuild` as its action** (unless it has `run:`). Beyond `build`/`test`/`clean`/`archive`, any xcodebuild action works: `build-for-testing`, `test-without-building` (re-run tests with no recompile: `-testPlan` still applies), `analyze`, etc. Pair `build-for-testing` (compile once) with `test-without-building` (fast reruns / CI split).
- **Ad-hoc Swift packages**: a SwiftPM package has no `.xcodeproj`/`.xcworkspace`: omit **both** `project` and `workspace` (only one of the two may be set, and neither is required). Two ways to drive a package:
  - `run:` scripts for the swift toolchain: `swift build`, `swift test`, `swift run`. Simplest; no scheme/destination needed.
  - xcodebuild against the package's auto-generated scheme (named after the package): set `scheme:` + `destination:` to build/test for a simulator or other platform.

```yaml
# xc.yaml for a Swift package: no project/workspace
defaults: { scheme: MyPackage, destination: "platform=macOS" }
commands:
  swift-build: { run: "swift build" }
  swift-test:  { run: "swift test --parallel" }
  build: {}                      # → xcodebuild build -scheme MyPackage ...
  test:  {}                      # → xcodebuild test  -scheme MyPackage ...
```
- **`run:` commands** are plain shell (lint, format, codegen): they support hooks, variants, `extra-args`, and `--dry-run` like build commands.
- **Env vars**: `${VAR}` or `${VAR:-default}` anywhere: keeps configs portable across machines/CI.
- **Hooks** on a command run for all its variants; a variant overrides them or disables with `hooks: {}`.
- **`settings`** (`formatter`, `verbose`) can live in the project `xc.yaml` *or* in global config. `formatter` is any shell command output is piped to: `xcbeautify` (default), `xcpretty`, `raw` (none), or one with flags like `"xcbeautify --disable-logging"`.
- **Global config** `~/.config/xc/config.yaml` holds cross-project `defaults` and `settings`.

After editing, run `xc list` (confirm it parses and shows what you expect) and `xc doctor` (confirm schemes/destinations resolve). Use `--dry-run` to verify the produced invocation before a real build.
