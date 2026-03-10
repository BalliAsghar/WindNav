<p align="center">
  <img src="Packaging/AppIcon.svg" alt="WindNav Logo" width="200"/>
</p>

# WindNav

**WindNav** is a powerful macOS utility that transforms how you switch between apps and windows. It provides a sleek, customizable overlay interface for navigating your workspace with keyboard-driven efficiency.

## Features

- **Fast App & Window Switching** - Navigate between apps and specific windows with customizable keyboard shortcuts
- **Directional Navigation** - Use arrow keys to move through your open apps and windows
- **Pinned Apps** - Keep your most-used apps always visible at the front
- **Smart Filtering** - Exclude specific apps and control which windows appear
- **Customizable Appearance** - Adjust theme, icon sizes, spacing, and layout
- **Launch at Login** - Start WindNav automatically when you log in

## Keyboard Controls

| Action              | Shortcut            |
| ------------------- | ------------------- |
| Open app switcher   | `Cmd + Tab`         |
| Navigate left       | `Cmd + Opt + Left`  |
| Navigate right      | `Cmd + Opt + Right` |
| Browse HUD forward  | `Cmd + Opt + Up`    |
| Browse HUD backward | `Cmd + Opt + Down`  |

> All keyboard shortcuts are fully customizable in the configuration file.
> `Cmd + Opt + Up/Down` opens the directional browse HUD, previews the current selection, and commits on modifier release when configured.

## Why WindNav?

The default macOS app switcher is limited. WindNav gives you:

- See all windows, not just apps
- Navigate directionally with arrow keys
- Pin your favorite apps to the front
- Exclude apps you never want to see
- Complete control over appearance and behavior

## System Requirements

- macOS 15.0 or later
- Accessibility permission for directional navigation and switching
- Screen Recording permission only when HUD thumbnails are enabled

## Downloading

- Open the [GitHub Releases page](https://github.com/BalliAsghar/WindNav/releases).
- Download the latest `WindNav.app` release artifact.
- Move `WindNav.app` to `/Applications` and launch it.

### Run locally

Build and run the app from source during development:

```bash
swift build
swift run TabApp
```

If you want a local `.app` bundle in `dist/`, package it with:

```bash
./scripts/package_app.sh
```

## Configuration

WindNav is configured via a TOML file located at:

**Note:** If the config file does not exist, WindNav will create one with default settings on first launch.

```
~/.config/windnav/config.toml
```

### Example Configuration

```toml
[activation]
trigger = "cmd-tab"

[directional]
enabled = true
left = "opt-cmd-left"
right = "opt-cmd-right"
up = "opt-cmd-up"
down = "opt-cmd-down"
browse-left-right-mode = "immediate"
commit-on-modifier-release = true

[hud]
thumbnails = true
size = "small" # Options: "small", "medium", "large"

[onboarding]
permission-explainer-shown = false
launch-at-login-enabled = false

[visibility]
show-minimized = true
show-hidden = true
show-fullscreen = true
show-empty-apps = "show-at-end"

[ordering]
pinned-apps = ["com.apple.Safari", "com.apple.Mail"]
unpinned-apps = "append"

[filters]
exclude-apps = ["Activity Monitor"]
exclude-bundle-ids = []

[appearance]
theme = "system"
show-window-count = true

[performance]
log-level = "info"
log-color = "auto"
```

### Configuration Sections

| Section       | Description                                  |
| ------------- | -------------------------------------------- |
| `activation`  | Keyboard shortcut used to open the switcher  |
| `directional` | Directional hotkeys and browse behavior      |
| `hud`         | HUD thumbnail visibility and size            |
| `onboarding`  | First-run and launch-at-login state          |
| `visibility`  | Which windows and windowless apps to include |
| `ordering`    | Pinned app ordering and unpinned handling    |
| `filters`     | Apps and bundle IDs to exclude               |
| `appearance`  | Theme mode and window-count badges           |
| `performance` | Logging verbosity and ANSI color mode        |
