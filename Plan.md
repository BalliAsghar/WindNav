# Tab++ Detailed Implementation Plan

## 1. Purpose

Build a production-ready macOS app switcher that combines:

- Alt-Tab-level window management and Cmd+Tab interception reliability.
- WindNav-level low idle resource usage and directional keyboard flow.

This plan translates [guide.md](./guide.md) into an execution roadmap with concrete phases, reuse targets, quality gates, and acceptance criteria.

---

## 2. Product Goals and Success Criteria

## 2.1 Functional Goals

- Replace native `Cmd+Tab` with Tab++ switching flow.
- Support two modes:
1. Traditional switcher (Cmd+Tab style).
2. Directional flow (`h/j/k/l` and arrow keys) with modifier-based session behavior.
- Respect configurable visibility filters:
1. Minimized windows.
2. Hidden windows.
3. Fullscreen windows.
4. Apps without open windows.
- Support sorting modes:
1. Fixed order.
2. Most recent order.
3. Pinned apps.
- Provide TOML-based configuration in `~/.config/tabpp/config.toml`.

## 2.2 Performance Goals

- Idle memory target: <= 30 MB RSS on Apple Silicon (stretch target <= 20 MB).
- Idle CPU target: ~0% average (no periodic busy loops).
- Hotkey-to-HUD response target: <= 40 ms p95.
- Direction key-to-selection update: <= 16 ms p95.

## 2.3 UX Goals

- Default behavior works immediately after Accessibility permission grant.
- Keyboard-only operation for all main workflows.
- UI remains visually clean/minimal and avoids heavy preference windows.

---

## 3. Scope and Non-Goals

## 3.1 In Scope (v1)

- Cmd+Tab interception and restore safety.
- Window list modeling with visibility filters and ordering modes.
- Traditional switcher HUD.
- Directional browse flow HUD + commit on modifier release.
- TOML config loading, validation, defaults creation.
- Light/dark theme, icon size, spacing/padding.
- App exclusion list by app name and bundle id.
- Unit and integration tests for parsing, ordering, and navigation.

## 3.2 Out of Scope (v1)

- Full GUI settings suite with many tabs.
- Cloud sync of settings.
- Plugin system.
- OCR search across window content.

---

## 4. Technical Constraints

- macOS app, Swift, AppKit/SwiftUI hybrid UI.
- Accessibility permission required.
- Private SkyLight APIs required for symbolic hotkey override (Cmd+Tab).
- Must fail safe: always restore system Cmd+Tab on normal exit and recoverable crash/signal paths.

---

## 5. Architecture Overview

Adopt WindNav's lean runtime architecture and integrate Alt-Tab's robust window-state + system-switcher behavior.

## 5.1 Core Modules

1. `TabApp` (entrypoint and lifecycle)
- app launch, permissions, runtime wiring, graceful teardown.

2. `TabCore.Hotkeys`
- Carbon global hotkey registration.
- private API symbolic hotkey override.
- modifier monitoring and session state.

3. `TabCore.Windows`
- current system snapshot acquisition.
- window filtering (hidden/minimized/fullscreen/windowless).
- ordering (recent/fixed/pinned).
- frontmost/focus transitions.

4. `TabCore.Navigation`
- traditional cycle logic.
- directional browse flow logic.
- in-app window traversal.

5. `TabCore.Config`
- default config rendering.
- create/load/parse/validate TOML.
- migration and unknown-key handling.

6. `TabCore.UI`
- lightweight HUD rendering.
- list/grid model binding.
- theme + spacing + icon-size options.

7. `TabCore.Diagnostics`
- structured logging.
- lightweight timing metrics for performance checks.

---

## 6. Source Reuse Plan (Concrete)

Use code harvesting plus refactoring, not direct copy-paste of unrelated UI/dependency layers.

