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

| Action            | Shortcut            |
| ----------------- | ------------------- |
| Open app switcher | `Cmd + Tab`         |
| Navigate left     | `Cmd + Opt + Left`  |
| Navigate right    | `Cmd + Opt + Right` |
| Navigate up       | `Cmd + Opt + Up`    |
| Navigate down     | `Cmd + Opt + Down`  |

> All keyboard shortcuts are fully customizable in the configuration file.

## Why WindNav?

The default macOS app switcher is limited. WindNav gives you:

- See all windows, not just apps
- Navigate directionally with arrow keys
- Pin your favorite apps to the front
- Exclude apps you never want to see
- Complete control over appearance and behavior

## System Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permissions (for app switching and keyboard navigation)

## Configuration

WindNav is configured via a TOML file located at:

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
icon-size = 22
item-padding = 8
item-spacing = 8
show-window-count = true

[onboarding]
permission-explainer-shown = false
launch-at-login-enabled = true
```

### Configuration Sections

| Section       | Description                             |
| ------------- | --------------------------------------- |
| `activation`  | Keyboard shortcuts to open the switcher |
| `directional` | Navigation controls and behavior        |
| `visibility`  | Which windows to show/hide              |
| `ordering`    | App ordering and pinned apps            |
| `filters`     | Apps to exclude from the switcher       |
| `appearance`  | Visual customization options            |
| `onboarding`  | First-run and startup settings          |
