<p align="center">
    <img src="Packaging/AppIcon.svg" alt="Icon" width="256" height="256">
</p>

# WindNav

WindNav is a macOS keyboard navigation tool that helps you move between apps and windows without disturbing your layout.

## Why Use WindNav

- **Directional focus movement**
  - `left` / `right` moves between apps.
  - `up` / `down` cycles windows inside the current app.
- **Current-monitor awareness**
  - Navigation stays on the monitor you are actively using.
- **Predictable switching**
  - Optional app pinning gives you a stable app order.
- **Visual feedback**
  - Optional HUD shows where you are in the cycle.
- **Fully customizable shortcuts**
  - Pick any modifier + key combination you prefer.
- **Launch on login support**
  - Start WindNav automatically after sign in.

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

- `cmd-left`: previous app
- `cmd-right`: next app
- `cmd-up`: next window in current app
- `cmd-down`: previous window in current app

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
policy = "fixed-app-ring"
cycle-timeout-ms = 900

[navigation.fixed-app-ring]
pinned-apps = ["com.apple.Safari", "com.microsoft.VSCode"]
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

Notes:

- Set `cycle-timeout-ms = 0` to keep a cycling session active until you release the shortcut modifiers.
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
