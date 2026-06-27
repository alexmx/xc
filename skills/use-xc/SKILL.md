---
name: use-xc
description: Use the xc CLI to build, test, archive, and run any project task for Xcode/iOS/macOS projects via a project's xc.yaml config. Use when the user asks to build, test, clean, archive, lint, format, or run a project task or script, or to set up or edit an xc.yaml.
argument-hint: [command]
---

# xc: the task runner for Xcode projects

`xc` runs both `xcodebuild` builds and arbitrary project tasks (lint, format, codegen, release) from short named commands in `xc.yaml`, instead of long `xcodebuild` invocations and scattered scripts. One catalog (`xc list`) for everything. Needs macOS + Xcode; `xcbeautify` on PATH for formatted output (else raw).

## Workflow

**`xc list` first** (source of truth for commands/variants/defaults), then run, then inspect on failure. Never hand-roll `xcodebuild` when an `xc` command exists; if one's missing, add it to `xc.yaml`.

```bash
xc list                  # commands + variants this project defines (START HERE)
xc build:release         # run a command:variant
xc test --dest mac       # override destination for one run
```

A project needs an `xc.yaml` (or `xc.yml`) at its root; on "no config" run `xc init` to generate one.

## Command syntax

```
xc [<member>/]<command>[:<variant>] [options] [-- extra-xcodebuild-args...]
```

`<command>`/`<variant>` come from `xc list`. Args after `--` pass to `xcodebuild` verbatim.

```bash
xc test:ci                                     # command "test", variant "ci"
xc test --raw -- -enableAddressSanitizer YES   # passthrough args
IOS_SIMULATOR="iPhone SE" xc test              # env feeds ${VAR} in the config
```

## Options

- `--dest <name>`: destination by config name (`sim`, `mac`) or raw `platform=…` string.
- `--dry-run`: print the resolved command without running it.
- `-v`/`--verbose`: print the resolved `xcodebuild` invocation, then run. First step when a build misbehaves.
- `--raw`: raw xcodebuild output, no xcbeautify.
- `-C`/`--directory <dir>`: run as if `cd <dir>` first, using that dir's `xc.yaml`.
- `--all` / `--members <names>` / `--continue`: fan-out across members (see below).
- `--version`.

On failure, re-run with `--verbose` or `--raw` before changing anything.

## Subcommands

- `xc <command>` (default, = `xc run`): resolve command+variant, layer defaults/flags, run xcodebuild or the `run:` script.
- `xc list`: every command, variant (`:name`), script (`$ …`), and `defaults`.
- `xc destinations`: simulators/platforms this machine can target.
- `xc init`: generate a starter `xc.yaml` from the detected project/schemes.
- `xc doctor`: validate `xc.yaml`, workspace/project, schemes, destinations, formatter, global config, members.

## Monorepos (members)

A root `xc.yaml` registers nested projects as **members** (`name: path`), each a standalone `xc.yaml` (e.g. a `Packages/` of SPM packages). `xc list` at the root shows members + their commands.

```yaml
members:
  core: Packages/Core
  network: Packages/Network
commands:
  lint: { run: "swiftlint lint --quiet" }   # root still needs ≥1 command
```

```bash
xc -C Packages/Core test   # any directory's xc.yaml (no registration needed)
xc core/build:release      # member/command[:variant]
xc test --all              # root + every member that defines `test`
xc build --members core,network --continue
```

`--all` = root project + every member; `--members a,b` = those members only (root excluded). Fan-out is sequential in declared order, **skips** targets lacking the command, fail-fast unless `--continue`. Members are one level deep and inherit nothing from root; use global config for cross-project defaults.

## Editing the config

Layering, most→least specific: **CLI flags → variant → command → project `defaults` → global `~/.config/xc/config.yaml`**. A variant inherits its command, overriding only what it names.

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
    hooks: { pre: "tuist generate" }
    variants:
      release: { configuration: Release }   # overrides only configuration
  test:
    scheme: AppTests
    destination: [sim, mac]                  # a list tests on multiple destinations
  clean: {}                                  # empty = just the defaults
  archive:
    configuration: Release
    archive-path: "${BUILD_DIR:-./build}/App.xcarchive"
  build-for-testing: {}                      # command name IS the xcodebuild action
  test-without-building: { test-plan: Smoke }
  lint:
    run: "swiftlint lint --quiet"            # `run:` = script command, not xcodebuild
    variants:
      fix: { run: "swiftlint lint --fix" }

settings:                           # optional; also valid in global config
  formatter: "xcbeautify --disable-logging"
  verbose: false
```

- **Root fields**: `project` *or* `workspace` (mutually exclusive), `destinations`, `defaults`, `commands` (required), `settings`, `members`.
- **Command fields**: `run`, `scheme`, `configuration`, `destination` (string or list), `xcconfig`, `test-plan`, `result-bundle-path`, `derived-data-path`, `archive-path`, `extra-args` (list), `hooks` (`pre`/`post`), `variants`.
- **Command name = xcodebuild action** (unless `run:`): `build`/`test`/`clean`/`archive`, plus `build-for-testing`, `test-without-building` (`-testPlan` applies), `analyze`, etc. Pair build-for-testing (compile once) + test-without-building (fast reruns).
- **`run:` commands**: plain shell (lint/format/codegen); support hooks, variants, `extra-args`, `--dry-run`.
- **Env vars**: `${VAR}` / `${VAR:-default}` anywhere.
- **Hooks**: a command's hooks run for all its variants; a variant overrides them or disables with `hooks: {}`.
- **`settings`** (`formatter`, `verbose`): project `xc.yaml` or global config. `formatter` = shell command output is piped through: `xcbeautify` (default), `xcpretty`, `raw`, or with flags.
- **Swift package** (no `.xcodeproj`/`.xcworkspace`): omit both `project` and `workspace`. Drive via `run:` swift scripts, or xcodebuild against the auto-generated scheme (named after the package) with `scheme:`+`destination:`.

```yaml
# Swift package: no project/workspace
defaults: { scheme: MyPackage, destination: "platform=macOS" }
commands:
  swift-build: { run: "swift build" }
  swift-test:  { run: "swift test --parallel" }
  build: {}    # → xcodebuild build -scheme MyPackage ...
  test:  {}    # → xcodebuild test  -scheme MyPackage ...
```

After editing: `xc list` (parses?) and `xc doctor` (schemes/destinations resolve?); `--dry-run` to check the invocation.
