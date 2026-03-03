import Foundation

extension TabConfig {
    static let defaultToml = """
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
    mode = "most-recent"
    fixed-apps = []
    pinned-apps = []
    unpinned-apps = "append"

    [filters]
    exclude-apps = ["Finder", "Spotify"]
    exclude-bundle-ids = []

    [appearance]
    theme = "system"
    icon-size = 22
    item-padding = 8
    item-spacing = 8
    show-window-count = true

    [performance]
    idle-cache-refresh = "event-driven"
    log-level = "info"
    """
}
