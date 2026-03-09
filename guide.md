# WindNav Guide

## Project At A Glance
- WindNav is a macOS window switcher with two interaction modes:
  - activation cycle: Cmd+Tab-style linear cycling
  - directional navigation/browse: left/right/up/down movement between windows/apps
- Source of truth: code is authoritative. `README.md` may lag behind the implemented HUD/config behavior. When behavior changes, update both code and docs.
- Package manifest: `Package.swift`
  - package name: `TabPlusPlus`
  - minimum platform: macOS 15
  - products:
    - executable: `TabApp`
    - library: `TabCore`
  - test targets:
    - `TabCoreTests`
    - `TabAppTests`
- Main source roots:
  - `Sources/TabApp`: app bootstrap and menu bar shell
  - `Sources/TabCore`: runtime, config, hotkeys, windows, navigation, HUD
  - `Tests/TabCoreTests`, `Tests/TabAppTests`: coverage

## Runtime Flow
1. `Sources/TabApp/main.swift`
   - starts the app as an accessory app
   - creates `TabRuntime`
   - creates `FileSettingsStateStore`
   - creates `MenuBarSettingsController`
   - installs emergency cleanup to restore system Cmd+Tab on exit/crash paths
2. `Sources/TabCore/Runtime/TabRuntime.swift`
   - loads config through `ConfigLoader`
   - builds the core graph:
     - `CarbonHotkeyRegistrar`
     - `CatalogWindowProvider(source: AXWindowProvider())`
     - `AXFocusPerformer`
     - `MinimalHUDController`
     - `PermissionService`
   - parses bindings with `HotkeyParser`
   - registers hotkeys and refreshes permission-dependent capabilities
3. Hotkey handling
   - `CarbonHotkeyRegistrar` receives Carbon hotkey events
   - `TabRuntime.handleHotkeyAction(...)` routes to:
     - `NavigationCoordinator.startOrAdvanceCycle(...)`
     - `DirectionalCoordinator.handleHotkey(...)`
4. Snapshot acquisition
   - `AXWindowProvider.currentSnapshot()` fetches raw AX/CG window state
   - `CatalogWindowProvider.currentSnapshot()` passes raw snapshots through `WindowCatalog`
5. HUD presentation
   - coordinators build `HUDModel` via `HUDModelFactory`
   - `MinimalHUDController.show(...)` chooses:
     - thumbnail HUD when `hud.thumbnails = true`
     - icon-only HUD when `hud.thumbnails = false`
6. Commit/cancel
   - modifier release is watched by runtime event taps
   - cycle commit goes through `NavigationCoordinator.commitCycleOnModifierRelease(...)`
   - browse commit goes through `DirectionalCoordinator.commitOrEndSessionOnModifierRelease(...)`
   - focus is applied by `AXFocusPerformer`

## Feature Map

### App Bootstrap And Menu Bar Shell
- What it does:
  - starts the runtime
  - exposes config/permission/feature toggles in the menu bar UI
- Primary code:
  - `Sources/TabApp/main.swift`
  - `Sources/TabApp/MenuBarSettingsController.swift`
  - `Sources/TabApp/MenuBarViewModel.swift`
  - `Sources/TabApp/MenuBarPanelView.swift`
- Main types/functions:
  - `TabAppDelegate`
  - `MenuBarSettingsController`
  - `MenuBarViewModel`
- Tests:
  - `Tests/TabAppTests/MenuBarViewModelTests.swift`

### Hotkey Registration And System Cmd+Tab Override
- What it does:
  - parses user-configured hotkeys
  - registers Carbon hotkeys
  - disables/restores the system Cmd+Tab switcher when advanced input is enabled
- Primary code:
  - `Sources/TabCore/Hotkeys/HotkeyParser.swift`
  - `Sources/TabCore/Hotkeys/CarbonRegistrar.swift`
  - `Sources/TabCore/Hotkeys/HotkeyAction.swift`
  - `Sources/TabCore/Hotkeys/SystemHotkeyOverride.swift`
  - `Sources/TabCore/Runtime/TabRuntime.swift`
- Main types/functions:
  - `HotkeyParser.parse(_:)`
  - `CarbonHotkeyRegistrar.register(bindings:handler:)`
  - `SystemHotkeyOverride.disableSystemCmdTab()`
  - `SystemHotkeyOverride.restoreSystemCmdTab()`
