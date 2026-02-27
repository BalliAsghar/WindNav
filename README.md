<p align="center">
    <img src="Packaging/AppIcon.svg" alt="Icon" width="256" height="256">
</p>

# WindNav

WindNav is a macOS keyboard navigation tool that helps you move between apps and windows without disturbing your layout.

## Why Use WindNav

WindNav gives you one consistent keyboard flow for app and window switching:

- `left` / `right`: move between apps.
- `up` / `down`: open app-browse HUD, then cycle windows in the selected app during browse.
- Works with minimized windows and hidden apps by default (both configurable).
- Keeps navigation monitor-aware and predictable.
- Optional HUD shows exactly where you are in the cycle.

### Visual Guide (30 seconds)

1. Hold your modifier key (default: `Command`).
2. The first arrow you press locks the flow for this hold:
   - `left`/`right` first: immediate navigation flow.
   - `up`/`down` first: browse flow with deferred commit.
3. In browse flow, use `left`/`right` to select app and `up`/`down` to pick window.
4. Release the modifier to commit only in browse flow.

## Quick Start

1. Build the app bundle:

```bash
cd /path/to/WindNav
./scripts/build_app.sh
```

2. Move WindNav into your Applications folder:

```bash
mv dist/WindNav.app /Applications/
```

3. Launch from Applications:

```bash
open -a WindNav
```

4. On first launch, grant **Accessibility** permission when macOS prompts you.

## Default Shortcuts

- `cmd-left`: previous app (immediate)
- `cmd-right`: next app (immediate)
- `cmd-up`: open browse HUD / next window in selected browse app
- `cmd-down`: open browse HUD / previous window in selected browse app

## Personalize WindNav

Config file location:

```text
~/.config/windnav/config.toml
```

WindNav creates this file automatically on first launch.

Example configuration:

```toml
[hotkeys]
focus-left = "cmd-left"
focus-right = "cmd-right"
focus-up = "cmd-up"
focus-down = "cmd-down"

[navigation]
mode = "standard"
cycle-timeout-ms = 0
include-minimized = true
include-hidden-apps = true

[navigation.standard]
pinned-apps = ["com.openai.codex", "com.microsoft.VSCode"]
unpinned-apps = "append"
in-app-window = "last-focused"
grouping = "one-stop-per-app"

[startup]
launch-on-login = false

[hud]
enabled = true
show-icons = true
position = "middle-center"
```

Bundle ID tip for `navigation.standard.pinned-apps`:

```bash
osascript -e 'id of app "App"'
```

Notes:

- Set `cycle-timeout-ms = 0` to keep immediate cycling sessions active until you release the shortcut modifiers.
- Flow lock example: `cmd-right` then `up/down` in the same hold stays in immediate navigation flow (no mid-session switch to browse flow).
- Window-number pill tracks all standard windows for the selected app, including off-screen or Stage Manager-placed windows.
- If the exact selected window slot cannot be resolved, the HUD falls back to highlighting window `1`.
- Set `include-minimized = false` to ignore minimized windows during cycling.
- Set `include-hidden-apps = false` to ignore apps hidden via `Cmd+H`.
- Migration: `navigation.policy` and `[navigation.fixed-app-ring]` are no longer supported. Use `navigation.mode` and `[navigation.standard]`.
- Restart WindNav after editing `config.toml` (live reload is currently disabled).
- `launch-on-login` is most reliable when running the bundled app (`dist/WindNav.app`).

## Troubleshooting

- **Shortcuts do nothing**: Re-check macOS Accessibility permission for WindNav.
- **Config changes not applied**: Quit and relaunch WindNav.
- **Launch-on-login not sticking**: Run WindNav from the app bundle, not only with `swift run`.

## Development Run (Optional)

```bash
cd /path/to/WindNav
swift run WindNav
```