| Feature | Primary Source | Candidate Files | Tab++ Target |
| --- | --- | --- | --- |
| SkyLight bindings and symbolic hotkey IDs | Alt-Tab | `src/api-wrappers/private-apis/SkyLight.framework.swift` | `Sources/TabCore/Hotkeys/SkyLight.swift` |
| Cmd+Tab disable/restore guard | WindNav + Alt-Tab | `Sources/WindNavCore/Hotkeys/SystemHotkeyOverride.swift` | `Sources/TabCore/Hotkeys/SystemHotkeyOverride.swift` |
| Emergency restore on termination/signals | WindNav | `Sources/WindNavApp/main.swift` | `Sources/TabApp/main.swift` |
| Carbon global hotkeys | WindNav + Alt-Tab | `Sources/WindNavCore/Hotkeys/CarbonHotkeyRegistrar.swift`, `src/logic/events/KeyboardEvents.swift` | `Sources/TabCore/Hotkeys/CarbonRegistrar.swift` |
| Hotkey parsing from config | WindNav | `Sources/WindNavCore/Hotkeys/HotkeyParser.swift` | `Sources/TabCore/Hotkeys/HotkeyParser.swift` |
| Window snapshots via AX + filtering | WindNav | `Sources/WindNavCore/Accessibility/AXWindowProvider.swift` | `Sources/TabCore/Windows/AXWindowProvider.swift` |
| Window state model and focus behavior | Alt-Tab | `src/logic/Window.swift`, `src/logic/Windows.swift` | `Sources/TabCore/Windows/WindowModel.swift` |
| Most-recent ordering and focus-order updates | Alt-Tab | `src/logic/Windows.swift` (`sort`, `updateLastFocusOrder`) | `Sources/TabCore/Windows/WindowOrdering.swift` |
| Fixed/pinned app-ring ordering | WindNav | `Sources/WindNavCore/State/AppRingStateStore.swift` | `Sources/TabCore/Navigation/AppRingStateStore.swift` |
| Directional flow engine | WindNav | `Sources/WindNavCore/BrowseFlowController.swift`, `NavigationCoordinator.swift` | `Sources/TabCore/Navigation/BrowseFlowController.swift` |
| Lightweight HUD base | WindNav | `Sources/WindNavCore/UI/CycleHUDController.swift` | `Sources/TabCore/UI/SwitcherHUD.swift` |
| TOML load/create/validation | WindNav | `Sources/WindNavCore/Config/ConfigLoader.swift`, `ConfigModels.swift` | `Sources/TabCore/Config/*` |
| Config test patterns | WindNav | `Tests/WindNavCoreTests/ConfigTests.swift` | `Tests/TabCoreTests/ConfigTests.swift` |

Rules for reuse:

- Keep algorithms and interoperability techniques.
- Remove unrelated dependencies and app-specific preferences.
- Preserve attribution comments for private API signatures and known OS quirks.

---

## 7. Proposed Repository Layout

```text
Tab++/
  guide.md
  Plan.md
  Package.swift
  Sources/
    TabApp/
      main.swift
      AppDelegate.swift
    TabCore/
      Runtime/
        TabRuntime.swift
      Hotkeys/
        SkyLight.swift
        SystemHotkeyOverride.swift
        HotkeyParser.swift
        CarbonRegistrar.swift
        ModifierMonitor.swift
      Config/
        ConfigModels.swift
        ConfigDefaults.swift
        ConfigLoader.swift
        ConfigValidation.swift
      Windows/
        AXWindowProvider.swift
        WindowSnapshot.swift
        WindowFilter.swift
        WindowOrdering.swift
        FocusTracker.swift
      Navigation/
        NavigationCoordinator.swift
        BrowseFlowController.swift
        AppRingStateStore.swift
      UI/
        SwitcherHUDController.swift
        SwitcherHUDView.swift
        Theme.swift
      Diagnostics/
        Logger.swift
        Metrics.swift
  Tests/
    TabCoreTests/
      ConfigTests.swift
      HotkeyParserTests.swift
      WindowOrderingTests.swift
      NavigationCoordinatorTests.swift
      BrowseFlowControllerTests.swift
```

---

## 8. Configuration Specification (v1)

## 8.1 File Location and Bootstrapping

- Path: `~/.config/tabpp/config.toml`
- On startup:
1. Ensure `~/.config/tabpp/` exists.
2. If `config.toml` missing, write default TOML.
3. Parse and validate.
4. If invalid, fail with a clear error and log exact key/value issue.

