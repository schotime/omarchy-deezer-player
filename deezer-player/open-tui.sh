#!/bin/bash
# Slide the bar's drop-down deezer-tui down (or back up), focus a deezer-tui
# launched by hand in any other terminal, otherwise open the drop-down.
# Usage: open-tui.sh [deezer-tui command]

binary="${1:-deezer-tui}"
name=$(basename "$binary")
clients=$(hyprctl clients -j)

# hide-tui.sh only slides the drop-down away after it has had focus since it
# last came down, so each toggle starts that over.
focused_flag="${XDG_RUNTIME_DIR:-/tmp}/deezer-tui-dropdown-focused"
rm -f "$focused_flag"

# The window rule only sizes and places the drop-down when it is first opened,
# and Hyprland centres it whenever it next opens on another monitor. So before
# dropping it in, put it top-right under the focused monitor's bar at a third of
# that monitor's size; with its middle already there, Hyprland leaves it alone.
place_dropdown() {
  local monitor mx my lw lh top w h
  monitor=$(hyprctl monitors -j | jq -c '.[] | select(.focused)')
  [[ $(jq -r '.specialWorkspace.name' <<<"$monitor") == special:deezer ]] && return

  read -r mx my lw lh top < <(jq -r '"\(.x) \(.y) \((.width / .scale) | floor) \((.height / .scale) | floor) \(.reserved[1])"' <<<"$monitor")
  w=$((lw / 3))
  h=$((lh / 3))

  # The 8px offsets match general:gaps_out.
  hyprctl dispatch "hl.dsp.window.resize({ x = $w, y = $h, window = \"address:$1\" })" >/dev/null
  hyprctl dispatch "hl.dsp.window.move({ x = $((mx + lw - w - 8)), y = $((my + top + 8)), window = \"address:$1\" })" >/dev/null
}

# Walk up from each deezer-tui process until a parent owns a window. A daemon
# left running after its TUI quit is reparented away from any terminal, so it
# never matches and a fresh TUI is launched instead.
for pid in $(pgrep -x "$name"); do
  p=$pid
  while [[ -n $p && $p -gt 1 ]]; do
    address=$(jq -r --argjson pid "$p" '.[] | select(.pid == $pid) | .address' <<<"$clients" | head -n1)
    if [[ -n $address ]]; then
      # The window rule in hypr/hyprland.lua keeps the bar's TUI on its own
      # special workspace, so toggling that is what slides it in and out.
      workspace=$(jq -r --arg address "$address" '.[] | select(.address == $address) | .workspace.name' <<<"$clients")
      if [[ $workspace == special:deezer ]]; then
        place_dropdown "$address"
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("deezer")' >/dev/null
      else
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null
      fi
      exit 0
    fi
    p=$(awk '/^PPid:/ { print $2 }' "/proc/$p/status" 2>/dev/null)
  done
done

exec env COLORTERM=truecolor omarchy-launch-tui --app-id=org.omarchy.deezer-tui "$binary"
