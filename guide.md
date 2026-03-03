## Project Brief: Next-Generation macOS Window Switcher

This document outlines the requirements for developing a lightning-fast, highly resource-efficient macOS application designed to replace the default Command-Tab switcher. By combining the best elements of **Alt-Tab macOS** and **WindNav**, this new tool will deliver superior performance and intuitive navigation.

### Core Inspirations

- **Alt-Tab macOS:** A popular, highly customizable alternative to the built-in macOS switcher. While feature-rich and effective, it can be resource-intensive, consuming up to 200MB of real memory while sitting idle.
- **WindNav:** Our proprietary, lightweight custom window manager. It operates with a minimal footprint (around 15MB of idle memory) and introduces two distinct navigation methods:

1. A traditional Command-Tab style switcher.
2. A Directional Flow for moving between apps using directional keys (e.g., `h`, `j`, `k`, `l`, or arrows).

### The Objective

Develop a hybrid application that merges Alt-Tab's robust functionality with WindNav's ultra-low resource usage and streamlined aesthetics. The final product must offer both traditional switching and directional navigation without sacrificing system responsiveness or draining CPU/memory.

---

### Core Features

- **Customizable Activation Hotkey:** Users can set their preferred trigger (defaulting to `Command-Tab`).

  > **Note:** We will utilize the SkyLight Private API to intercept these keystrokes. We have previous experience with this from WindNav, though we will need to refine the implementation to remove previous quirks.

- **Refined User Interface:** The UI will adopt the clean, intuitive simplicity of WindNav's switcher, enhanced with subtle visual polish to make it highly appealing.
- **Directional Flow Navigation:** A fast, keyboard-centric way to navigate open windows using a modifier key combined with directional inputs (`h`, `j`, `k`, `l`, or arrow keys).
- **Extreme Efficiency:** The architecture must prioritize a minimal memory footprint and near-zero CPU usage while idle.

---

### Configuration Management

To keep the application lightweight and developer/power-user friendly, the application will adopt WindNav's configuration approach rather than relying on heavy GUI preference panes alone.

- **Configuration Format:** All user preferences will be stored in a `config.toml` file.
- **File Location:** The file will reside in the user's hidden config directory (e.g., `~/.config/<AppName>/config.toml`).
- **Initialization:** Upon application launch, the system must check for the existence of this file. If the `~/.config` directory or the `config.toml` file does not exist, the application will automatically create them and populate the file with the default configuration values.

---

### User Customization & Preferences (Configurable via TOML)

To ensure a personalized experience, the following settings must be adjustable within the `config.toml` file:

#### Visibility Settings

| Window State                  | Default Setting | TOML Key Example          |
| ----------------------------- | --------------- | ------------------------- |
| Show minimized windows        | True            | `show_minimized = true`   |
| Show hidden windows           | True            | `show_hidden = true`      |
| Show fullscreen windows       | True            | `show_fullscreen = true`  |
| Show apps with no open window | False           | `show_empty_apps = false` |

#### Sorting & Navigation

- **Window Order:** Users can choose how windows are organized. Options must include: _Fixed Order_, _Most Recent Order_, and _Pinned Apps_.
- **Directional Flow Hotkeys:** Users can map their own directional shortcuts. The default will be `Option + Command + Arrow Keys` (Up, Down, Left, Right).
- **App Exclusion List:** A built-in array/blocklist allowing users to hide specific applications from the switcher entirely (e.g., `exclude_apps = ["Finder", "Spotify"]`).

#### Appearance Tweaks

- **Theming:** Toggle between Light and Dark modes.
- **Layout Controls:** Adjustable icon sizes and customizable spacing/padding between application icons.

---

## Code Reusability Context (For `Plan.md`)

To accelerate development and ensure stability, we will systematically harvest and refactor specific components from our existing local repositories.

### 1. Alt-Tab macOS (`/Users/balli/code/alt-tab-macos`)

We will reference Alt-Tab for its battle-tested window management logic and API integrations, stripping away the heavy GUI overhead.

- **Feature:** SkyLight Private API Integration & Hotkey Interception
- _What we need:_ The stable implementation for overriding the native Command-Tab behavior. Since WindNav's implementation was "quirky," we will adopt Alt-Tab's more robust method for intercepting and handling modifier key events.

- **Feature:** "Most Recent" Window Ordering
- _What we need:_ The core logic that accurately tracks the z-order and focus history of macOS windows.

- **Feature:** Comprehensive Window State Detection
- _What we need:_ The helper functions used to accurately determine if a window is minimized, hidden, or fullscreen.

### 2. WindNav (`/Users/balli/code/WindNav`)

WindNav will serve as the architectural foundation for our UI, directional navigation, and lightweight configuration system.

- **Feature:** Lightweight Switcher UI Base
- _What we need:_ The core UI rendering code that gives WindNav its snappy, 15MB-footprint performance. We will use this as our visual base and apply enhancements on top of it.

- **Feature:** Directional Flow Logic
- _What we need:_ The algorithms handling spatial navigation (moving focus up, down, left, right using `h,j,k,l` or arrows).

- **Feature:** "Fixed Order" and "Pinned Apps" Logic
- _What we need:_ The existing data structures and sorting logic that handle fixed and pinned application states.

- **Feature:** TOML Configuration Engine
- _What we need:_ The parser and filesystem logic responsible for reading/writing `config.toml` to the `~/.config/` directory. This will be expanded to support the new variables.

#### Source-Code To use:

Alt-Tab macOS - /Users/balli/code/alt-tab-macos
WindNav - /Users/balli/code/WindNav
