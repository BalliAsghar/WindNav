<p align="center">
    <img src="Packaging/AppIcon.svg" alt="Icon" width="256" height="256">
</p>

# WindNav

WindNav is a lightweight macOS keyboard navigation agent.
It preserves your current window layout and only changes focus.

## Features (v1)

- Global hotkeys via Carbon (`RegisterEventHotKey`)
- AX window discovery for visible standard windows
- Predictable app-level focus cycling (`left/right`) with in-app window cycling (`up/down`)
- Current-monitor-only targeting
- TOML config (loaded on startup)

## Config

Path: `~/.config/windnav/config.toml`

```toml
[hotkeys]
focus-left = "cmd-left"
focus-right = "cmd-right"
focus-up = "cmd-up"     # in-app window cycling (forward)
focus-down = "cmd-down" # in-app window cycling (reverse)

[navigation]
policy = "fixed-app-ring" # currently fixed-app-ring is the only active policy
cycle-timeout-ms = 900
# set to 0 to keep cycling active until you release hotkey modifiers

[logging]
level = "info" # info|error
color = "auto" # auto|always|never

[startup]
launch-on-login = false

[hud]
enabled = true
show-icons = true
position = "middle-center"
```

`left/right` cycle apps in the configured ring.
`up/down` cycle windows within the selected app.
Hotkey modifiers support short and full names: `cmd|command`, `opt|option|alt`, `ctrl|control|ctl`, `shift`.
Multiple modifiers are supported, e.g. `cmd-shift-left` or `ctrl-opt-right`.
Set `navigation.cycle-timeout-ms = 0` to disable time-based session reset and end cycling (and hide HUD) when modifiers are released.
Config changes are applied on startup. Restart WindNav after editing `config.toml`.
`launch-on-login` is applied on startup.
HUD positions: `top-center`, `middle-center`, `bottom-center`.

## Log Output

WindNav writes structured logs to stdout:

```text
[07:10:11] Runtime    -> Starting WindNav
[07:10:11] Config     -> Loaded config from /Users/balli/.config/windnav/config.toml
[07:10:11] Startup    -> Launch-on-login already disabled (status=notRegistered)
[07:10:11] Hotkey     -> Registered left (keyCode=123, modifiers=256)
[07:10:13] Hotkey     -> Hotkey pressed: right
[07:10:13] Navigation -> Direction=right focused=52361 candidates=5
[07:10:13] Navigation -> Focused target window 52403
```

Launch-at-login can additionally log:

```text
[07:10:11] Startup    -> Applying launch-on-login=true (status-before=notRegistered)
[07:10:11] Startup    -> Launch-on-login set requested=true status-after=enabled
[07:10:11] Startup    -> Launch-on-login set requested=true status-after=requiresApproval
[07:10:11] Startup    -> Failed to apply launch-on-login=true; continuing startup: <error>
```

## Run (Dev)

```bash
cd /Users/balli/code/WindNav
swift run WindNav
```

On first launch, grant Accessibility permission when prompted.
If `launch-on-login` is enabled, run as bundled app (`dist/WindNav.app`) for `SMAppService.mainApp` registration behavior.
When running with `swift run WindNav`, launch-at-login registration can fail and is logged but non-fatal.
When running as `dist/WindNav.app`, stdout/stderr are redirected to `/tmp/windnav.log`.

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
