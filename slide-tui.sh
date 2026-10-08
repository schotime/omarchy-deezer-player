#!/bin/bash
# Point the special workspace slide at the bar edge the drop-down hangs off, so
# it comes out of the bar and goes back into it, then put the user's own slide
# back once it is hidden. Hyprland has one slide for every special workspace,
# so leaving it changed would also move the scratchpad's.
# Usage: slide-tui.sh from <top|bottom|left|right>
#        slide-tui.sh restore

saved="${XDG_RUNTIME_DIR:-/tmp}/deezer-tui-slide.json"

set_animation() {
  local leaf=$1 enabled=$2 speed=$3 bezier=$4 style=$5
  hyprctl eval "hl.animation({ leaf = \"$leaf\", enabled = $enabled, speed = $speed, bezier = \"${bezier:-default}\", style = \"$style\" })" >/dev/null
}

case $1 in
  from)
    # Only save the first time, so a second open doesn't save our own slide.
    [[ -e $saved ]] || hyprctl animations -j |
      jq -c '[.[0][] | select(.name == "specialWorkspaceIn" or .name == "specialWorkspaceOut")]' >"$saved"

    # The out style names the side it leaves from the far end of, so it's the
    # opposite edge: in from the top, out "bottom" goes back up.
    case $2 in
      bottom) in="slidevert bottom" out="slidevert top" ;;
      left) in="slide left" out="slide right" ;;
      right) in="slide right" out="slide left" ;;
      *) in="slidevert top" out="slidevert bottom" ;;
    esac
    IFS="|" read -r enabled speed bezier < <(jq -r '.[] | select(.name == "specialWorkspaceIn") | "\(.enabled)|\(.speed)|\(.bezier)"' "$saved")
    set_animation specialWorkspaceIn "$enabled" "$speed" "$bezier" "$in"
    IFS="|" read -r enabled speed bezier < <(jq -r '.[] | select(.name == "specialWorkspaceOut") | "\(.enabled)|\(.speed)|\(.bezier)"' "$saved")
    set_animation specialWorkspaceOut "$enabled" "$speed" "$bezier" "$out"
    ;;
  restore)
    [[ -e $saved ]] || exit 0
    # Let the slide out finish first, and leave ours in place if the drop-down
    # came back down meanwhile.
    sleep 1
    hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name == "special:deezer")' >/dev/null && exit 0
    jq -r '.[] | "\(.name)|\(.enabled)|\(.speed)|\(.bezier)|\(.style)"' "$saved" |
      while IFS="|" read -r leaf enabled speed bezier style; do
        set_animation "$leaf" "$enabled" "$speed" "$bezier" "$style"
      done
    rm -f "$saved"
    ;;
esac
