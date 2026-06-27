# xc

**The task runner for Xcode projects.** Tame `xcodebuild` *and* run every project task (build, test, lint, codegen, release) from one `xc.yaml`.

<p align="center">
<img width="700" alt="hero" src="https://github.com/user-attachments/assets/57f2944d-2df2-4b89-9208-de01e9e5660e" />
</p>

Think `make` or `just`, but it natively understands schemes, destinations, SwiftPM packages, and xcodebuild.

```bash
# Before
xcodebuild build \
  -workspace App.xcworkspace \
  -scheme App \
  -configuration Release \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -derivedDataPath ./DerivedData

# After
xc build:release
```

## Why xc?

xc does two jobs in one tool:

**Tames xcodebuild.** Short `build:release` / `test:ci` variants instead of flag strings, `sim`/`mac` aliases instead of destination specs, and readable xcbeautify output by default.

**Runs your project tasks.** Wrap `swiftlint`, `swiftformat`, `tuist generate`, or any shell command as a first-class task, with the same variants, hooks, and `--dry-run` as a build. `xc list` is a self-documenting menu of every command in the repo.

One `xc.yaml`, shared by the whole team, portable across machines and CI with `${VAR}` interpolation.

## Installation

### Homebrew

```bash
brew install alexmx/tools/xc
```

### Mise

```bash
mise use --global github:alexmx/xc
```

## Quick Start

```bash
cd your-xcode-project

xc init            # auto-detects your project, generates xc.yaml
xc build           # build with defaults
xc test            # run tests
xc build:release   # switch to release in one word
xc doctor          # verify everything is set up correctly
```

## Configuration

One `xc.yaml` at your project root defines every command, builds and tasks alike:

```yaml
workspace: App.xcworkspace

destinations:                          # short names for long -destination strings
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"
  mac: "platform=macOS"

defaults:                              # applied to every command
  scheme: App
  configuration: Debug
  destination: sim

commands:
  build:
    hooks: { pre: "tuist generate" }   # a step to run before building
    variants:
      release: { configuration: Release }
  test:
    scheme: AppTests
    variants:
      ci:
        result-bundle-path: "./build/tests.xcresult"
        extra-args: ["-enableCodeCoverage", "YES"]
  archive: { configuration: Release, archive-path: "./build/App.xcarchive" }
  clean: {}
  lint:                                # a `run:` field makes it a shell task
    run: "swiftlint lint --quiet"
    variants:
      fix: { run: "swiftlint lint --fix" }
```

That single file gives you:

```bash
xc build           # debug build (runs tuist generate first)
xc build:release   # release build
xc test:ci         # tests with coverage + result bundle
xc archive         # release archive
xc lint:fix        # autofix lint
xc list            # the whole catalog, self-documenting
```

Commands without a `run:` field become `xcodebuild` invocations; commands with one are shell tasks. Both share variants, hooks, env vars, and the `xc list` catalog.

## CLI Reference

```
xc [<member>/]<command>[:<variant>] [options] [-- extra-xcodebuild-args...]
```

| Command | |
|---------|---|
| `xc <command>` | Run a configured command |
| `xc <member>/<command>` | Run a command in a nested member project |
| `xc list` | Show available commands, variants, and members |
| `xc init` | Generate `xc.yaml` from your project |
| `xc doctor` | Validate setup and diagnose issues |
| `xc destinations` | List available simulators and platforms |

| Option | |
|--------|---|
| `--dest <name>` | Override destination by name or raw string |
| `--raw` | Skip xcbeautify, show raw xcodebuild output |
| `-v`, `--verbose` | Print the resolved xcodebuild invocation |
| `--dry-run` | Print the command without executing it |
| `-C`, `--directory <dir>` | Run as if in `<dir>`, using its `xc.yaml` |
| `--all` | Run the command in every member project |
| `--members <names>` | Run the command in the listed members (comma-separated) |
| `--continue` | When fanning out, continue after a member fails |
| `--version` | Show version |

```bash
xc test --dest mac                             # test on macOS
xc build --dry-run                             # inspect without running
xc test --raw -- -enableAddressSanitizer YES   # raw output + extra flags
```

## Configuration Guide

### Variants

A variant inherits its command and overrides only what it names:

```yaml
commands:
  build:
    configuration: Debug
    variants:
      release: { configuration: Release }   # flip one field
      core:    { scheme: Core }              # swap the scheme
```

### Named destinations

Alias long `-destination` strings; pass a list to run several at once:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
  mac: "platform=macOS"
commands:
  test: { destination: [sim, mac] }   # test on both