- Tests:
  - `Tests/TabCoreTests/HotkeyParserCoreTests.swift`
  - `Tests/TabCoreTests/SystemHotkeyOverrideCoreTests.swift`
  - `Tests/TabCoreTests/RuntimeCoreTests.swift`

### Config Loading, Defaults, Serialization, Validation
- What it does:
  - owns the TOML surface
  - creates defaults at first launch
  - validates removed keys and current enums
- Primary code:
  - `Sources/TabCore/Config/ConfigModels.swift`
  - `Sources/TabCore/Config/ConfigLoader.swift`
  - `Sources/TabCore/Config/ConfigDefaults.swift`
  - `Sources/TabCore/Runtime/SettingsStateStore.swift`
- Main types/functions:
  - `TabConfig`
  - `HUDConfig`
  - `HUDThumbnailSizePreset`
  - `ConfigLoader.loadOrCreate()`
  - `ConfigLoader.save(_:)`
  - `TabDefaultsCatalog`
  - `FileSettingsStateStore`
- Tests:
  - `Tests/TabCoreTests/ConfigCoreTests.swift`
  - `Tests/TabCoreTests/SettingsStoreCoreTests.swift`

### Permission Handling
- What it does:
  - checks/request accessibility
  - checks/request screen recording
  - opens the correct System Settings pane
- Primary code:
  - `Sources/TabCore/Runtime/PermissionService.swift`
  - `Sources/TabCore/Runtime/TabRuntime.swift`
  - `Sources/TabApp/MenuBarViewModel.swift`
- Main types/functions:
  - `PermissionService.status(for:)`
  - `PermissionService.request(_:)`
  - `PermissionService.openSystemSettings(for:)`
  - `TabRuntime.refreshPermissionDependentCapabilities(config:)`
- Tests:
  - `Tests/TabCoreTests/PermissionServiceCoreTests.swift`
  - `Tests/TabCoreTests/RuntimeCoreTests.swift`
  - `Tests/TabAppTests/MenuBarViewModelTests.swift`

### Window Snapshot Sourcing And Catalog Revision Tracking
- What it does:
  - collects raw window/app state
  - synthesizes fallback entries for empty apps when configured
  - attaches tracking metadata such as capture eligibility and revision
- Primary code:
  - `Sources/TabCore/Windows/AXWindowProvider.swift`
  - `Sources/TabCore/Windows/CatalogWindowProvider.swift`
  - `Sources/TabCore/Windows/WindowCatalog.swift`
  - `Sources/TabCore/Windows/WindowSnapshot.swift`
  - `Sources/TabCore/Windows/CGWindowPresence.swift`
  - `Sources/TabCore/Windows/SyntheticWindowID.swift`
- Main types/functions:
  - `AXWindowProvider.currentSnapshot()`
  - `CatalogWindowProvider.currentSnapshot()`
  - `WindowCatalog.reconcile(rawSnapshots:)`
  - `WindowCatalogMonitor`
  - `WindowSnapshot.withTrackingMetadata(...)`
- Tests:
  - mostly covered indirectly by navigation/runtime tests:
    - `Tests/TabCoreTests/NavigationCoordinatorCoreTests.swift`
    - `Tests/TabCoreTests/DirectionalCoordinatorCoreTests.swift`
    - `Tests/TabCoreTests/RuntimeCoreTests.swift`

### Activation-Cycle Navigation
- What it does:
  - builds a linear session ordered by recent focus/history
  - advances selection left/right
  - commits focus on modifier release
  - supports quit-selected-app and close-selected-window
- Primary code:
  - `Sources/TabCore/Navigation/NavigationCoordinator.swift`
  - `Sources/TabCore/Navigation/WindowSnapshotSupport.swift`
  - `Sources/TabCore/Navigation/AXWindowClosePerformer.swift`
  - `Sources/TabCore/Navigation/NSRunningAppTerminationPerformer.swift`
- Main types/functions:
  - `NavigationCoordinator.startOrAdvanceCycle(...)`
  - `NavigationCoordinator.commitCycleOnModifierRelease(...)`
  - `NavigationCoordinator.requestQuitSelectedAppInCycle()`
  - `NavigationCoordinator.requestCloseSelectedWindowInCycle()`
- Tests:
  - `Tests/TabCoreTests/NavigationCoordinatorCoreTests.swift`

### Directional Navigation And Browse
- What it does:
  - handles left/right directional navigation
  - handles up/down browse mode
  - keeps app ring ordering and focus memory
  - optionally commits on modifier release
