# Omarchy frontend

`deezer-player` is a Quickshell/Omarchy bar widget for the `deezer-tui`
daemon. It intentionally uses Omarchy's `Color` and `Style` singletons rather
than fixed colours, fonts, or spacing, so every system theme is reflected
immediately in the player UI.

## Install for development

Build or install `deezer-tui`, then copy the plugin into your user-owned
Omarchy plugin folder:

```bash
cp -r omarchy/deezer-player ~/.config/omarchy/plugins/schotime.deezer-player
```

Add **Deezer Player** from the Omarchy bar widget picker. The shell reloads
plugin files automatically. The widget polls `deezer-tui --status --json`,
and sends transport commands through the existing CLI/daemon protocol.

## Controls

- Left click the bar icon: open the panel. Middle click: play / pause.
  Scroll up / down: previous / next. Right click: open the TUI.
- In the panel: click the progress bar to seek, `n` / `b` for next / previous,
  `o` to open the TUI.
- Transport controls drive the shell's active media player, falling back to
  the `deezer-tui` CLI when the media service is unavailable.

## Drop-down TUI

`open-tui.sh` opens `deezer-tui` as a drop-down under the bar and
`hide-tui.sh` slides it away once focus leaves it. Both need `hyprctl` and
`jq`, plus a window rule that keeps the TUI on its own special workspace, in
`~/.config/hypr/hyprland.lua`:

```lua
o.window("org\\.omarchy\\.deezer-tui", {
  float = true,
  size = { "(monitor_w/3)", "(monitor_h/3)" },
  -- Top-right, just under the 30px bar with the usual 8px outer gap.
  move = { "(monitor_w-monitor_w/3-8)", "(38)" },
  workspace = "special:deezer",
})
```

The same script can be bound to a key:

```lua
o.bind("SUPER + SHIFT + M", "Music", 'bash "$HOME/.config/omarchy/plugins/schotime.deezer-player/open-tui.sh" deezer-tui')
```

The first version is deliberately a compact native control surface. Search,
library, queue, and login views should be added through a stable JSON IPC
endpoint in the Rust binary rather than duplicating Deezer API logic in QML.