## 8.2 Default TOML Draft

```toml
[activation]
trigger = "cmd-tab"
reverse-trigger = "cmd-shift-tab"
override-system-cmd-tab = true

[directional]
enabled = true
left = "opt-cmd-left"
right = "opt-cmd-right"
up = "opt-cmd-up"
down = "opt-cmd-down"
vim-left = "opt-cmd-h"
vim-down = "opt-cmd-j"
vim-up = "opt-cmd-k"
vim-right = "opt-cmd-l"
commit-on-modifier-release = true

[visibility]
show-minimized = true
show-hidden = true
show-fullscreen = true
show-empty-apps = false

[ordering]
mode = "most-recent" # fixed | most-recent | pinned
fixed-apps = []
pinned-apps = []
unpinned-apps = "append" # append | ignore

[filters]
exclude-apps = ["Finder", "Spotify"]
exclude-bundle-ids = []

[appearance]
theme = "system" # light | dark | system
icon-size = 22
item-padding = 8
item-spacing = 8
show-window-count = true

[performance]
idle-cache-refresh = "event-driven" # event-driven | interval
log-level = "info"
```

## 8.3 Validation Rules

- hotkey strings must parse to known key+modifier combinations.
- `ordering.mode` must be one of allowed enums.
- `icon-size` range: `14...64`.
- `item-padding` and `item-spacing` range: `0...24`.
- `exclude-*` arrays deduplicated.
- unknown keys are ignored with warning logs (not fatal).

---

## 9. Phase-by-Phase Delivery Plan

## Phase 0: Bootstrap and Skeleton (Day 1-2)

Tasks:

1. Initialize Swift package/app structure.
2. Add `TabRuntime` lifecycle.
3. Add logging and basic diagnostics.
4. Add CI script for build + tests.

Exit Criteria:

- App launches as accessory app.
- Builds cleanly in debug.
- Basic test target runs.

## Phase 1: Config Engine and Defaults (Day 2-3)

Tasks:

1. Port and adapt TOML loader/default writer.
2. Implement config models for all guide-required settings.
3. Add validation and error surfacing.
4. Add unit tests for valid/invalid configs and bootstrapping.

Exit Criteria:

- `~/.config/tabpp/config.toml` auto-created.
- Invalid config produces precise key-specific errors.
- Config tests pass.

## Phase 2: Hotkey Infrastructure + Cmd+Tab Override (Day 3-5)

Tasks:

1. Implement Carbon global hotkey registration.
2. Integrate SkyLight symbolic hotkey override.
3. Add modifier monitoring for session end behavior.
4. Add fail-safe restore handlers on terminate/signals/exceptions.

Exit Criteria:

- App can disable native Cmd+Tab and restore reliably.
- Hotkeys trigger runtime callbacks with no duplicate firing.
- Safety tests/manual checks pass for quit and relaunch.

## Phase 3: Window Snapshot + Filtering Layer (Day 5-7)

Tasks:

1. Implement AX-based snapshot collection.
2. Add visibility policies for minimized/hidden/fullscreen/windowless.
3. Add exclusion list handling by app name and bundle id.
4. Add focus tracker and last-focus ordering store.

Exit Criteria:

- Snapshot reflects active apps/windows accurately.
- Filter toggles in config take effect after restart.
- Ordering data updates on focus changes.

## Phase 4: Traditional Switcher Mode (Week 2)

Tasks:

1. Build selection model for Cmd+Tab forward/backward cycling.
2. Implement most-recent ordering path using focus order.
3. Implement fixed and pinned ordering path via app ring.
4. Add focus commit and edge-case handling (window closed, app terminated).

Exit Criteria:

- Cmd+Tab cycles reliably through filtered candidates.
- Reverse cycling works.
- Focus commit reaches target window/app with p95 <= 40 ms.

## Phase 5: Directional Flow Mode (Week 2)

Tasks:

1. Port/adapt browse flow session behavior.
2. Add left/right app traversal and up/down window traversal.
3. Support both arrow and vim directional keys.
4. Commit selection on modifier release.

Exit Criteria:

