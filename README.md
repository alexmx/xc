# xc

**A better way to run xcodebuild. Stop typing flags. Start shipping.**

<p align="center">
<img width="700" alt="hero" src="https://github.com/user-attachments/assets/57f2944d-2df2-4b89-9208-de01e9e5660e" />
</p>

That's it. No more copying 200-character `xcodebuild` invocations from your wiki. Define your commands once in `xc.yaml`, use them forever.

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

Built for fast, repeatable Xcode workflows.

- **One config, shared by all**: Keep commands in `xc.yaml` so everyone runs the same builds.
- **Variants over flags**: Use `build:release` or `test:coverage` instead of long flag strings.
- **Named destinations**: Use `sim`, `mac`, or `device` aliases instead of full destination specs.
- **Script support**: Run tools like `swiftlint` or `tuist generate` as first-class commands.
- **Env var support**: Use `${VAR}` and `${VAR:-default}` to keep configs portable.
- **Hooks built in**: Run pre/post steps for linting, setup, or notifications.
- **Readable output**: Use xcbeautify by default, switch to raw logs with `--raw`.

---

## Installation

### Homebrew

```bash
brew install alexmx/tools/xc
```

To update:

```bash
brew upgrade alexmx/tools/xc
```

### Mise

```bash
mise use --global github:alexmx/xc
```

Or in `mise.toml` for a project-scoped install:

```toml
[tools]
"github:alexmx/xc" = "latest"
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

## The Config

`xc.yaml` at the root of your project:

```yaml
workspace: App.xcworkspace

destinations:
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"
  mac: "platform=macOS"

defaults:
  scheme: App
  configuration: Debug
  destination: sim

commands:
  build:
    hooks:
      pre: "tuist generate"
    variants:
      release:
        configuration: Release

  test:
    scheme: AppTests
    variants:
      ci:
        result-bundle-path: "./build/tests.xcresult"
        extra-args:
          - "-enableCodeCoverage"
          - "YES"

  clean: {}

  archive:
    configuration: Release
    archive-path: "./build/App.xcarchive"

  lint:
    run: "swiftlint lint --quiet"
    variants:
      fix:
        run: "swiftlint lint --fix"
```

That config gives you:

```bash
xc build              # debug build (runs tuist generate first)
xc build:release      # release build
xc test               # run tests
xc test:ci            # tests with coverage + result bundle
xc archive            # create release archive
xc clean              # clean build
xc lint               # run swiftlint
xc lint:fix           # autofix lint issues
```

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
xc build --verbose                             # see what xcodebuild gets
xc build --dry-run                             # inspect without running
xc test --raw -- -enableAddressSanitizer YES   # raw output + extra flags
xc -C Packages/Core test                       # run in another directory's xc.yaml
xc core/build:release                          # run a member's command
xc test --all                                  # run `test` across all members
```

## Configuration Guide

### Named Destinations

Give short names to long destination strings:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
  sim-ipad: "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
  mac: "platform=macOS"

defaults:
  destination: sim
```

Test on multiple destinations at once:

```yaml
commands:
  test:
    destination:
      - sim
      - sim-ipad
```

Run `xc destinations` to see what's available on your machine.

### Variants

A variant inherits everything from its parent command and overrides only what it specifies:

```yaml
commands:
  build:
    scheme: App
    configuration: Debug
    variants:
      release:
        configuration: Release    # only this changes
      core:
        scheme: Core              # different scheme, same config
```

```bash
xc build          # scheme: App, configuration: Debug
xc build:release  # scheme: App, configuration: Release
xc build:core     # scheme: Core, configuration: Debug
```

### Command Names Are xcodebuild Actions

A command's name is passed straight to `xcodebuild` as its action, so any xcodebuild action works — not just `build`, `test`, `clean`, and `archive`:

```yaml
commands:
  build-for-testing: {}        # → xcodebuild build-for-testing ...
  test-without-building:       # → xcodebuild test-without-building ... (no recompile)
    test-plan: Smoke
  analyze: {}                  # → xcodebuild analyze ...
```

Pair `build-for-testing` (compile once) with `test-without-building` (re-run the existing build) to skip recompilation on test reruns or split build and test across CI stages. Test-only options like `test-plan` still apply to `test-without-building`. Commands with a `run` field are shell scripts instead (see below).

### Script Commands

Add a `run` field to execute shell scripts instead of xcodebuild:

```yaml
commands:
  generate:
    run: "tuist generate"

  lint:
    run: "swiftlint lint --quiet"
    variants:
      fix:
        run: "swiftlint lint --fix"

  loc:
    run: "find Sources -name '*.swift' | xargs wc -l | tail -1"
```

Scripts support hooks, variants, extra-args, and `--dry-run` like any other command.

### Swift Packages

A SwiftPM package has no `.xcodeproj` or `.xcworkspace` — just omit both `project` and `workspace`. xc then drives the `Package.swift` in the current directory. There are two ways to build a package:

```yaml
destinations:
  mac: "platform=macOS"
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"

defaults:
  scheme: MyPackage      # xcodebuild auto-generates a scheme named after the package
  destination: mac

commands:
  # 1. swift toolchain — the native way, no scheme/destination needed
  swift-build:
    run: "swift build"
  swift-test:
    run: "swift test --parallel"

  # 2. xcodebuild — build/test the package for a simulator or other platform
  build:
    variants:
      ios: { destination: sim }
  test:
    variants:
      ios: { destination: sim }