- Primary code:
  - `Sources/TabCore/Navigation/DirectionalCoordinator.swift`
  - `Sources/TabCore/Navigation/Direction.swift`
  - `Sources/TabCore/Navigation/WindowSnapshotSupport.swift`
- Main types/functions:
  - `DirectionalCoordinator.handleHotkey(direction:hotkeyTimestamp:)`
  - `DirectionalCoordinator.commitOrEndSessionOnModifierRelease(...)`
  - internal `AppRingStateStore`
  - internal `AppFocusMemoryStore`
- Tests:
  - `Tests/TabCoreTests/DirectionalCoordinatorCoreTests.swift`

### HUD Model Building And Metadata Normalization
- What it does:
  - converts ordered `WindowSnapshot` arrays into UI-ready HUD items
  - normalizes window title vs app name
  - assigns repeated-window badges
  - picks the initial thumbnail state
- Primary code:
  - `Sources/TabCore/UI/HUDModels.swift`
  - `Sources/TabCore/UI/HUDModelFactory.swift`
  - `Sources/TabCore/UI/HUDMetadataFormatter.swift`
- Main types/functions:
  - `HUDModel`
  - `HUDItem`
  - `HUDPresentationMode`
  - `HUDModelFactory.makeModel(...)`
  - `HUDMetadataFormatter.lines(for:)`
- Tests:
  - `Tests/TabCoreTests/HUDMetadataCoreTests.swift`
  - `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`
  - `Tests/TabCoreTests/HUDThumbnailToggleCoreTests.swift`

### Thumbnail-On HUD Layout And Rendering
- What it does:
  - renders the thumbnail grid HUD
  - applies size presets
  - keeps metadata rows aligned
  - renders selection, lift animation, and repeated-window badges
- Primary code:
  - `Sources/TabCore/UI/MinimalHUDController.swift`
- Main implementation areas:
  - `HUDGridMetrics`
  - `HUDThumbnailMetricsPreset`
  - thumbnail tile view/layout code
  - panel size policy
- Tests:
  - `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`
  - `Tests/TabCoreTests/HUDMetadataCoreTests.swift`

### Thumbnail-Off Icon-Only HUD Layout And Rendering
- What it does:
  - renders a native-like single-row icon strip
  - shows only the selected label
  - preserves repeated-window badges
  - horizontally reveals the selected item when needed
- Primary code:
  - `Sources/TabCore/UI/MinimalHUDController.swift`
  - `Sources/TabCore/UI/HUDIconProvider.swift`
- Main implementation areas:
  - `HUDIconStripMetrics`
  - icon-only tile path
  - horizontal reveal logic
  - icon-only badge positioning
- Tests:
  - `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`
  - `Tests/TabCoreTests/HUDIconProviderCoreTests.swift`

### ScreenCaptureKit Thumbnail Pipeline, Cache, And Live Selected-Window Stream
- What it does:
  - captures still thumbnails with ScreenCaptureKit
  - runs exactly one live stream for the selected window
  - caches thumbnail surfaces with bounded memory
  - preserves aspect ratio and avoids flicker on selection churn
- Primary code:
  - `Sources/TabCore/UI/ThumbnailPipeline.swift`
  - `Sources/TabCore/UI/MinimalHUDController.swift`
- Main types/functions:
  - `CaptureScheduler`
  - `ThumbnailCache`
  - `ThumbnailSurface`
  - `ThumbnailSizing`
  - `ScreenCaptureKitThumbnailProvider`
  - `ThumbnailState`
- Tests:
  - `Tests/TabCoreTests/ThumbnailPipelineCoreTests.swift`
  - `Tests/TabCoreTests/HUDThumbnailToggleCoreTests.swift`
  - `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`

### Menu Bar Feature Toggles And Settings Persistence
- What it does:
  - lets the user enable/disable directional navigation
  - lets the user enable/disable window thumbnails
  - persists config and reapplies runtime behavior immediately
- Primary code:
  - `Sources/TabApp/MenuBarViewModel.swift`
  - `Sources/TabApp/MenuBarPanelView.swift`
  - `Sources/TabCore/Runtime/SettingsStateStore.swift`
  - `Sources/TabCore/Runtime/TabRuntime.swift`
- Main types/functions:
  - `MenuBarViewModel.FeatureToggle`
  - `MenuBarViewModel.updateFeature(_:enabled:)`
  - `FileSettingsStateStore.save(_:)`
  - `TabRuntime.applyConfig(_:)`