- Directional sessions start/continue/commit predictably.
- No stuck HUD/session after app termination mid-session.
- Directional flow tests pass.

## Phase 6: HUD/UI Implementation and Appearance Controls (Week 3)

Tasks:

1. Implement lightweight HUD view/controller.
2. Bind theme, icon size, spacing, and padding from config.
3. Show current app/window cues and optional window counts.
4. Ensure stable rendering across monitors/scales.

Exit Criteria:

- HUD visual behavior mirrors mode semantics.
- Appearance settings are reflected correctly.
- No major frame drops during rapid cycling.

## Phase 7: Performance Hardening (Week 3)

Tasks:

1. Remove polling where events suffice.
2. Minimize allocations on hot paths.
3. Profile memory and CPU idle costs.
4. Add lightweight metrics logs for activation latency.

Exit Criteria:

- Idle memory <= 30 MB.
- Idle CPU effectively 0%.
- No regressions in hotkey responsiveness.

## Phase 8: QA, Packaging, and Release Candidate (Week 4)

Tasks:

1. Build integration test checklist and manual regression suite.
2. Validate behavior on multiple macOS versions (target matrix below).
3. Package signed app build.
4. Publish release notes and known limitations.

Exit Criteria:

- All P0/P1 bugs resolved.
- Config, hotkeys, switcher, directional flow, and safety restore all verified.

---

## 10. Test Strategy

## 10.1 Unit Tests

- `ConfigTests`: parsing, defaults, invalid values, unknown keys.
- `HotkeyParserTests`: supported key tokens/modifiers/error messages.
- `WindowOrderingTests`: most-recent/fixed/pinned logic.
- `NavigationCoordinatorTests`: no-focus/focused transitions.
- `BrowseFlowControllerTests`: session lifecycle and commit semantics.

## 10.2 Integration and Manual Tests

1. Permissions:
- first launch Accessibility flow.

2. System override safety:
- launch -> disable Cmd+Tab.
- normal quit -> restore.
- crash/signal paths -> restore.

3. Switching:
- Cmd+Tab forward/back.
- filtered windows behavior.
- pinned/fixed ordering.

4. Directional:
- arrow and vim keys.
- browse selection and commit on release.
- mid-session app termination.

5. Visual:
- light/dark/system.
- icon size and spacing settings.
- multi-monitor positioning.

## 10.3 macOS Matrix

- Primary: latest stable macOS.
- Secondary: previous major macOS.
- Architecture: Apple Silicon required, Intel if available.

---

## 11. Performance and Reliability Gates

Before v1 release candidate, all must pass:

1. Idle RSS <= 30 MB after 10 minutes idle.
2. Idle CPU near 0% (Activity Monitor baseline check).
3. 100 rapid trigger cycles without crash/hang.
4. 100 launch/quit cycles with no leftover Cmd+Tab override state.
5. No stale HUD after forced app closure of selected target.

---

## 12. Risk Register and Mitigations

1. Private API fragility across macOS updates.
- Mitigation: isolate SkyLight calls behind one module; add feature flag fallback to custom trigger only.

2. Cmd+Tab remains disabled after abnormal termination.
- Mitigation: restore in app delegate terminate + signal handlers + uncaught exception handler.

3. AX API inconsistency (missing titles/windows).
- Mitigation: fallback labels, robust nil handling, retries only where justified.

4. Performance regressions from UI effects.
- Mitigation: keep HUD rendering minimal; avoid heavy animations and repeated image transformations.

5. Config schema drift over time.
- Mitigation: strict models, migration helpers, warnings for unknown/legacy keys.

---

## 13. Delivery Milestones

1. Milestone A: Skeleton + config + hotkeys override safety.
2. Milestone B: Traditional switcher fully operational.
3. Milestone C: Directional flow + HUD complete.
4. Milestone D: Performance tuned and test-hardened RC.

---

## 14. Immediate Next Implementation Steps

1. Create package/app scaffold and base module layout.
2. Implement `Config` and `Hotkeys` modules first (dependency foundation).
3. Add `Window` snapshot/filter model and ordering.
4. Wire runtime loop and add minimal HUD for end-to-end smoke flow.

