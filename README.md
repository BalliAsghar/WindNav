<p align="center">
    <img src="Packaging/AppIcon.svg" alt="Icon" width="256" height="256">
</p>

# WindNav

WindNav is a macOS keyboard navigation tool for fast app and window switching without rearranging your workspace.

## Install

1. Download the latest `WindNav-vX.Y.Z.zip` from [Releases](https://github.com/balli/WindNav/releases).
2. Unzip the archive.
3. Move `WindNav.app` to `/Applications`.
4. Launch `WindNav.app`.

If macOS blocks the app because it is not notarized yet, run:

```bash
xattr -cr /Applications/WindNav.app
```

## Features

- Fast directional app switching with `left` / `right`.
- Window selection with `up` / `down` in both immediate and browse flows.
- Flow lock per modifier hold for predictable behavior.

## How It Works (Quick Guide)

1. Hold your modifier key (default: `Command`).
2. The first arrow you press locks the flow for this hold.
3. `left` / `right` first => immediate navigation flow.
4. `up` / `down` first => browse flow (deferred focus).
5. In browse flow, `left` / `right` selects app; `up` / `down` selects window.
6. Release the modifier to commit only in browse flow.

## Default Shortcuts

- `cmd-left`: previous app (immediate)
- `cmd-right`: next app (immediate)
- `cmd-up`: open browse HUD / next window in selected browse app
- `cmd-down`: open browse HUD / previous window in selected browse app

## Usage

1. Launch `WindNav.app`.
2. Grant Accessibility permission when macOS prompts you.
3. If the prompt does not appear, open `System Settings > Privacy & Security > Accessibility` and enable `WindNav`.
4. Use the default shortcuts to switch apps and windows.

WindNav needs Accessibility permission because macOS restricts apps from observing global keyboard shortcuts, reading the active UI state, and focusing other app windows unless the user explicitly allows it. Without that permission, WindNav cannot detect your hotkeys or move focus between apps and windows.

## Config

Config file location:

```text
~/.config/windnav/config.toml
```

WindNav creates this file automatically on first launch.

Opinionated Example:

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
pinned-apps = ["com.openai.codex", "dev.zed.Zed", "com.mitchellh.ghostty"]
unpinned-apps = "append"
in-app-window = "last-focused"
grouping = "one-stop-per-app"

[startup]
launch-on-login = true

[logging]
level = "info"
color = "auto"

[hud]
enabled = true
show-icons = true
position = "middle-center"
```

## Tips

- Set `cycle-timeout-ms = 0` to keep immediate cycling sessions active until you release the shortcut modifiers.
- The window-number pill counts all standard windows for the selected app, including off-screen / Stage Manager windows.
- If the exact selected window slot cannot be resolved, the HUD falls back to highlighting window `1`.
- Bundle ID tip for `navigation.standard.pinned-apps`:
  `osascript -e 'id of app "App"'`
- Restart WindNav after editing `config.toml`.

## Troubleshooting

- **Shortcuts do nothing**: Re-check macOS Accessibility permission for WindNav.
- **Config changes not applied**: Quit and relaunch WindNav.

## Development Run

```bash
cd /path/to/WindNav
swift run WindNav
```