- Tests:
  - `Tests/TabAppTests/MenuBarViewModelTests.swift`
  - `Tests/TabCoreTests/HUDThumbnailToggleCoreTests.swift`

## Config Surface
- Current root sections are owned by `Sources/TabCore/Config/ConfigModels.swift` and parsed/serialized by `Sources/TabCore/Config/ConfigLoader.swift`.
- Current user-facing sections:
  - `[activation]`
    - `trigger`
  - `[directional]`
    - `enabled`
    - `left`
    - `right`
    - `up`
    - `down`
    - `browse-left-right-mode`
    - `commit-on-modifier-release`
  - `[hud]`
    - `thumbnails`
    - `size = "small" | "medium" | "large"`
  - `[onboarding]`
    - `permission-explainer-shown`
    - `launch-at-login-enabled`
  - `[visibility]`
    - `show-minimized`
    - `show-hidden`
    - `show-fullscreen`
    - `show-empty-apps`
  - `[ordering]`
    - `pinned-apps`
    - `unpinned-apps`
  - `[filters]`
    - `exclude-apps`
    - `exclude-bundle-ids`
  - `[appearance]`
    - `theme`
    - `show-window-count`
  - `[performance]`
    - log configuration
- Important config migration note:
  - `hud.size` replaced the old low-level appearance sizing knobs.
  - `appearance.icon-size`, `appearance.item-padding`, and `appearance.item-spacing` are intentionally removed and should stay invalid unless the config surface is redesigned again.

## UI/HUD Modes
- Rendering owner: `Sources/TabCore/UI/MinimalHUDController.swift`
- Mode selection:
  - `HUDPresentationMode(hud:)` in `Sources/TabCore/UI/HUDModels.swift`
  - `thumbnails = true` -> thumbnail grid mode
  - `thumbnails = false` -> icon-only native-style mode
- Thumbnail mode:
  - multi-row centered grid
  - size preset driven by `hud.size`
  - repeated-window badge support
  - metadata uses fixed two-line layout
  - selected window gets live thumbnail updates
- Icon-only mode:
  - single-row strip
  - larger rasterized app icons from `HUDIconProvider`
  - selected item label only
  - repeated-window badge support
  - ignores `hud.size`
- Selection behavior:
  - coordinators own selection order/index
  - HUD is purely a presentation layer over `HUDModel`
  - selected-tile lift animation is implemented in `MinimalHUDController`

## Window + Navigation Pipeline
- Raw source:
  - `AXWindowProvider` collects AX windows and supplements them with CG/NSWorkspace evidence
- Tracking layer:
  - `CatalogWindowProvider` sends snapshots through `WindowCatalog`
  - `WindowCatalog` adds:
    - `revision`
    - `isOnCurrentSpace`
    - `isOnCurrentDisplay`
    - `canCaptureThumbnail`
- Navigation flows:
  - activation cycle:
    - `TabRuntime.handleHotkeyAction(...)`
    - `NavigationCoordinator.startOrAdvanceCycle(...)`
  - directional:
    - `TabRuntime.handleHotkeyAction(...)`
    - `DirectionalCoordinator.handleHotkey(direction:hotkeyTimestamp:)`
- HUD model:
  - `HUDModelFactory.makeModel(...)`
- HUD render:
  - `MinimalHUDController.show(model:appearance:hud:)`
- Commit:
  - `AXFocusPerformer.focus(windowId:pid:)`

## Where To Change Things
- Change config schema or TOML parsing:
  - `Sources/TabCore/Config/ConfigModels.swift`
  - `Sources/TabCore/Config/ConfigLoader.swift`
  - `Sources/TabCore/Config/ConfigDefaults.swift`
  - tests: `Tests/TabCoreTests/ConfigCoreTests.swift`
- Change hotkeys or input bindings:
  - `Sources/TabCore/Hotkeys/HotkeyParser.swift`
  - `Sources/TabCore/Hotkeys/HotkeyAction.swift`
  - `Sources/TabCore/Runtime/TabRuntime.swift`
  - tests: `Tests/TabCoreTests/HotkeyParserCoreTests.swift`, `Tests/TabCoreTests/RuntimeCoreTests.swift`
- Change system Cmd+Tab override behavior:
  - `Sources/TabCore/Hotkeys/SystemHotkeyOverride.swift`
  - tests: `Tests/TabCoreTests/SystemHotkeyOverrideCoreTests.swift`
