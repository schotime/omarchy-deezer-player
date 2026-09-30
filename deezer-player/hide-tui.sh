#!/bin/bash
# Slide the drop-down deezer-tui back up once focus has left it, but only after
# it has had focus since it came down, so opening it while focus sits elsewhere
# doesn't close it straight away. open-tui.sh clears the flag on every toggle.
# Usage: hide-tui.sh

focused_flag="${XDG_RUNTIME_DIR:-/tmp}/deezer-tui-dropdown-focused"

# Every bar (one per monitor) runs this for the same focus change, and a second
# toggle would slide the drop-down straight back down, so only one may run.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/deezer-tui-hide.lock"
flock -n 9 || exit 0

monitors=$(hyprctl monitors -j)
shown=$(jq -r '.[] | select(.specialWorkspace.name == "special:deezer") | .name' <<<"$monitors" | head -n1)

if [[ -z $shown ]]; then
  rm -f "$focused_flag"
  exit 0
fi

if [[ $(hyprctl activewindow -j | jq -r '.class // ""') == org.omarchy.deezer-tui ]]; then
  touch "$focused_flag"
  exit 0
fi

[[ -e $focused_flag ]] || exit 0
rm -f "$focused_flag"

focused=$(jq -r '.[] | select(.focused) | .name' <<<"$monitors")
toggle='hl.dsp.workspace.toggle_special("deezer")'

# toggle_special acts on the focused monitor, so when focus went to the other
# monitor, hop back to close it there and then return.
if [[ $shown == "$focused" ]]; then
  hyprctl dispatch "$toggle" >/dev/null
else
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$shown\" })" >/dev/null
  hyprctl dispatch "$toggle" >/dev/null
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$focused\" })" >/dev/null
fi
