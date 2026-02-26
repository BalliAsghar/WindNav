# WindNav

WindNav is a lightweight macOS keyboard navigation agent.
It preserves your current window layout and only changes focus.

## Features (v1)

- Global hotkeys via Carbon (`RegisterEventHotKey`)
- AX window discovery for visible standard windows
- Logical focus cycling (`left/right`) using MRU order
- Current-monitor-only targeting
- TOML config with auto-reload

## Config

Path: `~/.config/windnav/config.toml`

```toml
[hotkeys]
focus-left = "cmd-left"
focus-right = "cmd-right"

[navigation]
scope = "current-monitor"
policy = "mru-cycle"
no-candidate = "noop"
filtering = "conservative"
cycle-timeout-ms = 900

[logging]
level = "info" # info|error
color = "auto" # auto|always|never
```

`left` means previous window in the logical cycle, and `right` means next.
`up/down` are intentionally not bound in v1.1.

## Log Output

WindNav writes structured logs to stdout:

```text
[07:10:11] Runtime    -> Starting WindNav
[07:10:11] Config     -> Loaded config from /Users/balli/.config/windnav/config.toml
[07:10:11] Hotkey     -> Registered left (keyCode=123, modifiers=256)
[07:10:13] Hotkey     -> Hotkey pressed: right
[07:10:13] Navigation -> Direction=right focused=52361 candidates=5
[07:10:13] Navigation -> Focused target window 52403
```

## Run (Dev)

```bash
cd /Users/balli/code/WindNav
swift run WindNav
```

On first launch, grant Accessibility permission when prompted.

## Build (Release Binary)

```bash
cd /Users/balli/code/WindNav
swift build -c release --product WindNav
```

Binary output:

```text
/Users/balli/code/WindNav/.build/arm64-apple-macosx/release/WindNav
```

## Build App Bundle With Icon

WindNav uses repo-owned icon assets:

```text
/Users/balli/code/WindNav/Packaging/windnav.svg
/Users/balli/code/WindNav/Packaging/windnav.icns
```

Build app bundle (no args):

```bash
cd /Users/balli/code/WindNav
./scripts/build_app.sh
```

Bundle output:

```text
/Users/balli/code/WindNav/dist/WindNav.app
```

Launch:

```bash
open /Users/balli/code/WindNav/dist/WindNav.app
```

Defaults:

- `Bundle ID`: `com.windnav.app`
- signing: skipped
- app type: background agent (`LSUIElement=true`)