- Change window sourcing/filtering/catalog behavior:
  - `Sources/TabCore/Windows/AXWindowProvider.swift`
  - `Sources/TabCore/Windows/CatalogWindowProvider.swift`
  - `Sources/TabCore/Windows/WindowCatalog.swift`
  - downstream tests: navigation/runtime tests
- Change activation-cycle ordering/commit behavior:
  - `Sources/TabCore/Navigation/NavigationCoordinator.swift`
  - `Sources/TabCore/Navigation/WindowSnapshotSupport.swift`
  - tests: `Tests/TabCoreTests/NavigationCoordinatorCoreTests.swift`
- Change directional behavior or app ring logic:
  - `Sources/TabCore/Navigation/DirectionalCoordinator.swift`
  - tests: `Tests/TabCoreTests/DirectionalCoordinatorCoreTests.swift`
- Change HUD metadata/title/subtitle behavior:
  - `Sources/TabCore/UI/HUDMetadataFormatter.swift`
  - `Sources/TabCore/UI/HUDModelFactory.swift`
  - `Sources/TabCore/UI/MinimalHUDController.swift`
  - tests: `Tests/TabCoreTests/HUDMetadataCoreTests.swift`
- Change thumbnail HUD layout, chrome, size presets, badges:
  - `Sources/TabCore/UI/MinimalHUDController.swift`
  - tests: `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`
- Change icon-only HUD layout or icon rendering:
  - `Sources/TabCore/UI/MinimalHUDController.swift`
  - `Sources/TabCore/UI/HUDIconProvider.swift`
  - tests: `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`, `Tests/TabCoreTests/HUDIconProviderCoreTests.swift`
- Change thumbnail capture, cache, live stream policy:
  - `Sources/TabCore/UI/ThumbnailPipeline.swift`
  - `Sources/TabCore/UI/MinimalHUDController.swift`
  - tests: `Tests/TabCoreTests/ThumbnailPipelineCoreTests.swift`
- Change menu bar toggles or permission prompts:
  - `Sources/TabApp/MenuBarViewModel.swift`
  - `Sources/TabApp/MenuBarPanelView.swift`
  - tests: `Tests/TabAppTests/MenuBarViewModelTests.swift`

## Test Map
- Config:
  - `Tests/TabCoreTests/ConfigCoreTests.swift`
  - `Tests/TabCoreTests/SettingsStoreCoreTests.swift`
- Runtime and permissions:
  - `Tests/TabCoreTests/RuntimeCoreTests.swift`
  - `Tests/TabCoreTests/PermissionServiceCoreTests.swift`
- Hotkeys/system override:
  - `Tests/TabCoreTests/HotkeyParserCoreTests.swift`
  - `Tests/TabCoreTests/SystemHotkeyOverrideCoreTests.swift`
- Activation cycle:
  - `Tests/TabCoreTests/NavigationCoordinatorCoreTests.swift`
- Directional:
  - `Tests/TabCoreTests/DirectionalCoordinatorCoreTests.swift`
- HUD layout and styling:
  - `Tests/TabCoreTests/HUDGridLayoutCoreTests.swift`
  - `Tests/TabCoreTests/HUDMetadataCoreTests.swift`
- Thumbnail pipeline and gating:
  - `Tests/TabCoreTests/ThumbnailPipelineCoreTests.swift`
  - `Tests/TabCoreTests/HUDThumbnailToggleCoreTests.swift`
- Icon provider:
  - `Tests/TabCoreTests/HUDIconProviderCoreTests.swift`
- Menu bar:
  - `Tests/TabAppTests/MenuBarViewModelTests.swift`
- Misc cleanup:
  - `Tests/TabCoreTests/InternalCleanupCoreTests.swift`

## Current Gotchas
- `README.md` is not fully current:
  - it still references older config/UI details
  - trust `ConfigModels.swift`, `ConfigLoader.swift`, and `MinimalHUDController.swift` first
- `hud.size` is thumbnail-only. Icon-only HUD ignores it by design.
- `hud.thumbnails = false` is not “thumbnail grid without images”; it is a separate icon-only HUD path.
- Screen Recording is only relevant when thumbnails are enabled. Accessibility still gates advanced input and system Cmd+Tab override behavior.
- The live thumbnail policy is intentionally narrow:
  - one live stream for the selected window
  - other windows use cached stills/opportunistic refresh
- Much of the window/capture correctness is validated through coordinator/HUD integration tests rather than isolated window-provider unit tests.