```

```bash
xc swift-test       # swift test --parallel
xc build            # xcodebuild build -scheme MyPackage -destination platform=macOS
xc test:ios         # xcodebuild test  -scheme MyPackage -destination "platform=iOS Simulator,..."
```

See [`Examples/Package`](Examples/Package) for a complete runnable example.

### Monorepos & Members

In a repo with several projects (say a `Packages/` directory of SPM packages, each with its own `xc.yaml`), register them as **members** of a root `xc.yaml` and drive them all from the repo root:

```yaml
# repo-root/xc.yaml
members:
  core: Packages/Core
  network: Packages/Network

commands:
  lint:
    run: "swiftlint lint --quiet"   # the root can still have its own commands
```

Each member stays a normal, standalone `xc.yaml` (it still works if you `cd` into it). There are three ways to use them:

```bash
# 1. Run in any directory's xc.yaml (no registration needed) — like `cd dir && xc`
xc -C Packages/Core test

# 2. Address a registered member's command directly (runs with that member as cwd)
xc core/build
xc core/test:ci          # member `core`, command `test`, variant `ci`

# 3. Fan out a command across members
xc test --all            # run `test` in every member that defines it
xc build --members core,network
xc build --all --continue   # don't stop at the first failure
```

Fan-out runs sequentially in declared order, **skips** members that don't define the command, and stops at the first failure unless `--continue` is passed (then it reports which members failed at the end). `xc list` and `xc doctor` are member-aware — `list` shows each member's commands, `doctor` validates that each member's `xc.yaml` loads.

Members are one level deep and inherit nothing from the root by default — for cross-project defaults, use the [global config](#global-config). See [`Examples/Monorepo`](Examples/Monorepo) for a complete runnable example.

### Environment Variables

Use `${VAR}` or `${VAR:-default}` anywhere in the config:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"

commands:
  archive:
    archive-path: "${BUILD_DIR:-./build}/App.xcarchive"
```

```bash
IOS_SIMULATOR="iPhone SE" xc test   # override from env
```

### Hooks

Run scripts before and after any command:

```yaml
commands:
  build:
    hooks:
      pre: "swiftlint lint"
      post: "say 'build complete'"
    variants:
      release:
        hooks:
          pre: "swiftlint lint --strict"   # overrides the command hooks
      quick:
        hooks: {}                          # disables hooks for this variant
```

Hooks defined on a command run for all its variants. A variant can override hooks or disable them entirely with `hooks: {}`.

### Resolution Order

Settings layer from most to least specific:

1. CLI flags (`--dest`, `-- extra-args`)
2. Variant config
3. Command config
4. Project defaults (`defaults` in `xc.yaml`)
5. Global defaults (`~/.config/xc/config.yaml`)

### Global Config

Shared defaults across all your projects at `~/.config/xc/config.yaml`:

```yaml
defaults:
  destination: "platform=iOS Simulator,name=iPhone 17 Pro"

settings:
  formatter: xcbeautify
  verbose: false
```

The `formatter` setting controls how xcodebuild output is processed. Any value is run as a shell command with xcodebuild output piped into it:

```yaml
settings:
  formatter: xcbeautify                              # default — auto-detected from PATH
  formatter: "xcbeautify --disable-logging"           # custom flags
  formatter: xcpretty                                # different tool
  formatter: raw                                     # no formatting
```

Use `--raw` on any command to skip formatting for a single invocation.

A `settings` block can also live in a project's `xc.yaml`, overriding the global config for that project:

```yaml
settings:
  formatter: "xcbeautify --disable-logging"
```

### Config Reference

**Root fields:**

| Field | Type | Description |
|-------|------|-------------|
| `project` | string | Path to `.xcodeproj` (mutually exclusive with `workspace`) |
| `workspace` | string | Path to `.xcworkspace` |
| `destinations` | map | Named destination aliases |
| `defaults` | object | Default settings applied to all commands |
| `commands` | map | Command definitions (required) |
| `settings` | object | `formatter` / `verbose` (see [Global Config](#global-config)); set here to override per project |
| `members` | map | Nested projects, `name: path` — addressable as `name/command` (see [Monorepos & Members](#monorepos--members)) |

**Command fields:**

| Field | Type | Description |
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

```
$ xc doctor
  OK    xc.yaml
  OK    Workspace    App.xcworkspace
  OK    Scheme: App
  OK    Scheme: AppTests
  OK    Dest: sim    iPhone 17 Pro
  OK    Dest: mac    macOS
  OK    xcbeautify
  OK    Global config    ~/.config/xc/config.yaml
```

```
$ xc list
  defaults     scheme: App, configuration: Debug, destination: sim

  archive      configuration: Release, archive-path: ./build/App.xcarchive
  build
    :release   configuration: Release
  clean
  lint         $ swiftlint lint --quiet
    :fix       $ swiftlint lint --fix
  test         scheme: AppTests
    :ci        result-bundle-path: ./build/tests.xcresult, extra-args: -enableCodeCoverage YES
```

## Use with AI agents

A skill guide for agents driving xc via the CLI lives at [`skills/use-xc/SKILL.md`](skills/use-xc/SKILL.md). Install it with [Skillman](https://github.com/alexmx/skillman):

```bash
skillman install github.com/alexmx/xc
```

## License

MIT