```

Run `xc destinations` to see what's installed.

### Script commands

A `run:` field runs shell instead of xcodebuild. That's what turns xc into a task runner. Script commands take variants, hooks, extra-args, and `--dry-run` like any build, and share the `xc list` catalog:

```yaml
commands:
  generate: { run: "tuist generate" }
  loc:      { run: "find Sources -name '*.swift' | xargs wc -l | tail -1" }
```

### Any xcodebuild action

A command with no `run:` passes its name to `xcodebuild` as the action, so any action works, not just `build`/`test`/`clean`/`archive`:

```yaml
commands:
  build-for-testing: {}                          # compile once
  test-without-building: { test-plan: Smoke }     # then re-run without rebuilding
  analyze: {}
```

### Swift packages

A SwiftPM package has no `.xcodeproj`/`.xcworkspace`, so omit both `project` and `workspace` and xc drives the `Package.swift` in the current directory. Use `run: "swift build"` / `"swift test"` for the toolchain, or set `scheme:` + `destination:` to build the package with xcodebuild (for simulators or other platforms). See [`Examples/Package`](Examples/Package).

### Monorepos & members

Register nested projects as **members** of a root `xc.yaml` and drive them from the repo root. Each member stays a standalone `xc.yaml` that still works on its own:

```yaml
members:
  core: Packages/Core
  network: Packages/Network
```

```bash
xc -C Packages/Core test     # run in any directory's xc.yaml (no registration needed)
xc core/build:release        # member/command:variant
xc test --all                # fan out across members that define `test`
xc build --all --continue    # don't stop at the first failure
```

Fan-out runs sequentially, skips members that don't define the command, and is fail-fast unless `--continue`. `xc list` and `xc doctor` are member-aware. Members are one level deep and inherit nothing from the root; use the [global config](#global-config) for cross-project defaults. See [`Examples/Monorepo`](Examples/Monorepo).

### Environment variables

`${VAR}` and `${VAR:-default}` expand anywhere in the config:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"
```

```bash
IOS_SIMULATOR="iPhone SE" xc test   # override from env
```

### Hooks

`pre`/`post` shell steps on any command. A variant overrides them, or disables them with `hooks: {}`:

```yaml
commands:
  build:
    hooks: { pre: "swiftlint lint", post: "say 'build complete'" }
```

### Resolution order

Settings layer most to least specific: **CLI flags → variant → command → project `defaults` → global config**.

### Global config

`~/.config/xc/config.yaml` holds cross-project `defaults` and `settings`:

```yaml
defaults:
  destination: "platform=iOS Simulator,name=iPhone 17 Pro"
settings:
  formatter: xcbeautify   # or "xcbeautify --disable-logging", xcpretty, raw
  verbose: false
```

`formatter` is any shell command xcodebuild output is piped through; `raw` (or `--raw` on a single run) disables it. A project `xc.yaml` can set its own `settings` block to override the global one.

### Config reference

**Root fields:** `project` *or* `workspace` (mutually exclusive), `destinations`, `defaults`, `commands` (required), `settings`, `members`.

| Command field | Type | Description |
|-------|------|-------------|
| `run` | string | Shell script (makes this a script command) |
| `scheme` | string | Xcode scheme |
| `configuration` | string | Build configuration |
| `destination` | string or list | Destination name(s) or raw string(s) |
| `xcconfig` | string | Path to `.xcconfig` file |
| `test-plan` | string | Test plan (test commands only) |
| `result-bundle-path` | string | Result bundle path (test commands only) |
| `derived-data-path` | string | Custom derived data path |
| `archive-path` | string | Archive path (archive command only) |
| `extra-args` | list | Additional xcodebuild arguments |
| `hooks` | object | `pre` and `post` shell commands |
| `variants` | map | Named variant overrides |

## Diagnostics

`xc doctor` validates your setup; `xc list` prints the command catalog:

```
$ xc doctor
  OK    xc.yaml
  OK    Workspace    App.xcworkspace
  OK    Scheme: App
  OK    Dest: sim    iPhone 17 Pro
  OK    xcbeautify

$ xc list
  build
    :release   configuration: Release
  test         scheme: AppTests
    :ci        result-bundle-path: ./build/tests.xcresult, extra-args: -enableCodeCoverage YES
  lint         $ swiftlint lint --quiet
    :fix       $ swiftlint lint --fix
```

## Use with AI agents

A skill guide for agents driving xc lives at [`skills/use-xc/SKILL.md`](skills/use-xc/SKILL.md). Install it with [Skillman](https://github.com/alexmx/skillman):

```bash
skillman install github.com/alexmx/xc
```

## License

MIT
