# xc

A better way to run xcodebuild.

Define your build commands once in `xc.yaml`, then run them with `xc build` instead of typing out the full xcodebuild invocation every time. Variants like `xc build:release` switch configuration with zero flags. Think of it as `package.json` scripts for Xcode projects.

```
# instead of:
xcodebuild build -workspace App.xcworkspace -scheme App -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"

# just run:
xc build
```

## Install

```bash
git clone https://github.com/alexmx/xc.git
cd xc
swift build -c release
cp .build/release/xc /usr/local/bin/xc
```

Requires Swift 6.2+ and macOS 15+.

**Optional:** Install [xcbeautify](https://github.com/cpisciotta/xcbeautify) for formatted output:
```bash
brew install xcbeautify
```

## Quick Start

```bash
cd your-xcode-project
xc init          # generates xc.yaml from your project
xc build         # build with defaults
xc test          # run tests
xc build:release # build with release variant
```

## Usage

```
xc <command>[:<variant>] [options] [-- extra-xcodebuild-args...]
```

### Commands

| Command | Description |
|---------|-------------|
| `xc <command>` | Run a configured command (default) |
| `xc init` | Generate `xc.yaml` from your project |
| `xc list` | Show available commands and variants |
| `xc doctor` | Validate project setup and diagnose issues |
| `xc destinations` | List available destinations and simulators |

### Options

| Option | Description |
|--------|-------------|
| `--dest <name>` | Override destination (name or raw string) |
| `--raw` | Show raw xcodebuild output (skip xcbeautify) |
| `-v`, `--verbose` | Print the resolved xcodebuild invocation |
| `--dry-run` | Print the command without executing it |
| `--version` | Show version |

### Examples

```bash
xc build                              # build with defaults
xc build:release                      # build with release variant
xc test --dest mac                    # test on macOS instead of simulator
xc build --verbose                    # see the full xcodebuild invocation
xc build --dry-run                    # print without executing
xc test --raw -- -enableAddressSanitizer YES  # raw output + extra flags
xc lint                               # run a script command
xc lint:fix                           # run a script variant
```

## Configuration

### `xc.yaml`

Place `xc.yaml` at the root of your project. xc searches upward from the current directory, so it works from any subdirectory.

```yaml
workspace: App.xcworkspace

destinations:
  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
  mac: "platform=macOS"

defaults:
  scheme: App
  configuration: Debug
  destination: sim

commands:
  build:
    hooks:
      pre: "echo 'Building...'"
      post: "echo 'Done.'"
    variants:
      release:
        configuration: Release

  test:
    variants:
      coverage:
        extra-args:
          - "-enableCodeCoverage"
          - "YES"

  clean: {}

  archive:
    configuration: Release
    archive-path: "./build/App.xcarchive"
```

### Config Reference

#### Root

| Field | Type | Description |
|-------|------|-------------|
| `project` | string | Path to `.xcodeproj` (mutually exclusive with `workspace`) |
| `workspace` | string | Path to `.xcworkspace` (mutually exclusive with `project`) |
| `destinations` | map | Named destination aliases |
| `defaults` | object | Default settings applied to all commands |
| `commands` | map | Command definitions (required) |

#### Command Fields

| Field | Type | Description |
|-------|------|-------------|
| `run` | string | Shell script to execute (makes this a script command) |
| `scheme` | string | Xcode scheme |
| `configuration` | string | Build configuration (Debug, Release, etc.) |
| `destination` | string or list | Destination name(s) or raw string(s) |
| `test-plan` | string | Test plan name (test commands only) |
| `result-bundle-path` | string | Result bundle output path (test commands only) |
| `xcconfig` | string | Path to `.xcconfig` file |
| `derived-data-path` | string | Custom derived data path |
| `archive-path` | string | Archive output path (archive command only) |
| `extra-args` | list | Extra arguments passed to xcodebuild |
| `hooks` | object | Pre/post hooks (`pre:` and `post:` shell commands) |
| `variants` | map | Named variants that override this command's settings |

### Resolution Order

Settings are layered from most to least specific:

1. CLI flags (`--dest`, `-- extra-args`)
2. Variant config
3. Command config
4. Project defaults (`defaults` in `xc.yaml`)
5. Global defaults (`~/.config/xc/config.yaml`)

Variant fields **override** the parent command — they don't merge. For `extra-args`, variant args replace base args entirely.

### Named Destinations

Define destination aliases to avoid repeating long strings:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
  sim-ipad: "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
  mac: "platform=macOS"

defaults:
  destination: sim    # reference by name
```

A command can target multiple destinations:

```yaml
commands:
  test:
    destination:
      - sim
      - sim-ipad
```

Run `xc destinations` to see available simulators on your machine.

### Script Commands

Commands with a `run` field execute shell scripts instead of xcodebuild:

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

```bash
xc lint          # runs swiftlint lint --quiet
xc lint:fix      # runs swiftlint lint --fix
```

Script commands support hooks, variants, `extra-args`, and `--dry-run` just like xcodebuild commands.

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
IOS_SIMULATOR="iPhone SE" xc test    # override simulator via env
```

Only the `${}` syntax is supported — bare `$VAR` is not expanded.

### Hooks

Run shell commands before and after any command:

```yaml
commands:
  build:
    hooks:
      pre: "swiftlint lint"
      post: "say 'build complete'"
    variants:
      release:
        hooks:
          pre: "swiftlint lint --strict"  # variant hooks override command hooks
```

### Global Config

Optional global defaults at `~/.config/xc/config.yaml`:

```yaml
defaults:
  destination: "platform=iOS Simulator,name=iPhone 17 Pro"

settings:
  formatter: xcbeautify
  verbose: false
```

Global defaults apply when neither the command nor project defaults specify a value.

## Diagnostics

### `xc doctor`

Validates your entire setup:

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

### `xc list`

Shows all available commands and variants:

```
$ xc list
archive    configuration: Release, archive-path: ./build/App.xcarchive
build
  :release    configuration: Release
clean
test
  :coverage    extra-args: -enableCodeCoverage YES
```

## License

MIT
