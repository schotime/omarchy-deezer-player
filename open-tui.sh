#!/bin/bash
# Slide the bar's drop-down deezer-tui down (or back up), focus a deezer-tui
# launched by hand in any other terminal, otherwise open the drop-down.
# Usage: open-tui.sh [deezer-tui command] [corner] [edge]
# corner is top-left, top-right, bottom-left or bottom-right: the corner of the
# screen the bar icon sits in, so the drop-down comes out next to it. edge is
# the bar's edge (top, bottom, left or right), which it slides out of.

binary="${1:-deezer-tui}"
name=$(basename "$binary")
clients=$(hyprctl clients -j)

# The bar widget passes its corner and edge each time. A key binding doesn't,
# so work them out from the bar's edge and the layout section holding the
# widget in shell.json: the left section is the top of a side bar, the others
# the far end (the right, or the bottom of a side bar).
corner=$2
edge=$3
if [[ -z $corner ]]; then
  read -r edge section < <(jq -r '.bar as $bar | "\($bar.position // "top") \(
    [$bar.layout // {} | to_entries[] | select(any(.value[]?; .id == "schotime.deezer-player")) | .key][0] // "right")"' \
    "$HOME/.config/omarchy/shell.json" 2>/dev/null)
  edge=${edge:-top}
  case $edge in
    left | right) [[ $section == left ]] && corner=top-$edge || corner=bottom-$edge ;;
    *) [[ $section == left ]] && corner=$edge-left || corner=$edge-right ;;
  esac
fi
edge=${edge:-${corner%%-*}}

slide="$(dirname "$0")/slide-tui.sh"

# hide-tui.sh only slides the drop-down away after it has had focus since it
# last came down, so each toggle starts that over.
focused_flag="${XDG_RUNTIME_DIR:-/tmp}/deezer-tui-dropdown-focused"
rm -f "$focused_flag"

# The window rule only sizes and places the drop-down when it is first opened,
# and Hyprland centres it whenever it next opens on another monitor. So before
# dropping it in, put it in $corner of the focused monitor, inside the bar, at a
# third of that monitor's size; with its middle already there, Hyprland leaves
# it alone. Pass "force" to place it even while it is showing.
place_dropdown() {
  local monitor mx my lw lh left top right bottom w h x y
  monitor=$(hyprctl monitors -j | jq -c '.[] | select(.focused)')
  [[ $2 != force && $(jq -r '.specialWorkspace.name' <<<"$monitor") == special:deezer ]] && return

  read -r mx my lw lh left top right bottom < <(jq -r '"\(.x) \(.y) \((.width / .scale) | floor) \((.height / .scale) | floor) \(.reserved | map(tostring) | join(" "))"' <<<"$monitor")
  w=$((lw / 3))
  h=$((lh / 3))

  # The 8px offsets match general:gaps_out.
  if [[ $corner == *-left ]]; then x=$((mx + left + 8)); else x=$((mx + lw - right - w - 8)); fi
  if [[ $corner == top-* ]]; then y=$((my + top + 8)); else y=$((my + lh - bottom - h - 8)); fi

  hyprctl dispatch "hl.dsp.window.resize({ x = $w, y = $h, window = \"address:$1\" })" >/dev/null
  hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $y, window = \"address:$1\" })" >/dev/null
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
        if hyprctl monitors -j | jq -e '.[] | select(.focused) | .specialWorkspace.name == "special:deezer"' >/dev/null; then
          hyprctl dispatch 'hl.dsp.workspace.toggle_special("deezer")' >/dev/null
          setsid bash "$slide" restore >/dev/null 2>&1 &
        else
          place_dropdown "$address"
          bash "$slide" from "$edge"
          hyprctl dispatch 'hl.dsp.workspace.toggle_special("deezer")' >/dev/null
        fi
      else
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null
      fi
      exit 0
    fi
    p=$(awk '/^PPid:/ { print $2 }' "/proc/$p/status" 2>/dev/null)
  done
done

bash "$slide" from "$edge"
COLORTERM=truecolor omarchy-launch-tui --app-id=org.omarchy.deezer-tui "$binary" &

# The window rule drops a fresh TUI in at a fixed spot, so move it to $corner
# once it maps.
for _ in $(seq 50); do
  address=$(hyprctl clients -j | jq -r '.[] | select(.class == "org.omarchy.deezer-tui") | .address' | head -n1)
  if [[ -n $address ]]; then
    place_dropdown "$address" force
    exit 0
  fi
  sleep 0.1
done
